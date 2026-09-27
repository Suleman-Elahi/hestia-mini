# Hestia-Mini Install & Deploy Guide

Hestia-Mini is a stripped-down HestiaCP derivative with a single `admin`
user and three modules: **Mail**, **Domain Management** (Nginx reverse
proxy + load balancing), and **Terminal** (web terminal).

Derived from HestiaCP (GPLv3) — see `LICENSE` and `NOTICE.md`.

---

## 1. Requirements

- A dedicated Debian 11/12/13 or Ubuntu 22.04/24.04/26.04 VPS/server, **or** a
  server that already runs another control panel (e.g. 1Panel) that you do
  not want to conflict with.
- Root SSH access.
- A registered domain/hostname if you want mail to work properly (SPF/DKIM/
  reverse DNS all depend on DNS being correctly pointed at this host — see
  Section 5).
- Outbound internet access (the installer pulls packages from the
  distro's package manager and the Hestia package repository).

### 1.1 If this host already runs another panel (e.g. 1Panel)

Isolation from another panel is achieved through **distinct ports and
avoiding services the other panel already owns** — not containerization.
Before installing, run this audit and record the results:

```bash
ss -tlnp
dpkg -l | grep -E 'nginx|exim|postfix|dovecot'
systemctl list-units --type=service --state=running \
  | grep -E 'nginx|mail|exim|postfix|dovecot'
```

Confirm before proceeding:

- Which ports the other panel's reverse proxy/dashboard already occupy
  (commonly 80, 443, and its own dashboard port). The Mini panel port
  defaults to 8083 and falls back to 8084-8090; the web terminal uses 8085.
- Whether a stub MTA (Postfix/Exim as a local-only relay) is already bound
  to port 25 — common on default Debian/Ubuntu installs. It must be
  removed before Exim can bind port 25. The installer detects this and
  offers to purge it interactively, or pass `--purge-mta`/`--no-purge-mta`
  to control the behavior non-interactively.
- Whether the other panel already manages the firewall (iptables/nftables).
  This installer does not touch firewall rules; if you need ports
  opened, do so through your existing firewall management (or manually via
  `ufw`/`iptables`/`nft`), not through this installer.

---

## 2. What gets installed

| Component | Purpose | Managed by |
|---|---|---|
| `hestia` + `hestia-nginx` + `hestia-php` | Panel base and web UI, dedicated port (default 8083) | Installer |
| `hestia-web-terminal` | Browser terminal backend (port 8085) | Installer |
| System `nginx` | Reverse proxy for managed domains (ports 80/443) | Installer + `v-add-domain` |
| Exim | SMTP (mail transfer) | Installer |
| Dovecot | IMAP/POP3 | Installer |
| ClamAV | Antivirus scanning for mail | Installer (skip with `--no-antivirus`) |
| SpamAssassin / spamd | Antispam scoring for mail | Installer (skip with `--no-antispam`) |
| Roundcube (SQLite) | Webmail (`webmail` alias) | Installer |
| PHP 8.2 + PHP-FPM pool | Panel/webmail runtime | Installer |
| Admin user account | Single panel login | Installer (auto-created; use `--admin-email`/`--admin-password` to customize) |

Explicitly **not** installed: Apache, PHP-FPM web-hosting pools,
MariaDB/MySQL, PostgreSQL, phpMyAdmin/phpPgAdmin, BIND/named (DNS server),
iptables/fail2ban rule sets, FTP servers, file manager, vhost templates,
cron UI, backup UI, app marketplace. There is no multi-user management:
no user list, packages, roles, SSH/SFTP keys, notifications, or API keys.

---

## 3. Quick install

```bash
git clone <your-hestia-mini-repo-url> /usr/local/src/hestia-mini
cd /usr/local/src/hestia-mini
sudo bash install/hestia-mini-install.sh
```

The installer will:

1. Verify it's running as root, on a supported OS (warns and asks for
   confirmation on untested Debian/Ubuntu point releases).
2. Check for port conflicts on the panel port (8083, falling back to
   8084-8090); picks an alternate port rather than colliding.
3. Detect a conflicting stub MTA on port 25 and offer to purge it
   (`--purge-mta` / `--no-purge-mta` to control this non-interactively).
4. Install packages: `hestia`, `hestia-nginx`, `hestia-php`,
   `hestia-web-terminal`, Exim, Dovecot, ClamAV, SpamAssassin, PHP 8.2,
   Nginx, Node.js, and supporting tools.
5. Create the `hestiaweb` (panel) and `hestiamail` (mail service)
   system users and the `hestia-users` group.
6. Copy `bin/`, `func/`, `web/`, and `install/deb`+`install/common`
   resources into `/usr/local/hestia/`, and build the panel front-end
   assets (`npm install && npm run build`).
7. Write `/usr/local/hestia/conf/hestia.conf` (with `minipanel.conf` kept
   as a compatibility symlink) and `/etc/hestiacp/hestia.conf` as the
   upstream-compatible bootstrap config.
8. Configure Exim, Dovecot (2.3 or 2.4 template, auto-detected), ClamAV,
   and SpamAssassin from the install tree's templates.
9. Configure a PHP-FPM pool and install Roundcube webmail (SQLite).
10. Write the Nginx reverse-proxy skeleton (`/etc/nginx/conf.d/domains/`;
    domains are added later via `v-add-domain` or the panel).
11. Write a scoped sudoers file limiting `hestiaweb` to running only
    `/usr/local/hestia/bin/*` scripts.
12. Set up a small crontab for queue processing.
13. Generate a self-signed cert for the panel's own HTTPS.
14. Create the single `admin` panel user (unless one already exists),
    using `--admin-email`/`--admin-password` if given, otherwise a
    generated email/password.
15. Start Exim, Dovecot, Nginx, the web terminal, and the panel service;
    print the panel URL and the admin credentials.

At the end, **reboot the system** once before using the panel.

---

## 4. Installer options

```
--yes, -y             Non-interactive: assume yes to all prompts
--purge-mta           Automatically purge a conflicting stub MTA on port 25
--no-purge-mta        Never purge, just warn
--no-antivirus        Skip installing ClamAV antivirus for mail
--no-antispam         Skip installing SpamAssassin antispam for mail
--admin-email EMAIL   Admin contact email (default: admin@<hostname>)
--admin-password PASS Admin password (default: randomly generated)
--panel-domain DOMAIN Panel domain for Let's Encrypt SSL (e.g. panel.example.com)
```

When run interactively (without `--yes`), the installer asks whether to
install ClamAV and SpamAssassin, defaulting to yes. With `--yes`, both are
installed unless skipped via `--no-antivirus` / `--no-antispam`.

Example fully non-interactive install:

```bash
sudo bash install/hestia-mini-install.sh --yes --purge-mta \
  --admin-email you@yourdomain.com
```

### 4.1 Panel domain & HTTPS

The installer generates a self-signed certificate for the panel's own
port. Pass `--panel-domain panel.example.com` to register the panel domain
as a managed reverse-proxy domain: it appears under **Domains → Reverse
Proxy**, gets a free Let's Encrypt certificate, and the panel becomes
reachable on the standard HTTPS port (`https://panel.example.com`). The
same certificate is copied to `/usr/local/hestia/ssl/` for direct
`https://panel.example.com:8083` access, and `v-update-letsencrypt-ssl`
keeps it refreshed on renewal. Requirements: the domain's A record must
point at this server, and port 80 must be reachable for the HTTP-01
challenge.

To install a certificate issued elsewhere instead, replace the files manually:

```bash
sudo cp your-cert.crt /usr/local/hestia/ssl/certificate.crt
sudo cp your-key.key  /usr/local/hestia/ssl/certificate.key
sudo chown root:mail /usr/local/hestia/ssl/certificate.*
sudo chmod 660 /usr/local/hestia/ssl/certificate.*
sudo systemctl restart hestia dovecot exim4 nginx
```

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
4. **Change the admin password** (admin menu → Edit user → change
   password), and confirm the contact email is correct if you didn't pass
   `--admin-email` during install.
5. **Create a mail domain** to verify the mail stack end-to-end:
   - Panel → Mail → Add Mail Domain.
   - Add a mail account under that domain.
   - Test SMTP submission (port 587) and IMAP login (port 993) with a mail
     client or `openssl s_client -connect <host>:993 -crlf`.
6. **Add a reverse-proxy domain** (Panel → Domains) pointing at a backend,
   and confirm traffic flows through Nginx.
7. **Open the Terminal** (Panel → Terminal) and confirm the admin shell works.
8. **Confirm the other panel (e.g. 1Panel) is unaffected**: re-run
   `ss -tlnp` and confirm its dashboard/proxy still respond as before.

---

## 6. Mail deliverability notes (DNS records you must add yourself)

Hestia-Mini does not manage DNS. For outbound mail from this server to be
accepted by other mail providers, add these records at whatever DNS
provider hosts your domain:

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

The installer does not write firewall rules. If this host has a
firewall active (recommended), ensure these ports are reachable as needed:

| Port | Service | Expose externally? |
|---|---|---|
| Panel port (default 8083, or next free) | Panel UI (hestia-nginx) | Yes |
| 8085 (localhost) | Web terminal backend | No — proxied through the panel |
| 80 / 443 | Nginx reverse proxy (managed domains, webmail) | Yes, if serving domains/webmail |
| 25 | SMTP (Exim, inbound mail) | Yes, if this server should receive mail |
| 465 / 587 | SMTP submission (Exim) | Yes, for mail clients to send |
| 993 | IMAPS (Dovecot) | Yes, for mail clients to read mail |
| 995 | POP3S (Dovecot) | Only if you use POP3 |

---

## 8. Uninstall / rollback

Use `install/hestia-mini-uninstall.sh`. **This is destructive by default** —
it removes every mail domain/account created through Hestia-Mini, in
addition to the panel software itself, unless you pass `--keep-data`.

```bash
sudo bash install/hestia-mini-uninstall.sh --dry-run     # preview only, changes nothing
sudo bash install/hestia-mini-uninstall.sh               # interactive, asks for confirmation
sudo bash install/hestia-mini-uninstall.sh --yes         # non-interactive, full removal
sudo bash install/hestia-mini-uninstall.sh --yes --keep-data     # keep mail data + admin home dir
sudo bash install/hestia-mini-uninstall.sh --yes --keep-packages # only remove config, leave apt packages installed
```

**Always run `--dry-run` first** to review exactly what will happen on
your system before running for real.

This script only removes what Hestia-Mini itself installed. It does not
touch 1Panel or any other software running alongside it — verify with
`ss -tlnp` afterward that nothing unexpected changed.

---

## 9. Verifying the install

```bash
# Confirm panel service is up
sudo systemctl status hestia

# Confirm mail services are up and listening
sudo ss -tlnp | grep -E ':25|:465|:587|:993|:995'

# Confirm web terminal is up
sudo systemctl status hestia-web-terminal

# Confirm sudoers file is scoped correctly (should show only the bin/ wildcard)
sudo cat /etc/sudoers.d/hestiaweb
```

For a full functional smoke test, follow the Post-install checklist in
Section 5 end to end rather than relying on service status alone.
