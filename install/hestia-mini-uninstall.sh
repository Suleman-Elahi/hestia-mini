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
HESTIA='/usr/local/hestia'
LOG="/root/hestia_mini_uninstall-$(date +%d%m%Y%H%M).log"

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
echo "  - The panel (hestia-nginx, hestia-php, /usr/local/hestia)"
echo "  - Exim, Dovecot, ClamAV, SpamAssassin configuration"
echo "  - phpMyAdmin, phpPgAdmin, and the File Manager"
echo "  - The reverse-proxy nginx config, sudoers rule, and cron jobs"
echo "  - The 'hestiaweb' and 'hestiamail' system users"
if [ "$KEEP_DATA" = 'yes' ]; then
	echo -e "  - ${GREEN}Data will be KEPT${NC}: mail spools, database contents, user home dirs"
else
	echo -e "  - ${RED}Mail spools, database contents (MySQL/MariaDB + PostgreSQL data), and${NC}"
	echo -e "    ${RED}user home directories created for MiniPanel users WILL BE DELETED.${NC}"
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
for svc in hestia nginx exim4 dovecot clamav-daemon spamd; do
	run systemctl stop "$svc"
	run systemctl disable "$svc"
done

# Only stop DB engines if we're about to remove their packages/data;
# otherwise leave them running for whatever else might depend on them.
if [ "$KEEP_DATA" != 'yes' ] && [ "$KEEP_PACKAGES" != 'yes' ]; then
	run systemctl stop mysql
	run systemctl stop mariadb
	run systemctl stop postgresql
fi

#----------------------------------------------------------#
#              Remove MiniPanel-managed databases            #
#----------------------------------------------------------#

if [ "$KEEP_DATA" != 'yes' ]; then
	echo -e "\n[ * ] Removing phpMyAdmin/phpPgAdmin control databases..."
	mysql_cmd="mysql"
	command -v mariadb > /dev/null 2>&1 && mysql_cmd="mariadb"
	if command -v "$mysql_cmd" > /dev/null 2>&1; then
		if [ "$DRY_RUN" = 'yes' ]; then
			echo "  [dry-run] DROP DATABASE phpmyadmin; DROP USER 'pma'@'localhost';"
		else
			$mysql_cmd -uroot -e "DROP DATABASE IF EXISTS phpmyadmin;" >> "$LOG" 2>&1
			$mysql_cmd -uroot -e "DROP USER IF EXISTS 'pma'@'localhost';" >> "$LOG" 2>&1
		fi
	fi

	echo -e "\n[ * ] Removing all user-created MySQL/MariaDB and PostgreSQL databases and roles..."
	echo -e "${YELLOW}      (this deletes ALL databases created through MiniPanel for every user)${NC}"
	if [ -d "$HESTIA/bin" ] && [ -d "$HESTIA/data/users" ]; then
		for user_dir in "$HESTIA"/data/users/*/; do
			[ -d "$user_dir" ] || continue
			mp_user="$(basename "$user_dir")"
			if [ -f "$user_dir/db.conf" ]; then
				while IFS= read -r line; do
					dbname=$(echo "$line" | grep -oP "DB='[^']*'" | cut -d"'" -f2)
					dbtype=$(echo "$line" | grep -oP "TYPE='[^']*'" | cut -d"'" -f2)
					[ -z "$dbname" ] && continue
					if [ "$DRY_RUN" = 'yes' ]; then
						echo "  [dry-run] $HESTIA/bin/v-delete-database $mp_user $dbname"
					else
						"$HESTIA/bin/v-delete-database" "$mp_user" "$dbname" >> "$LOG" 2>&1
					fi
				done < "$user_dir/db.conf"
			fi
		done
	fi
fi

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
#                Remove phpMyAdmin/phpPgAdmin                #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing phpMyAdmin/phpPgAdmin files..."
run rm -rf /usr/share/phpmyadmin /etc/phpmyadmin /var/lib/phpmyadmin
run rm -rf /usr/share/phppgadmin /etc/phppgadmin

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

echo -e "\n[ * ] Removing Exim/Dovecot configuration written by MiniPanel..."
run rm -f /etc/exim4/exim4.conf.template /etc/exim4/dnsbl.conf \
	/etc/exim4/spam-blocks.conf /etc/exim4/limit.conf /etc/exim4/system.filter
run rm -rf /etc/dovecot/conf.d/domains
run rm -f /etc/dovecot/dovecot.conf

#----------------------------------------------------------#
#                    Remove panel software                   #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing MiniPanel core..."
run rm -rf "$HESTIA"
run rm -f /etc/hestiacp/hestia.conf
run rmdir /etc/hestiacp 2> /dev/null
run rm -f /usr/share/keyrings/hestia-keyring.gpg
run rm -f /etc/apt/sources.list.d/hestia.list

#----------------------------------------------------------#
#                  Purge underlying packages                 #
#----------------------------------------------------------#

if [ "$KEEP_PACKAGES" != 'yes' ]; then
	echo -e "\n[ * ] Purging underlying service packages..."
	echo -e "${YELLOW}      (mariadb-server/mysql-server/postgresql are only purged if --keep-data is not set)${NC}"

	pkgs_always="hestia hestia-nginx hestia-php clamav-daemon spamd exim4 exim4-daemon-heavy
	  dovecot-imapd dovecot-managesieved dovecot-pop3d dovecot-sieve"

	pkgs_with_data="mariadb-server mariadb-client mariadb-common mysql-server mysql-client
	  mysql-common postgresql postgresql-contrib"

	if [ "$DRY_RUN" = 'yes' ]; then
		echo "  [dry-run] apt-get -y purge $pkgs_always"
	else
		apt-get -y purge $pkgs_always >> "$LOG" 2>&1
	fi

	if [ "$KEEP_DATA" != 'yes' ]; then
		if [ "$DRY_RUN" = 'yes' ]; then
			echo "  [dry-run] apt-get -y purge $pkgs_with_data"
			echo "  [dry-run] rm -rf /var/lib/mysql /var/lib/postgresql"
		else
			apt-get -y purge $pkgs_with_data >> "$LOG" 2>&1
			rm -rf /var/lib/mysql /var/lib/postgresql
		fi
	else
		echo "  --keep-data set: leaving mariadb-server/mysql-server/postgresql packages"
		echo "  and their data directories (/var/lib/mysql, /var/lib/postgresql) installed."
	fi

	run apt-get -y autoremove
else
	echo -e "\n[ * ] --keep-packages set: leaving all service packages installed."
fi

#----------------------------------------------------------#
#                  Remove system service users                #
#----------------------------------------------------------#

echo -e "\n[ * ] Removing MiniPanel system service accounts..."
run userdel hestiaweb
if [ "$KEEP_DATA" = 'yes' ]; then
	run userdel hestiamail
else
	run userdel -r hestiamail
fi
run groupdel hestia-users

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
