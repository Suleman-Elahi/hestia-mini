#!/bin/bash

# ======================================================== #
#
# Hestia-Mini Uninstaller
#
# Removes everything installed by hestia-mini-install.sh:
# panel, mail stack, database engines, phpMyAdmin/phpPgAdmin,
# file manager, sudoers, cron, system users, and - unless
# --keep-data is given - all mail/database DATA as well.
#
# THIS IS DESTRUCTIVE. By default it deletes mail spools and
# database contents. Use --keep-data to preserve them, or
# --dry-run to see what would happen without changing anything.
#
# ======================================================== #

export PATH=$PATH:/sbin
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none
HESTIA='/usr/local/hestia'
LOG="/root/hestia_mini_uninstall-$(date +%d%m%Y%H%M).log"
spinner="/\-|"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ASSUME_YES='no'
KEEP_DATA='no'
DRY_RUN='no'
KEEP_PACKAGES='no'

while [ $# -gt 0 ]; do
	case "$1" in
		--yes | -y)
			ASSUME_YES='yes'
			shift
			;;
		--keep-data)
			KEEP_DATA='yes'
			shift
			;;
		--keep-packages)
			KEEP_PACKAGES='yes'
			shift
			;;
		--dry-run)
			DRY_RUN='yes'
			shift
			;;
		--help | -h)
			echo "Usage: $0 [options]"
			echo "  --yes, -y          Non-interactive: skip the confirmation prompt"
			echo "  --keep-data        Keep mail spools (/home/*/mail), MySQL/MariaDB and"
			echo "                     PostgreSQL data directories, and user home directories."
			echo "                     Panel config, packages, and code are still removed."
			echo "  --keep-packages    Do not apt purge the underlying service packages"
			echo "                     (exim4, dovecot, mariadb-server, postgresql, etc)."
			echo "                     Only removes MiniPanel-specific config/data."
			echo "  --dry-run          Print what would be removed without removing anything."
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

run() {
	if [ "$DRY_RUN" = 'yes' ]; then
		echo "  [dry-run] $*"
	else
		"$@" >> "$LOG" 2>&1
	fi
}

check_result() {
	local status=$1
	local message=$2

	if [ "$status" -ne 0 ]; then
		echo -e "[${RED} FAILED ${NC}]"
		echo "  Error: $message"
		echo "  Details: $LOG"
		exit "$status"
	fi
}

run_apt() {
	local action_desc="$1"
	shift
	if [ "$DRY_RUN" = 'yes' ]; then
		echo "  [dry-run] $*"
		return 0
	fi

	printf "  %-55s" "$action_desc..."
	"$@" >> "$LOG" 2>&1 &
	local back_pid=$!
	local spin_i=1
	while kill -0 $back_pid > /dev/null 2>&1; do
		printf " [%c]  " "${spinner:spin_i++%${#spinner}:1}"
		sleep 0.5
		printf "\b\b\b\b\b\b"
	done
	echo -ne '\b\b\b\b\b\b'
	wait $back_pid
	local status=$?
	if [ "$status" -eq 0 ]; then
		echo -e "[${GREEN} OK ${NC}]"
	else
		echo -e "[${RED} FAILED ${NC}]"
		echo "  Error: $action_desc failed. Check details in: $LOG"
		exit "$status"
	fi
}

cleanup_policy_rc_d() {
	rm -f /usr/sbin/policy-rc.d
}
trap cleanup_policy_rc_d EXIT INT TERM

say() {
	echo -e "$1"
}

if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}Error: This uninstaller must be run as root.${NC}"
	exit 1
fi

echo "====================================================="
echo "       Hestia-Mini Uninstaller"
echo "====================================================="
echo
echo -e "${YELLOW}This will remove:${NC}"
echo "  - The panel (hestia, hestia-nginx, hestia-php, hestia-web-terminal, /usr/local/hestia)"
echo "  - Exim, Dovecot, ClamAV, SpamAssassin configuration"
echo "  - The File Manager"
echo "  - The reverse-proxy nginx config, sudoers rule, and cron jobs"
echo "  - The 'hestiaweb' and 'hestiamail' system users"
if [ "$KEEP_DATA" = 'yes' ]; then
	echo -e "  - ${GREEN}Data will be KEPT${NC}: mail spools, user home dirs"
else
	echo -e "  - ${RED}Mail spools and user home directories created for MiniPanel users${NC}"
	echo -e "    ${RED}WILL BE DELETED.${NC}"
fi
if [ "$KEEP_PACKAGES" = 'yes' ]; then
	echo "  - Service packages (exim4, dovecot, mariadb-server, etc) will be LEFT INSTALLED."
else
	echo "  - Service packages (exim4, dovecot, clamav, mariadb-server, postgresql, etc) will be purged."
fi
echo
echo "A log of this run will be written to: $LOG"
echo

if [ "$DRY_RUN" = 'yes' ]; then
	echo -e "${YELLOW}DRY RUN: no changes will be made.${NC}"
	echo
fi

if [ "$ASSUME_YES" != 'yes' ] && [ "$DRY_RUN" != 'yes' ]; then
	read -r -p "Type 'yes' to proceed: " confirm
	if [ "$confirm" != "yes" ]; then
		echo "Aborted."
		exit 0
	fi
fi

#----------------------------------------------------------#
#                 Stop and disable services                 #
#----------------------------------------------------------#

echo -e "\n[ * ] Stopping services..."
for svc in hestia hestia-web-terminal nginx exim4 dovecot clamav-daemon clamav-freshclam spamd spamassassin; do
	run systemctl stop "$svc" 2>/dev/null || true
	run systemctl disable "$svc" 2>/dev/null || true
done

killall -9 freshclam clamd 2>/dev/null || true

#----------------------------------------------------------#
#                 Remove mail data (Exim/Dovecot)            #
#----------------------------------------------------------#

if [ "$KEEP_DATA" != 'yes' ]; then
	echo -e "\n[ * ] Removing mail domains and spools for all MiniPanel users..."
	echo -e "${YELLOW}      (this deletes ALL mail accounts/messages created through MiniPanel)${NC}"
	if [ -d "$HESTIA/bin" ] && [ -d "$HESTIA/data/users" ]; then
		for user_dir in "$HESTIA"/data/users/*/; do
			[ -d "$user_dir" ] || continue
			mp_user="$(basename "$user_dir")"
			if [ -f "$user_dir/mail.conf" ]; then
				while IFS= read -r line; do
					domain=$(echo "$line" | grep -oP "DOMAIN='[^']*'" | cut -d"'" -f2)
					[ -z "$domain" ] && continue
					if [ "$DRY_RUN" = 'yes' ]; then
						echo "  [dry-run] $HESTIA/bin/v-delete-mail-domain $mp_user $domain"
					else
						"$HESTIA/bin/v-delete-mail-domain" "$mp_user" "$domain" >> "$LOG" 2>&1
					fi
				done < "$user_dir/mail.conf"
			fi
		done
	fi
	run rm -rf /etc/exim4/domains /etc/exim4/domains_debug
	run rm -rf /var/spool/exim4
	run rm -rf /var/mail
fi

#----------------------------------------------------------#
#                  Remove panel user accounts                #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing MiniPanel user accounts..."
if [ -d "$HESTIA/data/users" ]; then
	for user_dir in "$HESTIA"/data/users/*/; do
		[ -d "$user_dir" ] || continue
		mp_user="$(basename "$user_dir")"
		if id "$mp_user" > /dev/null 2>&1; then
			if [ "$KEEP_DATA" = 'yes' ]; then
				run userdel "$mp_user"
			else
				run userdel -r "$mp_user"
			fi
		fi
	done
fi

#----------------------------------------------------------#
#                    Remove File Manager                     #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing File Manager..."
run rm -rf "$HESTIA/web/fm"

#----------------------------------------------------------#
#             Remove nginx / PHP-FPM / sudoers / cron         #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing Hestia-Mini nginx/PHP-FPM/sudoers/cron configuration..."
run rm -f /etc/nginx/conf.d/minipanel.conf /etc/nginx/conf.d/hestia-mini.conf
run rm -f /etc/php/*/fpm/pool.d/www.conf
run rm -f /etc/sudoers.d/hestiaweb
run rm -f /var/spool/cron/crontabs/hestiaweb
run rm -f /var/spool/cron/crontabs/hestiamail
run systemctl reload nginx 2> /dev/null

#----------------------------------------------------------#
#                Remove Dovecot/Exim configuration            #
#----------------------------------------------------------#

# Exim and Dovecot configuration is handled after package cleanup. Removing
# /etc/exim4/exim4.conf.template before exim4-config is purged can leave a
# retained or partially configured Exim package unusable.

#----------------------------------------------------------#
#                  Purge underlying packages               #
#----------------------------------------------------------#

if [ "$KEEP_PACKAGES" != 'yes' ]; then
	echo -e "\n[ * ] Purging underlying service packages..."

	pkgs_always="hestia hestia-nginx hestia-php hestia-web-terminal nodejs clamav-daemon clamav-freshclam spamd spamassassin exim4 exim4-base exim4-config exim4-daemon-heavy bsd-mailx dovecot-imapd dovecot-managesieved dovecot-pop3d dovecot-sieve"

	# Preseed debconf selections for unattended package purge
	if command -v debconf-set-selections > /dev/null 2>&1; then
		echo "exim4-base exim4/purge_spool boolean true" | debconf-set-selections 2>/dev/null || true
		echo "clamav-base clamav-base/purge boolean true" | debconf-set-selections 2>/dev/null || true
	fi

	# Prevent maintainer scripts from hanging on service management during purge
	echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
	chmod a+x /usr/sbin/policy-rc.d

	apt_opts=(
		-y
		--allow-change-held-packages
		-o Dpkg::Options::="--force-confdef"
		-o Dpkg::Options::="--force-confold"
	)

	run_apt "Purging panel, web, and mail packages" apt-get "${apt_opts[@]}" purge $pkgs_always

	run_apt "Removing unused dependencies (autoremove)" apt-get "${apt_opts[@]}" autoremove

	rm -f /usr/sbin/policy-rc.d

	echo -e "\n[ * ] Removing Exim/Dovecot configuration written by MiniPanel..."
	run rm -f /etc/exim4/exim4.conf.template /etc/exim4/dnsbl.conf \
		/etc/exim4/spam-blocks.conf /etc/exim4/limit.conf /etc/exim4/system.filter /etc/exim4/white-blocks.conf
	run rm -rf /etc/dovecot/conf.d/domains
	run rm -f /etc/dovecot/dovecot.conf
else
	echo -e "\n[ * ] --keep-packages set: restoring a valid Debian Exim template."
	if [ "$DRY_RUN" = 'yes' ]; then
		echo "  [dry-run] restore /etc/exim4/exim4.conf.template from Debian example"
	else
		debian_exim_template='/usr/share/doc/exim4-base/examples/example.conf.gz'
		[ -f "$debian_exim_template" ] || check_result 1 "Missing Debian Exim template: $debian_exim_template"
		zcat "$debian_exim_template" > /etc/exim4/exim4.conf.template
		check_result $? "Failed to restore the Debian Exim template"
		rm -f /etc/exim4/dnsbl.conf /etc/exim4/spam-blocks.conf /etc/exim4/limit.conf /etc/exim4/system.filter /etc/exim4/white-blocks.conf
		update-exim4.conf >> "$LOG" 2>&1
		check_result $? "Failed to regenerate the retained Exim configuration. Check details in: $LOG"
	fi
	echo "  Dovecot configuration is retained because its packages remain installed."
fi

#----------------------------------------------------------#
#                    Remove panel software                 #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing remaining MiniPanel core files..."
run rm -f /lib/systemd/system/hestia-web-terminal.service
run systemctl daemon-reload 2>/dev/null || true
run rm -rf "$HESTIA"
run rm -rf /var/log/hestia
run rm -f /etc/logrotate.d/hestia
run rm -f /etc/profile.d/hestia.sh
run rm -f /run/hestia-nginx.pid /run/hestia-php.pid /run/hestia-php.sock
run rm -f /etc/hestiacp/hestia.conf
run rmdir /etc/hestiacp 2> /dev/null
run rm -f /usr/share/keyrings/hestia-keyring.gpg
run rm -f /etc/apt/sources.list.d/hestia.list
run rm -f /usr/share/keyrings/sury-keyring.gpg /etc/apt/sources.list.d/php.list
run rm -f /usr/share/keyrings/nodejs.gpg /etc/apt/sources.list.d/nodejs.list

#----------------------------------------------------------#
#                  Remove system service users                #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing MiniPanel system service accounts..."
run userdel hestiaweb
run groupdel hestiaweb 2> /dev/null || true
if [ "$KEEP_DATA" = 'yes' ]; then
	run userdel hestiamail
else
	run userdel -r hestiamail
fi
run groupdel hestia-users 2> /dev/null || true

echo
echo "====================================================="
if [ "$DRY_RUN" = 'yes' ]; then
	echo "  Dry run complete. No changes were made."
else
	echo "  MiniPanel has been uninstalled."
	echo "  Log written to: $LOG"
	if [ "$KEEP_DATA" = 'yes' ]; then
		echo "  Data was preserved: mail spools, database contents, and user home"
		echo "  directories were NOT removed."
	fi
fi
echo "====================================================="
