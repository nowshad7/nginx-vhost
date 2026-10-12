# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-10-12

### Security

- `nginx -t` output now goes to a `mktemp` file instead of the predictable
  `/tmp/nginx-vhost-test.<pid>`. The script runs as root, so a local user could
  plant a symlink at the fixed path and make it overwrite an arbitrary file.

### Added

- One-line install from the latest GitHub release. Every release attaches
  `nginx-vhost` and `nginx-vhost.sha256`.
- CI, release and license badges in the README.

## [1.0.0] - 2026-10-12

### Added

- `add`, `rm` and `list` commands for reverse proxy, static and PHP-FPM vhosts.
- Validation with `nginx -t` before reload, with automatic rollback on failure.
- `/etc/hosts` management, local HTTPS via mkcert (`--ssl`), and `--dry-run`.
- `list --json` for scripts and agents.
- Sandboxed test suite, CI, `AGENTS.md` and `llms.txt`.

### Fixed

- Removing the last nginx-vhost entry from a hosts file no longer aborts
  partway through a rollback.

[1.0.1]: https://github.com/nowshad7/nginx-vhost/releases/tag/v1.0.1
[1.0.0]: https://github.com/nowshad7/nginx-vhost/releases/tag/v1.0.0
