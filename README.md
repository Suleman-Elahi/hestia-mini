# Hestia-Mini

A lightweight, standalone admin panel derived from [HestiaCP](https://github.com/hestiacp/hestiacp),
supporting four focused feature areas: **Email**, **Database**, **File Management**, and **Terminal**.

Hestia-Mini keeps HestiaCP's battle-tested core — its CLI command surface, shell
function library, and the PHP web UI — while removing everything unrelated to
mail, databases, file manager, and terminal: no web-hosting (Apache/PHP-FPM vhosts),
no DNS server, no FTP, no firewall rule management, no backups, no cron UI, and
no app marketplace.

> **Attribution & License:** Hestia-Mini is derived from HestiaCP and is
> distributed under the GNU General Public License v3. See
> [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md).

---

## Features

- **Email** — mail domains and accounts, aliases, auto-reply, forwarding,
  DKIM, antispam (SpamAssassin) and antivirus (ClamAV) toggles, quotas, and
  rate limits, backed by Exim + Dovecot.
- **Database** — MySQL/MariaDB (installed by default) and PostgreSQL (on-demand),
  with phpMyAdmin and phpPgAdmin web UIs served through a dedicated reverse
  proxy.
- **File Manager** — browser-based file management (Filegator).
- **Terminal** — web terminal and SSH shell access.
- **CLI-first** — a large `v-*` command suite under `bin/` for scripting and
  automation, plus a JSON API and shell API.
- **User & access management** — users, packages, roles, two-factor
  authentication, SSH/SFTP keys, notifications, and an API-key system.

### Explicitly not included

Apache, PHP-FPM web-hosting pools, BIND/named (DNS server), iptables/fail2ban
rule sets, FTP servers, vhost templates, per-domain Let's Encrypt automation,
cron UI, backup UI, and the quick-install app marketplace.

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

The installer is non-intrusive by default and automates admin-user creation,
phpMyAdmin, and the file manager. PostgreSQL can be installed on-demand at any time or during setup using `--postgresql`. Common flags:

```
--yes, -y             Assume yes to all prompts (non-interactive)
--purge-mta           Purge a conflicting stub MTA on port 25
--no-purge-mta        Never purge, just warn
--postgresql          Install PostgreSQL database engine during setup
--no-pgsql            Skip enabling PostgreSQL (default)
--no-pma              Skip installing phpMyAdmin
--no-pga              Skip installing phpPgAdmin
--no-filemanager      Skip installing the File Manager
--admin-email EMAIL   Admin contact email
--admin-password PASS Admin password
--proxy-port PORT     Reverse-proxy port for the DB web UIs (default 8080)
```

Fully non-interactive example:

```bash
sudo bash install/hestia-mini-install.sh --yes --purge-mta \
  --admin-email you@yourdomain.com --proxy-port 8090
```

After installing, **reboot once**, then follow the post-install checklist and
mail-deliverability DNS notes in [`docs/INSTALL.md`](docs/INSTALL.md).

### Spin up PostgreSQL On-Demand

If you need PostgreSQL later after initial setup, you can install and configure it anytime via CLI/panel using:

```bash
sudo /usr/local/hestia/bin/v-add-sys-pgsql
```

---

## Uninstall

```bash
sudo bash install/hestia-mini-uninstall.sh --dry-run     # preview only
sudo bash install/hestia-mini-uninstall.sh               # interactive
sudo bash install/hestia-mini-uninstall.sh --yes         # full removal
sudo bash install/hestia-mini-uninstall.sh --yes --keep-data       # keep mail/db data
sudo bash install/hestia-mini-uninstall.sh --yes --keep-packages   # leave apt packages installed
```

*(Note: `install/minipanel-uninstall.sh` is provided as a backward-compatible symlink)*

Uninstall is destructive by default — always run `--dry-run` first.

---

## Project structure

| Path | Purpose |
|---|---|
| `bin/` | CLI commands (`v-add-*`, `v-change-*`, `v-delete-*`, `v-list-*`, `v-suspend-*`, …) |
| `func/` | Shell function library (core `main.sh`, `db.sh`, `domain.sh`, `ip.sh`, `rebuild.sh`, `syshealth.sh`, `upgrade.sh`) |
| `web/` | Panel web UI (PHP) — `inc/` core, `add/`, `edit/`, `delete/`, `list/`, `login/`, `api/`, `src/`, themes, locale |
| `install/` | Installer (`hestia-mini-install.sh`), uninstaller (`hestia-mini-uninstall.sh`), and packaged config templates |
| `conf/` | Default panel configuration (`hestia.conf`, with `minipanel.conf` kept as a compatibility symlink) |
| `data/` | Runtime data (`users/`, `packages/`, `queue/`) |
| `docs/` | Documentation |

---

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — full install, deploy, and uninstall
  guide, including post-install checklist, firewall/ports reference, and mail
  deliverability (SPF/DKIM/DMARC/PTR) notes.

## License

Hestia-Mini is distributed under the [GNU General Public License v3](LICENSE).
This project is derived from [HestiaCP](https://github.com/hestiacp/hestiacp);
see [`NOTICE.md`](NOTICE.md) for attribution.
