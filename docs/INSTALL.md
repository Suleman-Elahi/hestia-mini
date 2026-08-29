# MiniPanel Install & Deploy Guide

This document describes how to install and configure MiniPanel, the
stripped-down HestiaCP derivative that supports Mail, Database, and File
Manager only. It reflects the actual current state of the `minipanel/`
codebase, including a handful of remaining manual steps documented in
Section 4.1.

Derived from HestiaCP (GPLv3) — see `LICENSE` and `NOTICE.md`.

---

## 1. Requirements

- A dedicated Debian 12/13 or Ubuntu 22.04/24.04/26.04 VPS/server, **or** a
  server that already runs another control panel (e.g. 1Panel) that you do
  not want to conflict with.
- Root SSH access.
- A registered domain/hostname if you want mail to work properly (SPF/DKIM/
  reverse DNS all depend on DNS being correctly pointed at this host — see
  Section 6).
- Outbound internet access (the installer pulls packages from the
  distro's package manager and the Hestia package repository).

### 1.1 If this host already runs another panel (e.g. 1Panel)

Isolation from another panel is achieved through **distinct ports and
avoiding services the other panel already owns** — not containerization.
Before installing, run this audit and record the results:

```bash
ss -tlnp
dpkg -l | grep -E 'nginx|mysql|mariadb|postgresql|exim|postfix|dovecot'
systemctl list-units --type=service --state=running \
  | grep -E 'nginx|mysql|maria|postgres|mail|exim|postfix|dovecot'
```

Confirm before proceeding:
- Which ports the other panel's reverse proxy/dashboard already occupy
  (commonly 80, 443, and its own dashboard port).
- Whether a stub MTA (Postfix/Exim as a local-only relay) is already bound
  to port 25 — common on default Debian/Ubuntu installs. It must be
  removed before Exim can bind port 25. The installer detects this and
  offers to purge it interactively, or pass `--purge-mta`/`--no-purge-mta`
  to control the behavior non-interactively.
- Whether the other panel already manages a MySQL/MariaDB/PostgreSQL
  instance on this host.
- Whether the other panel already manages the firewall (iptables/nftables).
  MiniPanel's installer does not touch firewall rules; if you need ports
  opened, do so through your existing firewall management (or manually via
  `ufw`/`iptables`/`nft`), not through this installer.

---

## 2. What gets installed

| Component | Purpose | Managed by |
|---|---|---|
| `hestia-nginx` + `hestia-php` | Panel's own web UI, dedicated port | MiniPanel |
| System `nginx` | Reverse proxy for phpMyAdmin/phpPgAdmin only | MiniPanel |
| Exim | SMTP (mail transfer) | MiniPanel |
| Dovecot | IMAP/POP3 | MiniPanel |
| ClamAV | Antivirus scanning for mail | MiniPanel |
| SpamAssassin | Antispam scoring for mail | MiniPanel |
| MariaDB/MySQL | Database engine | MiniPanel |
| PostgreSQL | Database engine | MiniPanel (skip with `--no-pgsql`) |
| File manager (Filegator) | Browser-based file management | MiniPanel (skip with `--no-filemanager`) |
| phpMyAdmin / phpPgAdmin | Database web UIs | MiniPanel (skip with `--no-pma` / `--no-pga`) |
| Admin user account | Panel login | MiniPanel (auto-created; use `--admin-email`/`--admin-password` to customize) |

Explicitly **not** installed: Apache, PHP-FPM web-hosting pool, BIND/named
(DNS server), iptables/fail2ban rule sets, vsftpd/proftpd (FTP), vhost
templates, per-domain Let's Encrypt automation, cron job UI, backup UI,
app/quick-install marketplace.

---

## 3. Quick install

```bash
git clone <your-minipanel-repo-url> /usr/local/src/minipanel
cd /usr/local/src/minipanel
sudo bash install/minipanel-install.sh
```

The installer will:
1. Verify it's running as root, on a supported OS (warns and asks for
   confirmation on untested Debian/Ubuntu point releases).
2. Check for port conflicts on the panel port (8083, falling back to
   8084-8090), the reverse-proxy port (8080 by default, or `--proxy-port`),
   and the phpMyAdmin/phpPgAdmin internal backend ports; picks an
   alternate port or aborts with a clear message rather than silently
   colliding with an existing service.
3. Detect a conflicting stub MTA on port 25 and offer to purge it
   (`--purge-mta` / `--no-purge-mta` to control this non-interactively).
4. Detect an already-running MySQL/MariaDB or PostgreSQL instance and
   offer to reuse it instead of installing a second one.
5. Install packages: `hestia-nginx`, `hestia-php`, Exim, Dovecot, ClamAV,
   SpamAssassin, MariaDB, MySQL client libs, PostgreSQL, PHP-FPM, plus a
   fixed PHP version (currently 8.2) for the panel and DB web UIs.
6. Create the `hestiaweb` (panel) and `hestiamail` (mail/db service)
   system users and the `hestia-users` group.
7. Copy `bin/`, `func/`, `web/`, and `install/deb`+`install/common`
   resources into `/usr/local/hestia/`.
8. Write `/usr/local/hestia/conf/minipanel.conf` and symlink
   `/etc/hestiacp/hestia.conf` to it.
9. Configure Exim, Dovecot (2.3 or 2.4 template, auto-detected), ClamAV,
   and SpamAssassin from the Hestia install tree's templates.
10. Enable/start MariaDB and (unless `--no-pgsql`) PostgreSQL.
11. Configure a PHP-FPM pool, then download, install, and configure
    phpMyAdmin (unless `--no-pma`) and phpPgAdmin (unless `--no-pga`),
    including creating the phpMyAdmin control database/user and the
    PostgreSQL password-auth `pg_hba.conf` entries.
12. Write a reverse-proxy nginx config for phpMyAdmin/phpPgAdmin on the
    checked/available port.
13. Write a scoped sudoers file limiting `hestiaweb` to running only
    `/usr/local/hestia/bin/*` scripts.
14. Set up a small crontab for queue processing and self-update checks.
15. Start Exim, Dovecot, nginx, and the panel service; generate a
    self-signed cert for the panel's own HTTPS.
16. Install the File Manager (unless `--no-filemanager`).
17. Create the `admin` panel user and grant it the admin role (unless an
    admin user already exists), using `--admin-email`/`--admin-password`
    if given, otherwise a generated email/password.
18. Print the panel URL, database web UI URLs, and the admin credentials.

At the end, **reboot the system** once before using the panel — several
steps (group membership changes, sudoers, cron) benefit from a clean
process environment.

---

## 4. Installer options

The installer now automates admin user creation, phpMyAdmin, phpPgAdmin,
the file manager, and PostgreSQL enablement. Available flags:

```
--yes, -y             Non-interactive: assume yes to all prompts
--purge-mta           Automatically purge a conflicting stub MTA on port 25
--no-purge-mta        Never purge, just warn
--no-pgsql            Skip enabling PostgreSQL
--no-pma              Skip installing phpMyAdmin
--no-pga              Skip installing phpPgAdmin
--no-filemanager      Skip installing the File Manager
--admin-email EMAIL   Admin contact email (default: admin@<hostname>)
--admin-password PASS Admin password (default: randomly generated)
--proxy-port PORT     Reverse-proxy port for phpMyAdmin/phpPgAdmin (default: 8080)
```

Example fully non-interactive install:

```bash
sudo bash install/minipanel-install.sh --yes --purge-mta \
  --admin-email you@yourdomain.com --proxy-port 8090
```

### 4.1 Remaining manual/known limitations

- **Reverse-proxy port collisions**: the installer checks the reverse-proxy
  port (`--proxy-port`, default 8080) and the phpMyAdmin/phpPgAdmin
  internal backend ports (8081/8082, localhost-only) for conflicts before
  writing config, and will pick an alternate port or abort with a clear
  message rather than overwrite a running service. It does **not** know
  about ports another panel (e.g. 1Panel) reserves logically but isn't
  currently listening on — always cross-check against the Section 1.1
  audit output yourself, especially if the other panel is not running at
  install time.
- **Panel HTTPS cert replacement**: the installer generates a self-signed
  certificate automatically. To replace it with a real certificate
  (purchased, or issued externally via `certbot --manual` since there's no
  web server on port 80 for an HTTP-01 challenge), do it manually:

  ```bash
  sudo cp your-cert.crt /usr/local/hestia/ssl/certificate.crt
  sudo cp your-key.key  /usr/local/hestia/ssl/certificate.key
  sudo chown root:mail /usr/local/hestia/ssl/certificate.*
  sudo chmod 660 /usr/local/hestia/ssl/certificate.*
  sudo systemctl restart hestia dovecot exim4 nginx
  ```

  Verify the key matches the cert before restarting services:
  ```bash
  openssl x509 -noout -modulus -in your-cert.crt | openssl md5
  openssl rsa  -noout -modulus -in your-key.key  | openssl md5
  # the two md5 values must match
  ```
- **phpPgAdmin source**: the installer pulls a Hestia-maintained fork of
  phpPgAdmin (`github.com/hestiacp/phppgadmin`) since upstream phpPgAdmin
  releases predate PHP 8 support. If you'd rather run the modern
  community fork described in `docs/phppgadmin.md` (PHP 7.4+/8.3+,
  Composer-based, themes, plugin system), install it separately following
  that document instead of relying on `--no-pga` plus a manual setup — the
  two are not wire-compatible drop-ins for each other's config format.
- **Existing MySQL/MariaDB or PostgreSQL on the host**: the installer
  detects a running instance and will prompt (or, with `--yes`,
  automatically choose) to reuse it rather than installing a second one.
  If reusing an existing instance, phpMyAdmin/phpPgAdmin will be
  configured against `localhost` on the standard ports — confirm this
  matches the existing instance's actual bind address before relying on it.

---

## 5. Post-install checklist

Run through this in order after the installer finishes and before handing
the panel to real users.

1. **Reboot** the host once.
2. **Log into the panel** at `https://<server-ip-or-hostname>:<port>`
   using the admin credentials printed at the end of the install (port
   shown there too, default 8083 unless it was already taken).
3. **Accept/replace the self-signed cert** in your browser, or install a
   real cert per Section 4.1.
4. **Change the admin password** from the panel (Users → Edit → Change
   password), and confirm the contact email is correct if you didn't pass
   `--admin-email` during install.
5. **Create a mail domain** to verify the mail stack end-to-end:
   - Panel → Mail → Add Mail Domain.
   - Add a mail account under that domain.
   - Test SMTP submission (port 587) and IMAP login (port 993) with a mail
     client or `openssl s_client -connect <host>:993 -crlf`.
6. **Create a test database** to verify the DB stack:
   - Panel → Database → Add Database.
   - Confirm you can connect with the generated credentials via
     `mysql -h 127.0.0.1 -u <dbuser> -p`.
   - If PostgreSQL is enabled, confirm phpPgAdmin login at
     `http://<host>:<proxy-port>/phppgadmin/`.
7. **Confirm the other panel (e.g. 1Panel) is unaffected**: re-run
   `ss -tlnp` and confirm its dashboard/proxy still respond as before.

---

## 6. Mail deliverability notes (DNS records you must add yourself)

MiniPanel does not manage DNS (DNS management was intentionally removed).
For outbound mail from this server to be accepted by other mail providers,
add these records at whatever DNS provider hosts your domain:

- **A/AAAA record**: `mail.yourdomain.com` → this server's IP.
- **PTR (reverse DNS)**: ask your VPS/hosting provider to set the reverse
  DNS of this server's IP to `mail.yourdomain.com`. This is usually done in
  your hosting provider's control panel, not your DNS zone.
- **SPF**: a TXT record on `yourdomain.com`:
  `v=spf1 mx a:mail.yourdomain.com ip4:<this-server-ip> ~all`
- **DKIM**: after creating a mail domain in the panel, retrieve the DKIM
  public key with:
  ```bash
  sudo /usr/local/hestia/bin/v-list-mail-domain-dkim-dns admin yourdomain.com
  ```
  and add the printed TXT record to your DNS zone.
- **DMARC** (recommended): a TXT record on `_dmarc.yourdomain.com`:
  `v=DMARC1; p=quarantine; rua=mailto:postmaster@yourdomain.com`

Without SPF/DKIM/PTR configured correctly, outbound mail from this server
is very likely to be marked as spam or rejected outright by major
providers (Gmail, Outlook, etc.) regardless of how correctly Exim/Dovecot
are configured locally.

---

## 7. Firewall / ports reference

MiniPanel's installer does not write firewall rules. If this host has a
firewall active (recommended), ensure these ports are reachable as needed:

| Port | Service | Expose externally? |
|---|---|---|
| Panel port (default 8083, or next free) | Panel UI (hestia-nginx) | Yes |
| Reverse proxy port (default 8080, `--proxy-port` to change) | phpMyAdmin/phpPgAdmin | Only if you need remote DB UI access; consider restricting by IP instead |
| 25 | SMTP (Exim, inbound mail) | Yes, if this server should receive mail |
| 465 / 587 | SMTP submission (Exim) | Yes, for mail clients to send |
| 993 | IMAPS (Dovecot) | Yes, for mail clients to read mail |
| 995 | POP3S (Dovecot) | Only if you use POP3 |
| 3306 | MySQL/MariaDB | No — keep bound to localhost unless you have a specific need for remote DB access |
| 5432 | PostgreSQL | No — same as above |

---

## 8. Uninstall / rollback

Use `install/minipanel-uninstall.sh`. **This is destructive by default** —
it removes every mail domain/account and every database created through
MiniPanel, in addition to the panel software itself, unless you pass
`--keep-data`.

```bash
sudo bash install/minipanel-uninstall.sh --dry-run     # preview only, changes nothing
sudo bash install/minipanel-uninstall.sh               # interactive, asks for confirmation
sudo bash install/minipanel-uninstall.sh --yes         # non-interactive, full removal
sudo bash install/minipanel-uninstall.sh --yes --keep-data     # keep mail/db data + home dirs
sudo bash install/minipanel-uninstall.sh --yes --keep-packages # only remove MiniPanel config, leave apt packages installed
```

What it removes (full run, no flags):
- Stops and disables `hestia`, `nginx`, `exim4`, `dovecot`, `clamav-daemon`,
  `spamd`, and the database engines.
- Deletes every mail domain/account via `v-delete-mail-domain` (removes
  Exim/Dovecot config **and mail spool data**) and every database via
  `v-delete-database` (drops the actual MySQL/MariaDB/PostgreSQL
  databases), for every MiniPanel user.
- Removes the phpMyAdmin control database/user, and deletes phpMyAdmin,
  phpPgAdmin, and the File Manager files.
- Removes the reverse-proxy nginx config, the PHP-FPM pool config, the
  scoped sudoers rule, and the MiniPanel cron jobs.
- Deletes each MiniPanel user account (`userdel -r`, removing home
  directories unless `--keep-data` is set).
- Deletes `/usr/local/hestia` entirely, the Hestia apt repository, and its
  signing key.
- Purges the underlying service packages (`exim4`, `dovecot-*`,
  `clamav-daemon`, `spamd`, `mariadb-server`, `postgresql`, etc.) unless
  `--keep-packages` is set.
- Removes the `hestiaweb` and `hestiamail` system users and the
  `hestia-users` group.

**Always run `--dry-run` first** to review exactly what will happen on
your system before running for real. If you need to preserve mail/database
contents (e.g. migrating to a different tool, or just being cautious), use
`--keep-data`, which skips all data deletion but still removes the panel
software and configuration.

This script only removes what MiniPanel itself installed. It does not
touch 1Panel or any other software running alongside it — verify with
`ss -tlnp` afterward that nothing unexpected changed.

---

## 9. Verifying the install

Static/config-level checks worth running after any manual step above:

```bash
# Confirm panel service is up
sudo systemctl status hestia

# Confirm mail services are up and listening
sudo ss -tlnp | grep -E ':25|:465|:587|:993|:995'

# Confirm database is reachable
sudo mysql -e "SELECT 1"

# Confirm sudoers file is scoped correctly (should show only the bin/ wildcard, no broader grants)
sudo cat /etc/sudoers.d/hestiaweb
```

For a full functional smoke test, follow the Post-install checklist in
Section 5 end to end (create a mail domain/account, create a database,
confirm phpMyAdmin/file manager access) rather than relying on service
status alone.
