# Hestia-Mini

A lightweight, standalone admin panel derived from [HestiaCP](https://github.com/hestiacp/hestiacp),
supporting four focused feature areas: **Email**, **Domain Management**,
**File Management**, and **Terminal**.

Hestia-Mini keeps HestiaCP's battle-tested core — its CLI command surface, shell
function library, and the PHP web UI — while removing everything unrelated to
mail, domain management, file manager, and terminal: no web-hosting
(Apache/PHP-FPM vhosts), no database management, no DNS server, no FTP, no
firewall rule management, no backups, no cron UI, and no app marketplace.

> **Attribution & License:** Hestia-Mini is derived from HestiaCP and is
> distributed under the GNU General Public License v3. See
> [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md).

---

## Features

- **Email** — mail domains and accounts, aliases, auto-reply, forwarding,
  DKIM, antispam (SpamAssassin) and antivirus (ClamAV) toggles, quotas, and
  rate limits, backed by Exim + Dovecot.
- **Domain Management** — add, edit, list, and remove domains with Nginx
  reverse proxying and load balancing (round_robin, weighted, least_conn,
  ip_hash, hash). Supports multiple backend targets per domain and optional
  Let's Encrypt SSL.
- **File Manager** — browser-based file management (Filegator).
- **Terminal** — web terminal (xterm.js over WebSocket) and SSH shell access.
- **CLI-first** — a large `v-*` command suite under `bin/` for scripting and
  automation, plus a JSON API and shell API.
- **User & access management** — users, packages, roles, two-factor
  authentication, SSH/SFTP keys, notifications, and an API-key system.

### Explicitly not included

Apache, PHP-FPM web-hosting pools, BIND/named (DNS server), MySQL/MariaDB,
PostgreSQL, iptables/fail2ban rule sets, FTP servers, vhost templates,
per-domain Let's Encrypt automation, cron UI, backup UI, and the quick-install
app marketplace.

---

## Requirements

- A dedicated **Debian 11/12/13** or **Ubuntu 22.04/24.04/26.04** server, **or** a
  server that already runs another control panel (e.g. 1Panel) that you don't
  want to conflict with.
- Root SSH access.
- A registered domain/hostname (required for correct SPF/DKIM/reverse-DNS mail
  deliverability).
- Outbound internet access during install.

Isolation from an existing panel is achieved through distinct ports and avoiding
services the other panel already owns — not containerization. See
[`docs/INSTALL.md`](docs/INSTALL.md#11-if-this-host-already-runs-another-panel-eg-1panel).

---

## Quick install

```bash
git clone <your-hestia-mini-repo-url> /usr/local/src/hestia-mini
cd /usr/local/src/hestia-mini
sudo bash install/hestia-mini-install.sh
```

*(Note: `install/minipanel-install.sh` is provided as a backward-compatible symlink)*

The installer is non-intrusive by default and automates admin-user creation
and the file manager. Common flags:

```
--yes, -y             Assume yes to all prompts (non-interactive)
--purge-mta           Purge a conflicting stub MTA on port 25
--no-purge-mta        Never purge, just warn
--no-filemanager      Skip installing the File Manager
--admin-email EMAIL   Admin contact email
--admin-password PASS Admin password
```

Fully non-interactive example:

```bash
sudo bash install/hestia-mini-install.sh --yes --purge-mta \
  --admin-email you@yourdomain.com
```

After installing, **reboot once**, then follow the post-install checklist and
mail-deliverability DNS notes in [`docs/INSTALL.md`](docs/INSTALL.md).

---

## Uninstall

```bash
sudo bash install/hestia-mini-uninstall.sh --dry-run     # preview only
sudo bash install/hestia-mini-uninstall.sh               # interactive
sudo bash install/hestia-mini-uninstall.sh --yes         # full removal
sudo bash install/hestia-mini-uninstall.sh --yes --keep-data       # keep mail data
sudo bash install/hestia-mini-uninstall.sh --yes --keep-packages   # leave apt packages installed
```

*(Note: `install/minipanel-uninstall.sh` is provided as a backward-compatible symlink)*

Uninstall is destructive by default — always run `--dry-run` first.

---

## Project structure

| Path | Purpose |
|---|---|
| `bin/` | CLI commands (`v-add-*`, `v-change-*`, `v-delete-*`, `v-list-*`, `v-suspend-*`, …) |
| `func/` | Shell function library (`main.sh`, `domain.sh`, `domain_proxy.sh`, `ip.sh`, `rebuild.sh`, `syshealth.sh`, `upgrade.sh`) |
| `src/` | Backend source files (e.g. `deb/web-terminal/` — Node.js WebSocket-to-PTY bridge) |
| `web/` | Panel web UI (PHP) — `inc/` core, `add/`, `edit/`, `delete/`, `list/`, `login/`, `api/`, `src/`, themes, locale |
| `web/css/src/`, `web/js/src/` | Front-end sources compiled into `web/css/themes/*.min.css` and `web/js/dist/*` |
| `build.js`, `package.json` | Front-end asset build (esbuild + Lightning CSS) |
| `install/` | Installer (`hestia-mini-install.sh`), uninstaller (`hestia-mini-uninstall.sh`), and packaged config templates |
| `conf/` | Default panel configuration (`hestia.conf`, with `minipanel.conf` kept as a compatibility symlink) |
| `data/` | Runtime data (`users/`, `packages/`, `queue/`) |
| `docs/` | Documentation |

---

## Front-end build

`web/css/src/**` (styles) and `web/js/src/**` (scripts) are the panel's real
front-end sources. They are compiled into `web/css/themes/*.min.css` and
`web/js/dist/*`:

```bash
npm install
npm run build
```

The installer runs this automatically, so a fresh install always deploys
Hestia-Mini's own UI (the upstream `hestia` package only ships upstream's
prebuilt bundles). After changing anything under `web/css/src` or
`web/js/src`, re-run `npm run build` and redeploy the built files.

---

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — full install, deploy, and uninstall
  guide, including post-install checklist, firewall/ports reference, and mail
  deliverability (SPF/DKIM/DMARC/PTR) notes.

## License

Hestia-Mini is distributed under the [GNU General Public License v3](LICENSE).
This project is derived from [HestiaCP](https://github.com/hestiacp/hestiacp);
see [`NOTICE.md`](NOTICE.md) for attribution.
