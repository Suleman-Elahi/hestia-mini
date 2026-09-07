#!/bin/bash
# ======================================================== #
# Hestia-Mini Install Module: phpPgAdmin Configuration
# Called from hestia-mini-install.sh
# ======================================================== #

configure_phppgadmin() {
	if [ "$PGA_INSTALL" = 'yes' ] && [ "$PGSQL_ENABLE" = 'yes' ]; then
		echo -e "\n[ * ] Installing phpPgAdmin v$pga_v..."
		if [ ! -d /usr/share/phppgadmin ]; then
			mkdir -p /etc/phppgadmin /usr/share/phppgadmin
			( cd /tmp &&
				wget --retry-connrefused --quiet "https://github.com/hestiacp/phppgadmin/releases/download/v$pga_v/phppgadmin-v$pga_v.tar.gz" &&
				tar xzf "phppgadmin-v$pga_v.tar.gz" -C /usr/share/phppgadmin/ &&
				rm -f "phppgadmin-v$pga_v.tar.gz" ) >> $LOG 2>&1
			check_result $? "Failed to download/install phpPgAdmin"

			cp -f "$HESTIA_INSTALL_DIR/pga/config.inc.php" /etc/phppgadmin/config.inc.php 2>> $LOG
			if [ ! -L /usr/share/phppgadmin/conf/config.inc.php ]; then
				ln -sf /etc/phppgadmin/config.inc.php /usr/share/phppgadmin/conf/config.inc.php
			fi

			chown -R root:hestiamail /etc/phppgadmin/
			chmod 640 /etc/phppgadmin/config.inc.php
		else
			echo "  phpPgAdmin already installed, skipping."
		fi

		# Ensure PostgreSQL accepts password auth for the pma/panel-managed
		# roles (matches upstream Hestia's pg_hba.conf handling)
		PG_HBA=$(find /etc/postgresql -maxdepth 2 -name pg_hba.conf 2> /dev/null | sort -V | tail -n1)
		if [ -n "$PG_HBA" ] && ! grep -q "^host.*all.*all.*127.0.0.1/32.*md5" "$PG_HBA"; then
			echo "host    all             all             127.0.0.1/32            md5" >> "$PG_HBA"
			echo "host    all             all             ::1/128                 md5" >> "$PG_HBA"
			systemctl reload postgresql 2> /dev/null
		fi
	elif [ "$PGA_INSTALL" = 'yes' ] && [ "$PGSQL_ENABLE" != 'yes' ]; then
		echo -e "\n[ * ] Skipping phpPgAdmin (PostgreSQL disabled via --no-pgsql)."
	else
		echo -e "\n[ * ] Skipping phpPgAdmin install (disabled via --no-pga)."
	fi
}
