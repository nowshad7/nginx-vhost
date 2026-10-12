#!/usr/bin/env bash
# `ok` always returns 0, so `cond && ok || fail` is a safe if/else here.
# shellcheck disable=SC2015
# Sandboxed tests for nginx-vhost. Needs no root, no nginx and no network:
# every path goes through the NGINX_VHOST_* overrides, and `nginx` is a stub.
#
#   ./tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/nginx-vhost"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# Stub nginx binaries: one accepts every config, one rejects every config.
mkdir -p "$WORK/nginx-pass" "$WORK/nginx-fail"
printf '#!/bin/sh\nexit 0\n' > "$WORK/nginx-pass/nginx"
printf '#!/bin/sh\necho "stub: config rejected" >&2\nexit 1\n' > "$WORK/nginx-fail/nginx"
chmod +x "$WORK"/nginx-*/nginx

# Fresh sandbox per test. Sets OUT and RC from the last `run`.
new_sandbox() {
  S="$WORK/sb.$RANDOM$RANDOM"
  mkdir -p "$S"/{available,enabled,ssl,log}
  printf '%s' "${1-}" > "$S/hosts"
}
run() {   # run <pass|fail> <args...>
  local stub="$1"; shift
  OUT="$(PATH="$WORK/nginx-$stub:$PATH" \
    NGINX_VHOST_AVAILABLE="$S/available" NGINX_VHOST_ENABLED="$S/enabled" \
    NGINX_VHOST_SSL_DIR="$S/ssl" NGINX_VHOST_HOSTS="$S/hosts" \
    NGINX_VHOST_LOG_DIR="$S/log" "$BIN" "$@" 2>&1)"
  RC=$?
}
has()    { printf '%s' "$OUT" | grep -qF -- "$1"; }
no_tmp() { [ ! -e "$S/hosts.nvtmp" ]; }
no_conf() { [ -z "$(ls -A "$S/available")" ] && [ -z "$(ls -A "$S/enabled")" ]; }

valid_json() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -e . >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then printf '%s' "$1" | python3 -m json.tool >/dev/null 2>&1
  else return 0
  fi
}

echo "help and validation"
new_sandbox
run pass help;                      [ $RC -eq 0 ] && has "USAGE" && ok "help" || fail "help" "$OUT"
run pass version;                   [ $RC -eq 0 ] && has "nginx-vhost " && ok "version" || fail "version" "$OUT"
run pass add bad_domain 3000;       [ $RC -eq 1 ] && has "invalid domain" && ok "rejects invalid domain" || fail "rejects invalid domain" "$OUT"
run pass add x.local nonsense;      [ $RC -eq 1 ] && has "unrecognized target" && ok "rejects bad target" || fail "rejects bad target" "$OUT"
run pass add x.local 3000 --bogus;  [ $RC -eq 1 ] && has "unknown option" && ok "rejects unknown option" || fail "rejects unknown option" "$OUT"
run pass frobnicate;                [ $RC -eq 1 ] && has "unknown command" && ok "rejects unknown command" || fail "rejects unknown command" "$OUT"

echo "dry run writes nothing"
new_sandbox
run fail add app.local 3000 --dry-run
[ $RC -eq 0 ] && has "proxy_pass http://127.0.0.1:3000;" && ok "port -> proxy" || fail "port -> proxy" "$OUT"
run fail add app.local example.com:8080 --dry-run
has "proxy_pass http://example.com:8080;" && ok "host:port -> proxy" || fail "host:port -> proxy" "$OUT"
run fail add app.local https://api.example.com --dry-run
has "proxy_pass https://api.example.com;" && ok "URL -> proxy" || fail "URL -> proxy" "$OUT"
mkdir -p "$WORK/site" "$WORK/phpapp"; touch "$WORK/phpapp/index.php"
run fail add site.local "$WORK/site" --dry-run
has "try_files \$uri \$uri/ =404;" && ok "directory -> static" || fail "directory -> static" "$OUT"
run fail add php.local "$WORK/phpapp" --dry-run --php-sock /run/php/test.sock
has "fastcgi_pass unix:/run/php/test.sock;" && ok "index.php -> PHP" || fail "index.php -> PHP" "$OUT"
run fail add a.local 3000 --alias "b.local,c.local" --dry-run
has "server_name a.local b.local c.local;" && ok "aliases" || fail "aliases" "$OUT"
no_conf && [ ! -s "$S/hosts" ] && ok "no files written" || fail "no files written"

echo "add / list / rm"
new_sandbox $'127.0.0.1\tlocalhost\n'
run pass add app.local 3000
[ $RC -eq 0 ] && [ -f "$S/available/app.local.conf" ] && [ -L "$S/enabled/app.local.conf" ] \
  && ok "add writes config and symlink" || fail "add writes config and symlink" "$OUT"
grep -q "# nginx-vhost:app.local$" "$S/hosts" && grep -q localhost "$S/hosts" \
  && ok "add updates hosts, keeps other lines" || fail "add updates hosts, keeps other lines" "$(cat "$S/hosts")"
run pass add app.local 4000;        [ $RC -eq 1 ] && has "already exists" && ok "refuses duplicate without --force" || fail "refuses duplicate without --force" "$OUT"
run pass add app.local 4000 --force
[ $RC -eq 0 ] && [ "$(grep -c 'nginx-vhost:app.local' "$S/hosts")" -eq 1 ] \
  && ok "--force replaces, single hosts entry" || fail "--force replaces, single hosts entry" "$(cat "$S/hosts")"
run pass list;                      has "app.local" && has "proxy" && ok "list table" || fail "list table" "$OUT"
run pass list --json
if valid_json "$OUT" && has '"domain": "app.local"' && has '"target": "4000"' && has '"enabled": true'; then
  ok "list --json"; else fail "list --json" "$OUT"; fi
rm "$S/enabled/app.local.conf"
run pass list --json;               has '"enabled": false' && ok "list --json shows disabled" || fail "list --json shows disabled" "$OUT"
run pass rm app.local
[ $RC -eq 0 ] && [ ! -e "$S/available/app.local.conf" ] && ! grep -q app.local "$S/hosts" \
  && grep -q localhost "$S/hosts" && ok "rm cleans up" || fail "rm cleans up" "$OUT"
run pass list --json;               [ "$OUT" = "[]" ] && ok "list --json empty" || fail "list --json empty" "$OUT"

echo "JSON escaping"
new_sandbox
printf '# nginx-vhost: domain=q.local mode=static target=/srv/a "b"\\c\tz\n' > "$S/available/q.local.conf"
run pass list --json
valid_json "$OUT" && ok "quotes, backslashes and tabs escaped" || fail "quotes, backslashes and tabs escaped" "$OUT"

echo "rollback when nginx rejects the config"
new_sandbox $'127.0.0.1\tlocalhost\n'
run fail add bad.local 3000
[ $RC -eq 1 ] && has "rolled back" && no_conf \
  && ! grep -q bad.local "$S/hosts" && no_tmp && ok "full rollback" || fail "full rollback" "$OUT"

echo "hosts file holding only managed entries"
new_sandbox
run fail add x.local 3000
[ $RC -eq 1 ] && has "rolled back" && [ ! -s "$S/hosts" ] && no_tmp \
  && ok "rollback with empty hosts" || fail "rollback with empty hosts" "$OUT"
run pass add x.local 3000 && run pass add x.local 4000 --force
[ $RC -eq 0 ] && [ "$(grep -c 'nginx-vhost:x.local' "$S/hosts")" -eq 1 ] && no_tmp \
  && ok "re-add when it is the only line" || fail "re-add when it is the only line" "$OUT"
run pass rm x.local
[ $RC -eq 0 ] && [ ! -s "$S/hosts" ] && no_tmp && ok "rm the only line" || fail "rm the only line" "$OUT"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
