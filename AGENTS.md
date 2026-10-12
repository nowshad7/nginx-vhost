# AGENTS.md

Guidance for AI coding agents working on or with `nginx-vhost`. For what the
tool does and how people use it, read [README.md](README.md) first.

## Repo layout

| File | Purpose |
| --- | --- |
| `nginx-vhost` | The whole tool: a single Bash script (`set -euo pipefail`) |
| `install.sh` | Copies `nginx-vhost` to `$PREFIX` (default `/usr/local/bin`) |
| `README.md` | User-facing docs: keep it in sync with `usage()` in the script |

There are no dependencies to install, no build step, and no test suite yet.

## Safe by default: use `--dry-run`

`--dry-run` is the safe way to see what the tool does. It prints the server
block it would write, the `/etc/hosts` line, and the reload it would run, and
then exits 0 without writing anything. It also skips the sudo step, so it
works without root and without nginx installed.

```bash
./nginx-vhost add app.local 3000 --dry-run
./nginx-vhost add shop.local /var/www/shop --php --dry-run
./nginx-vhost rm app.local --dry-run
```

These commands never write either:

```bash
./nginx-vhost help
./nginx-vhost version
./nginx-vhost list
```

Exception: `--ssl` checks for `mkcert` **before** it looks at `--dry-run`, so
`add ... --ssl --dry-run` fails when `mkcert` is missing.

## Commands that write, and what they need

`add` and `rm` change the live system:

- They write to `/etc/nginx/sites-available/`, `/etc/nginx/sites-enabled/`,
  `/etc/nginx/ssl/` (with `--ssl`), and `/etc/hosts`.
- They run `nginx -t` and then reload nginx through `systemctl` or `nginx -s reload`.
- `rm` deletes without asking for confirmation.

**Root:** if the target paths aren't writable, the script re-runs itself with
`sudo -E`. A non-interactive session with no TTY and no passwordless sudo
can't answer the password prompt and fails. Don't run `add` or `rm` for real
on a user's machine unless they asked you to.

**Rollback:** if `nginx -t` fails after `add`, the script deletes the new
config, removes the symlink and the `/etc/hosts` line, and exits 1. A failed
`add` leaves nginx as it was.

## Sandboxing with environment overrides

These variables point every path the script writes at a scratch directory:

```bash
SANDBOX="$(mktemp -d)"
mkdir -p "$SANDBOX"/{available,enabled,ssl,log}
printf '127.0.0.1\tlocalhost\n' > "$SANDBOX/hosts"
export NGINX_VHOST_AVAILABLE="$SANDBOX/available" \
       NGINX_VHOST_ENABLED="$SANDBOX/enabled" \
       NGINX_VHOST_SSL_DIR="$SANDBOX/ssl" \
       NGINX_VHOST_HOSTS="$SANDBOX/hosts" \
       NGINX_VHOST_LOG_DIR="$SANDBOX/log"
```

If these paths are writable, the script skips sudo. Be aware that
`nginx -t` still tests the **system** nginx config, not the sandbox. So a real
`add` in the sandbox only succeeds where nginx is installed and runnable. On
machines without nginx, the `add` rolls back and exits 1. In that case use
`--dry-run`, or use `list` and `rm` against configs you create by hand.

## Output and exit codes

- Progress goes to stdout (`==>` and indented step lines). Warnings and errors
  go to stderr, prefixed `warning:` or `error:`.
- Colors are turned off when stdout isn't a TTY, so piped output is plain text.
- The exit code is `0` on success and `1` on any error (`die`). The script has
  no other exit codes.
- `list` prints a fixed-width table and has no JSON mode. A config counts as
  managed only if it has a `# nginx-vhost: domain=... mode=... target=...`
  header line.

## Checks before committing changes to the script

```bash
bash -n nginx-vhost                      # syntax
shellcheck nginx-vhost install.sh        # if shellcheck is installed
./nginx-vhost help
./nginx-vhost add app.local 3000 --dry-run
./nginx-vhost add web.local example.com:8080 --dry-run
./nginx-vhost add docs.local "$(mktemp -d)" --static --dry-run
./nginx-vhost add bad_domain 3000 --dry-run; echo "exit=$?"   # expect exit=1
```

## Conventions

- Keep the tool a single dependency-free Bash script. Don't add Python, Node,
  or other runtimes.
- Every new write path must honor `--dry-run` and get an `NGINX_VHOST_*`
  override.
- Changes to nginx config must go through `nginx_validate_reload`, so the
  validate-then-roll-back guarantee still holds.
- When you add or change an option, update `usage()`, the README options table,
  and this file together.
- Generated configs keep the `MANAGED_MARKER` line and the `# nginx-vhost:`
  metadata line. `list` and `rm` depend on both.
