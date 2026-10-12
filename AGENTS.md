# AGENTS.md

Guidance for AI coding agents working on or with `nginx-vhost`. For what the
tool does and how people use it, read [README.md](README.md) first.

## Repo layout

| File | Purpose |
| --- | --- |
| `nginx-vhost` | The whole tool: a single Bash script (`set -euo pipefail`) |
| `install.sh` | Copies `nginx-vhost` to `$PREFIX` (default `/usr/local/bin`) |
| `README.md` | User-facing docs: keep it in sync with `usage()` in the script |
| `tests/run.sh` | Sandboxed test suite: no root, nginx or network needed |
| `.github/workflows/ci.yml` | CI: runs shellcheck and `tests/run.sh` on every push and PR |
| `.github/workflows/release.yml` | On a `v*` tag: checks `VERSION`, runs the checks, attaches the script and its sha256 to the release |
| `CHANGELOG.md` | Release history ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) |
| `llms.txt` | Short summary of the project for LLMs |

There are no dependencies to install and no build step.

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
machines without nginx, the `add` rolls back and exits 1. To exercise the
real write path anyway, put a stub `nginx` that exits 0 first on `PATH`.
`tests/run.sh` does exactly this, with stubs that accept and reject.

## Output and exit codes

- Progress goes to stdout (`==>` and indented step lines). Warnings and errors
  go to stderr, prefixed `warning:` or `error:`.
- Colors are turned off when stdout isn't a TTY, so piped output is plain text.
- The exit code is `0` on success and `1` on any error (`die`). The script has
  no other exit codes.
- For machine-readable state, use `list --json`. Parse that rather than the
  table:

  ```json
  [
    {"domain": "app.local", "mode": "proxy", "target": "3000", "enabled": true, "config": "/etc/nginx/sites-available/app.local.conf"}
  ]
  ```

  `mode` is `proxy`, `static` or `php`. `target` is the value as the user
  typed it. `enabled` is `false` when the `sites-enabled` symlink is missing.
  An empty list prints `[]`.
- A config counts as managed only if it has a
  `# nginx-vhost: domain=... mode=... target=...` header line.

## Checks before committing changes to the script

CI runs exactly these commands, so run them first:

```bash
shellcheck nginx-vhost install.sh tests/run.sh
./tests/run.sh
```

If `shellcheck` isn't installed, `pip install shellcheck-py` provides it. When
you change behavior, add a case to `tests/run.sh`.

## Conventions

- Keep the tool a single dependency-free Bash script. Don't add Python, Node,
  or other runtimes.
- Every new write path must honor `--dry-run` and get an `NGINX_VHOST_*`
  override.
- Changes to nginx config must go through `nginx_validate_reload`, so the
  validate-then-roll-back guarantee still holds.
- When you add or change an option, update `usage()`, the README options table,
  and this file together.
- `rm` doesn't prompt for confirmation, on purpose: the tool has to stay usable
  from scripts. Agents should confirm with the user before running `rm`.
- Note user-visible changes under a new version heading in `CHANGELOG.md`.
  To release: set `VERSION` in `nginx-vhost` to match the heading, merge,
  then push a `vX.Y.Z` tag. The release workflow refuses a tag that doesn't
  match `VERSION`, and it uses that heading's section as the release notes. To backfill
  an existing release, run the Release workflow manually (Actions → Release →
  Run workflow) with the tag. It only fills in notes that are empty.
- Temporary files go through `mktemp`, never a fixed `/tmp` path: the script
  runs as root.
- Generated configs keep the `MANAGED_MARKER` line and the `# nginx-vhost:`
  metadata line. `list` and `rm` depend on both.
