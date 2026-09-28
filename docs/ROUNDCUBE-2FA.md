# Roundcube Two-Factor Authentication (2FA)

Webmail (`webmail.<domain>`) ships with TOTP two-factor login via the
`twofactor_gauthenticator` plugin
([upstream](https://github.com/alexandregz/twofactor_gauthenticator)),
compatible with any RFC 6238 authenticator app
(Google Authenticator, Authy, etc.).

The plugin is installed by `bin/v-add-sys-roundcube` on fresh installs
and re-ensured on upgrades. Default config lives at
`install/common/roundcube/plugins/config_twofactor_gauthenticator.inc.php`
and is deployed to `/etc/roundcube/plugins/twofactor_gauthenticator/config.inc.php`.
Key defaults: opt-in per user (`force_enrollment_users=false`), empty IP
whitelist, 30-day "remember device" allowed, failure logging on.

---

## 1. User self-service setup

1. Log in to webmail.
2. Go to **Settings > 2-Factor Authentication**.
3. Click **"Fill all fields"** — this auto-generates a valid secret and
   recovery codes. **Do not type your own secret** (see §3).
4. Scan the QR code with your authenticator app (or enter the secret manually).
5. Enter the current code, click **"Check code"**, then **Save**.
6. Store the recovery codes somewhere safe (password manager).

To force 2FA for everyone, set in
`/etc/roundcube/plugins/twofactor_gauthenticator/config.inc.php`:

```php
$rcmail_config['force_enrollment_users'] = true;
```

## 2. Admin: unlock a user locked out of 2FA

Symptoms: user enabled 2FA but codes never verify (often after a missing
QR code), recovery codes don't work, and login always bounces back to the
2FA prompt.

2FA state is stored per-user in the SQLite database
(`/var/lib/roundcube/db/roundcube.db`, `users.preferences`, PHP-serialized).
The fix is to remove the `twofactor_gauthenticator` key for that user so
they can log in with password only and re-enroll. **Back up first**, and
always edit via PHP `unserialize`/`serialize` — never `sed` — because the
serialized format embeds string lengths.

```bash
LOGIN='user@example.com'
cp -a /var/lib/roundcube/db/roundcube.db \
  "/root/roundcube.db.bak-$(date +%Y%m%d%H%M%S)"

cat > /tmp/fix2fa.php << PHP
<?php
\$db = new SQLite3('/var/lib/roundcube/db/roundcube.db');
\$row = \$db->querySingle(
  "SELECT preferences FROM users WHERE username='$LOGIN'", true);
\$prefs = unserialize(\$row['preferences']);
echo 'BEFORE keys: ' . implode(',', array_keys(\$prefs)) . "\n";
unset(\$prefs['twofactor_gauthenticator']);
\$stmt = \$db->prepare('UPDATE users SET preferences = :p WHERE username = :u');
\$stmt->bindValue(':p', serialize(\$prefs), SQLITE3_TEXT);
\$stmt->bindValue(':u', '$LOGIN', SQLITE3_TEXT);
\$stmt->execute();
echo "DONE\n";
PHP
php /tmp/fix2fa.php
rm -f /tmp/fix2fa.php
```

Substitute the real login name for `$LOGIN`. The user can then log in
without a 2FA code and re-enroll per §1. No service restart is needed.

To inspect before deleting:

```bash
sqlite3 /var/lib/roundcube/db/roundcube.db \
  "SELECT username FROM users;"
```

## 3. Why lockouts happen: secret must be base32

The TOTP secret must match `[A-Z][2-7]` (base32, no lowercase, no digits
`0/1/8/9`, no symbols). A manually typed secret containing other
characters (e.g. `^ % $`) produces no QR code and codes that can never
verify — including identical copy-pasted "recovery codes". Always use
**"Fill all fields"** to generate the secret. If the QR still doesn't
render after auto-generate, do not save; check the browser console and
`/var/log/roundcube/` for plugin asset errors first.
