# nginx-vhost

Point any local domain at any location — a reverse proxy, a static site, or a
PHP app — with a single command. Think of it as the nginx answer to the classic
Apache `vhost` helper scripts, but safer and with teardown built in.

```bash
nginx-vhost add app.local 3000            # proxy -> http://127.0.0.1:3000
nginx-vhost add web.local 8080           # proxy -> http://127.0.0.1:8080
nginx-vhost add shop.local /var/www/shop         # static or PHP (auto-detected)
nginx-vhost add api.local http://127.0.0.1:9000  # proxy to any URL
nginx-vhost list                                 # show what's configured
nginx-vhost rm  app.local                 # clean teardown
```

## Why

Spinning up a friendly local domain for a dev service usually means hand-editing
`/etc/nginx/sites-available/<name>.conf`, symlinking it into `sites-enabled/`,
adding a line to `/etc/hosts`, and reloading nginx — every single time. Miss a
semicolon and a blind `reload` can take your whole nginx down.

`nginx-vhost` does all of that in one command and, unlike the old Apache
scripts, **validates the config with `nginx -t` before it reloads** — if the new
vhost is invalid it rolls the change back automatically, so a typo never breaks
your running server.

## What it does for you

- **Auto-detects the target.** A bare port, a `host:port`, a full URL → reverse
  proxy. A directory → static site, or a PHP-FPM app if it sees an `index.php`.
- **Manages `/etc/hosts`** so the domain resolves to `127.0.0.1` (override with
  `--ip`, skip with `--no-hosts`).
- **Validates before reloading** and **rolls back on failure** — your running
  nginx is never left broken.
- **Clean teardown** — `rm` deletes the config, the symlink, the `/etc/hosts`
  line, and any generated certificate.
- **`list`** shows every vhost it manages and where each one points.
- **Local HTTPS** with `--ssl` via [mkcert](https://github.com/FiloSottile/mkcert).
- **WebSocket-ready** proxy headers out of the box.
- **`--dry-run`** prints exactly what it would do without writing anything.

## Install

```bash
sudo ./install.sh          # copies nginx-vhost to /usr/local/bin
# or manually:
sudo install -m 0755 nginx-vhost /usr/local/bin/nginx-vhost
```

Requires `nginx` and `bash`. PHP apps need `php-fpm`. HTTPS needs `mkcert`.

## Usage

```
nginx-vhost add <domain> <target> [options]
nginx-vhost rm  <domain>
nginx-vhost list
nginx-vhost help
```

### Target forms

| You type | Result |
| --- | --- |
| `3000` | reverse proxy to `http://127.0.0.1:3000` |
| `127.0.0.1:8080` | reverse proxy to `http://127.0.0.1:8080` |
| `http://localhost:9000` | reverse proxy to that URL |
| `/var/www/app` | static site, or PHP-FPM if `index.php` is present |

### Options

| Option | Meaning |
| --- | --- |
| `--php` | force PHP-FPM mode for a directory target |
| `--static` | force static mode for a directory target |
| `--php-sock <path>` | PHP-FPM socket (default: auto-detected, else `127.0.0.1:9000`) |
| `--alias <names>` | extra `server_name` aliases (space/comma separated) |
| `--ssl` | add local HTTPS via mkcert and redirect HTTP → HTTPS |
| `--ip <addr>` | `/etc/hosts` IP for the domain (default `127.0.0.1`) |
| `--port <n>` | HTTP listen port (default `80`) |
| `--no-hosts` | don't touch `/etc/hosts` |
| `--force` | overwrite an existing vhost of the same name |
| `--dry-run` | print what would happen; write nothing |

### Examples

```bash
# Reverse proxy a dev server
nginx-vhost add app.local 3000

# A Laravel / Symfony app with local HTTPS
nginx-vhost add shop.local /var/www/shop/public --php --ssl

# A static build with an extra alias
nginx-vhost add docs.local /var/www/docs/dist --alias www.docs.local

# See everything, then remove one
nginx-vhost list
nginx-vhost rm docs.local
```

## How it's wired

Config files live in `/etc/nginx/sites-available/<domain>.conf`, symlinked into
`sites-enabled/`. Each file carries a machine-readable header line so `list` and
`rm` can find and manage only the vhosts this tool created:

```nginx
# Managed by nginx-vhost - edit via `nginx-vhost`, not by hand
# nginx-vhost: domain=shop.local mode=php target=/var/www/shop
```

Paths can be overridden with environment variables (`NGINX_VHOST_AVAILABLE`,
`NGINX_VHOST_ENABLED`, `NGINX_VHOST_SSL_DIR`, `NGINX_VHOST_HOSTS`,
`NGINX_VHOST_LOG_DIR`) if your distro lays nginx out differently.

## License

MIT — see [LICENSE](LICENSE).
