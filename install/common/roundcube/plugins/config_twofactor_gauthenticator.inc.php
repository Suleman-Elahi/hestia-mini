<?php
// Hestia-Mini default configuration for the twofactor_gauthenticator plugin.
// Users opt in per-account via Settings > 2-Factor Authentication.
// See plugin README for all options.

// If true, all users must log in with 2-step verification (cannot skip).
$rcmail_config['force_enrollment_users'] = false;

// IPs allowed to bypass 2FA (CIDR supported). Empty = no bypass.
$rcmail_config['whitelist'] = array();

// If true, users can tick "remember this device" to skip 2FA for 30 days.
$rcmail_config['allow_save_device_30days'] = true;

// If true, the TOTP code field is masked as a password field.
$rcmail_config['twofactor_formfield_as_password'] = false;

// Restrict which login names may use 2FA (regex supported).
// When unset, all users may opt in. Example:
// $rcmail_config['users_allowed_2FA'] = array('.*@example.com');

// If true, 2FA failures are logged under Roundcube's log_dir.
$rcmail_config['enable_fail_logs'] = true;

// If true, 2FA secrets in user prefs are encrypted with Roundcube's DES key.
// WARNING: not reversible - flipping this back to false locks users out of 2FA.
$rcmail_config['twofactor_pref_encrypt'] = false;

// Incremental lockout delays (seconds) after consecutive failed 2FA codes.
$rcmail_config['twofactor_lockout_delays'] = array(1, 2, 5, 20, 60, 300, 600);

// Failure-counter expiry window (seconds).
$rcmail_config['twofactor_lockout'] = 900;

// Trusted reverse proxies whose X-Forwarded-For is honored (empty = REMOTE_ADDR only).
$rcmail_config['twofactor_trusted_proxies'] = array();
