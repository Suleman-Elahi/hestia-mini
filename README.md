# MiniPanel

A stripped-down admin panel derived from [HestiaCP](https://github.com/hestiacp/hestiacp),
supporting exactly three feature areas: **Email**, **Database**, and **File Management**.

MiniPanel keeps HestiaCP's battle-tested core — its CLI command surface, shell
function library, and the PHP web UI — while removing everything unrelated to
mail, databases, and the file manager: no web-hosting (Apache/PHP-FPM vhosts),
no DNS server, no FTP, no firewall rule management, no backups, no cron UI, and
no app marketplace.

> **Attribution & License:** MiniPanel is derived from HestiaCP and is
> distributed under the GNU General Public License v3. See
> [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md).

---

## Features

- **Email** — mail domains and accounts, aliases, auto-reply, forwarding,
  DKIM, antispam (SpamAssassin) and antivirus (ClamAV) toggles, quotas, and
  rate limits, backed by Exim + Dovecot.
- **Database** — MySQL/MariaDB and PostgreSQL database and user management,
  with phpMyAdmin and phpPgAdmin web UIs served through a dedicated reverse
  proxy.
- **File Manager** — browser-based file management (Filegator).
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

- A dedicated **Debian 12/13** or **Ubuntu 22.04/24.04/26.04** server, **or** a
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
git clone <your-minipanel-repo-url> /usr/local/src/minipanel
cd /usr/local/src/minipanel
sudo bash install/minipanel-install.sh
```

The installer is interactive by default and automates admin-user creation,
phpMyAdmin, phpPgAdmin, the file manager, and PostgreSQL enablement. Common
flags:

```
--yes, -y             Assume yes to all prompts (non-interactive)
--purge-mta           Purge a conflicting stub MTA on port 25
--no-purge-mta        Never purge, just warn
--no-pgsql            Skip enabling PostgreSQL
--no-pma              Skip installing phpMyAdmin
--no-pga              Skip installing phpPgAdmin
--no-filemanager      Skip installing the File Manager
--admin-email EMAIL   Admin contact email
--admin-password PASS Admin password
--proxy-port PORT     Reverse-proxy port for the DB web UIs (default 8080)
```

Fully non-interactive example:

```bash
sudo bash install/minipanel-install.sh --yes --purge-mta \
  --admin-email you@yourdomain.com --proxy-port 8090
```

After installing, **reboot once**, then follow the post-install checklist and
mail-deliverability DNS notes in [`docs/INSTALL.md`](docs/INSTALL.md).

## Uninstall

```bash
sudo bash install/minipanel-uninstall.sh --dry-run     # preview only
sudo bash install/minipanel-uninstall.sh               # interactive
sudo bash install/minipanel-uninstall.sh --yes         # full removal
sudo bash install/minipanel-uninstall.sh --yes --keep-data       # keep mail/db data
sudo bash install/minipanel-uninstall.sh --yes --keep-packages   # leave apt packages installed
```

Uninstall is destructive by default — always run `--dry-run` first.

---

## Project structure

| Path | Purpose |
|---|---|
| `bin/` | CLI commands (`v-add-*`, `v-change-*`, `v-delete-*`, `v-list-*`, `v-suspend-*`, …) |
| `func/` | Shell function library (core `main.sh`, `db.sh`, `domain.sh`, `ip.sh`, `rebuild.sh`, `syshealth.sh`, `upgrade.sh`) |
| `web/` | Panel web UI (PHP) — `inc/` core, `add/`, `edit/`, `delete/`, `list/`, `login/`, `api/`, `src/`, themes, locale |
| `install/` | Installer, uninstaller, and packaged config templates |
| `conf/` | Default panel configuration (`minipanel.conf`) |
| `data/` | Runtime data (`users/`, `packages/`, `queue/`) |
| `docs/` | Documentation |

---

## Documentation

- [`docs/INSTALL.md`](docs/INSTALL.md) — full install, deploy, and uninstall
  guide, including post-install checklist, firewall/ports reference, and mail
  deliverability (SPF/DKIM/DMARC/PTR) notes.

## License

MiniPanel is distributed under the [GNU General Public License v3](LICENSE).
This project is derived from [HestiaCP](https://github.com/hestiacp/hestiacp);
see [`NOTICE.md`](NOTICE.md) for attribution.
