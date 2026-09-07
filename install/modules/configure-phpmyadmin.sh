#!/bin/bash
# ======================================================== #
# Hestia-Mini Install Module: phpMyAdmin Configuration
# Called from hestia-mini-install.sh
# ======================================================== #

configure_phpmyadmin() {
	if [ "$PMA_INSTALL" = 'yes' ]; then
		echo -e "\n[ * ] Installing phpMyAdmin v$pma_v..."
		if [ ! -d /usr/share/phpmyadmin ] || [ "$(jq -r .version /usr/share/phpmyadmin/package.json 2> /dev/null)" != "$pma_v" ]; then
			mkdir -p /usr/share/phpmyadmin /etc/phpmyadmin/conf.d /var/lib/phpmyadmin/tmp
			( cd /tmp &&
				wget --quiet --retry-connrefused "https://files.phpmyadmin.net/phpMyAdmin/$pma_v/phpMyAdmin-$pma_v-all-languages.tar.gz" &&
				tar xzf "phpMyAdmin-$pma_v-all-languages.tar.gz" &&
				rm -rf "phpMyAdmin-$pma_v-all-languages/doc" &&
				cp -rf "phpMyAdmin-$pma_v-all-languages"/* /usr/share/phpmyadmin &&
				rm -rf "phpMyAdmin-$pma_v-all-languages" "phpMyAdmin-$pma_v-all-languages.tar.gz" ) >> $LOG 2>&1
			check_result $? "Failed to download/install phpMyAdmin"

			cp -f "$HESTIA_INSTALL_DIR/phpmyadmin/config.inc.php" /etc/phpmyadmin/config.inc.php 2>> $LOG
			sed -i "s|'configFile' => ROOT_PATH . 'config.inc.php',|'configFile' => '/etc/phpmyadmin/config.inc.php',|g" \
				/usr/share/phpmyadmin/libraries/vendor_config.php 2> /dev/null

			blowfish=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
			sed -i "s|%blowfish_secret%|$blowfish|" /etc/phpmyadmin/config.inc.php

			chown -R hestiamail:www-data /var/lib/phpmyadmin/tmp
			chmod 0770 /var/lib/phpmyadmin/tmp

			# Create pmadb + control user (phpmyadmin-fixer, adapted from
			# install/deb/phpmyadmin/pma.sh)
			pma_ctl_pass=$(gen_pass '24' 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')
			mysql_cmd="mysql"
			command -v mariadb > /dev/null 2>&1 && mysql_cmd="mariadb"
			$mysql_cmd -uroot -e "CREATE DATABASE IF NOT EXISTS phpmyadmin;" >> $LOG 2>&1
			$mysql_cmd -uroot -e "CREATE USER IF NOT EXISTS 'pma'@'localhost' IDENTIFIED BY '$pma_ctl_pass';" >> $LOG 2>&1
			$mysql_cmd -uroot -e "GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'pma'@'localhost'; FLUSH PRIVILEGES;" >> $LOG 2>&1
			if [ -f "$HESTIA_INSTALL_DIR/phpmyadmin/create_tables.sql" ]; then
				$mysql_cmd -uroot phpmyadmin < "$HESTIA_INSTALL_DIR/phpmyadmin/create_tables.sql" >> $LOG 2>&1
			fi

			cat > /etc/phpmyadmin/conf.d/01-localhost.php << PMACONF
<?php
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['port'] = '3306';
\$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';
\$cfg['Servers'][\$i]['controluser'] = 'pma';
\$cfg['Servers'][\$i]['controlpass'] = '$pma_ctl_pass';
\$cfg['Servers'][\$i]['bookmarktable'] = 'pma__bookmark';
\$cfg['Servers'][\$i]['relation'] = 'pma__relation';
\$cfg['Servers'][\$i]['userconfig'] = 'pma__userconfig';
\$cfg['Servers'][\$i]['table_info'] = 'pma__table_info';
\$cfg['Servers'][\$i]['column_info'] = 'pma__column_info';
\$cfg['Servers'][\$i]['history'] = 'pma__history';
\$cfg['Servers'][\$i]['recent'] = 'pma__recent';
\$cfg['Servers'][\$i]['table_uiprefs'] = 'pma__table_uiprefs';
\$cfg['Servers'][\$i]['tracking'] = 'pma__tracking';
\$cfg['Servers'][\$i]['table_coords'] = 'pma__table_coords';
\$cfg['Servers'][\$i]['pdf_pages'] = 'pma__pdf_pages';
\$cfg['Servers'][\$i]['designer_coords'] = 'pma__designer_coords';
\$cfg['Servers'][\$i]['savedsearches'] = 'pma__savedsearches';
\$cfg['Servers'][\$i]['central_columns'] = 'pma__central_columns';
\$cfg['Servers'][\$i]['designer_settings'] = 'pma__designer_settings';
\$cfg['Servers'][\$i]['export_templates'] = 'pma__export_templates';
\$cfg['Servers'][\$i]['navigationhiding'] = 'pma__navigationhiding';
\$cfg['Servers'][\$i]['users'] = 'pma__users';
\$cfg['Servers'][\$i]['usergroups'] = 'pma__usergroups';
\$cfg['Servers'][\$i]['hide_db'] = 'information_schema';
PMACONF
			cat > /etc/phpmyadmin/conf.d/99-tempdir.php << PMATMP
<?php
\$cfg['TempDir'] = '/var/lib/phpmyadmin/tmp';
PMATMP

			chown -R root:hestiamail /etc/phpmyadmin/
			chmod 640 /etc/phpmyadmin/config.inc.php /etc/phpmyadmin/conf.d/*.php
			chmod 750 /etc/phpmyadmin/conf.d/
		else
			echo "  phpMyAdmin already installed at version $pma_v, skipping."
		fi
	else
		echo -e "\n[ * ] Skipping phpMyAdmin install (disabled via --no-pma)."
	fi
}
