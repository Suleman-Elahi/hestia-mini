#!/bin/bash

#===========================================================================#
#                                                                           #
# MiniPanel - Domain Function Library (mail + common only)                  #
# Derived from HestiaCP                                                     #
#                                                                           #
#===========================================================================#

#----------------------------------------------------------#
#                       MAIL                               #
#----------------------------------------------------------#

# Mail domain existence check
is_mail_domain_new() {
	mail=$(ls $HESTIA/data/users/*/mail/$1.conf 2> /dev/null)
	if [ -n "$mail" ]; then
		if [ "$2" == 'mail' ]; then
			check_result $E_EXISTS "Mail domain $1 exists"
		fi
		mail_user=$(echo "$mail" | cut -f 7 -d /)
		if [ "$mail_user" != "$user" ]; then
			check_result "$E_EXISTS" "Mail domain $1 exists"
		fi
	fi
	mail_sub=$(echo "$1" | cut -f 1 -d .)
	mail_nosub=$(echo "$1" | cut -f 1 -d . --complement)
	for mail_reserved in $(echo "mail $WEBMAIL_ALIAS"); do
		if [ -n "$(ls $HESTIA/data/users/*/mail/$mail_reserved.$1.conf 2> /dev/null)" ]; then
			if [ "$2" == 'mail' ]; then
				check_result "$E_EXISTS" "Required subdomain \"$mail_reserved.$1\" already exists"
			fi
		fi
		if [ -n "$(ls $HESTIA/data/users/*/mail/$mail_nosub.conf 2> /dev/null)" ] && [ "$mail_sub" = "$mail_reserved" ]; then
			if [ "$2" == 'mail' ]; then
				check_result "$E_INVALID" "The subdomain \"$mail_sub.\" is reserved by \"$mail_nosub\""
			fi
		fi
	done
}

# Checking mail account existence
is_mail_new() {
	check_acc=$(grep "ACCOUNT='$1'" $USER_DATA/mail/$domain.conf)
	if [ -n "$check_acc" ]; then
		check_result "$E_EXISTS" "mail account $1 already exists"
	fi
	check_als=$(awk -F "ALIAS='" '{print $2}' $USER_DATA/mail/$domain.conf)
	match=$(echo "$check_als" | cut -f 1 -d "'" | grep $1)
	if [ -n "$match" ]; then
		parse_object_kv_list $(grep "ALIAS='$match'" $USER_DATA/mail/$domain.conf)
		check_als=$(echo ",$ALIAS," | grep ",$1,")
		if [ -n "$check_als" ]; then
			check_result "$E_EXISTS" "mail alias $1 already exists"
		fi
	fi
}

# Add mail server SSL configuration
add_mail_ssl_config() {
	# Ensure that SSL certificate directories exists
	if [ ! -d "$HOMEDIR/$user/conf/mail/$domain/ssl/" ]; then
		mkdir -p $HOMEDIR/$user/conf/mail/$domain/ssl/
	fi

	if [ ! -d "$HESTIA/ssl/mail" ]; then
		mkdir -p $HESTIA/ssl/mail
	fi

	if [ ! -d /etc/dovecot/conf.d/domains ]; then
		mkdir -p /etc/dovecot/conf.d/domains
	fi

	# Add certificate to Hestia user configuration data directory
	if [ -f "$ssl_dir/$domain.crt" ]; then
		cp -f $ssl_dir/$domain.crt $USER_DATA/ssl/mail.$domain.crt
		cp -f $ssl_dir/$domain.key $USER_DATA/ssl/mail.$domain.key
		cp -f $ssl_dir/$domain.crt $USER_DATA/ssl/mail.$domain.pem
		if [ -e "$ssl_dir/$domain.ca" ]; then
			cp -f $ssl_dir/$domain.ca $USER_DATA/ssl/mail.$domain.ca
			echo >> $USER_DATA/ssl/mail.$domain.pem
			cat $USER_DATA/ssl/mail.$domain.ca >> $USER_DATA/ssl/mail.$domain.pem
		fi
	fi

	chmod 660 $USER_DATA/ssl/mail.$domain.*

	# Add certificate to user home directory
	cp -f $USER_DATA/ssl/mail.$domain.crt $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.crt
	cp -f $USER_DATA/ssl/mail.$domain.key $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key
	cp -f $USER_DATA/ssl/mail.$domain.pem $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem
	if [ -e "$USER_DATA/ssl/mail.$domain.ca" ]; then
		cp -f $USER_DATA/ssl/mail.$domain.ca $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.ca
	fi

	# Clean up dovecot configuration (if it exists)
	if [ -f /etc/dovecot/conf.d/domains/$domain.conf ]; then
		rm -f /etc/dovecot/conf.d/domains/$domain.conf
	fi

	# Check if using custom / wildcard mail certificate
	wildcard_domain="\\*.$(echo "$domain" | cut -f 1 -d . --complement)"
	mail_cert_match=$($BIN/v-list-mail-domain-ssl $user $domain | awk '/SUBJECT|ALIASES/' | grep -wE " $domain| $wildcard_domain")
	dovecot_version="$(dovecot --version | cut -f -2 -d .)"

	if [ -n "$mail_cert_match" ]; then
		if [[ "$dovecot_version" = "2.4" ]]; then
			# Add domain SSL configuration to dovecot
			echo "" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "local_name $domain {" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "  ssl_server_cert_file = $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "  ssl_server_key_file = $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "}" >> /etc/dovecot/conf.d/domains/$domain.conf
		else
			echo "" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "local_name $domain {" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "  ssl_cert = <$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "  ssl_key = <$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key" >> /etc/dovecot/conf.d/domains/$domain.conf
			echo "}" >> /etc/dovecot/conf.d/domains/$domain.conf
		fi
		# Add domain SSL configuration to exim4
		ln -s $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem $HESTIA/ssl/mail/$domain.crt
		ln -s $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key $HESTIA/ssl/mail/$domain.key
	fi

	# Add domain SSL configuration to dovecot
	if [[ "$dovecot_version" = "2.4" ]]; then
		# Add domain SSL configuration to dovecot
		echo "" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "local_name mail.$domain {" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "  ssl_server_cert_file = $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "  ssl_server_key_file = $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "}" >> /etc/dovecot/conf.d/domains/$domain.conf
	else
		echo "" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "local_name mail.$domain {" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "  ssl_cert = <$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "  ssl_key = <$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key" >> /etc/dovecot/conf.d/domains/$domain.conf
		echo "}" >> /etc/dovecot/conf.d/domains/$domain.conf
	fi

	# Add domain SSL configuration to exim4
	ln -s $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem $HESTIA/ssl/mail/mail.$domain.crt
	ln -s $HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key $HESTIA/ssl/mail/mail.$domain.key

	# Set correct permissions on certificates
	chmod 0750 $HOMEDIR/$user/conf/mail/$domain/ssl
	chown -R $MAIL_USER:mail $HOMEDIR/$user/conf/mail/$domain/ssl
	chmod 0644 $HOMEDIR/$user/conf/mail/$domain/ssl/*
	chown -h $user:mail $HOMEDIR/$user/conf/mail/$domain/ssl/*
	chmod -R 0644 $HESTIA/ssl/mail/*
	chown -h $user:mail $HESTIA/ssl/mail/*
}

# Delete SSL support for mail domain
del_mail_ssl_config() {
	# Check to prevent accidental removal of mismatched certificate
	wildcard_domain="\\*.$(echo "$domain" | cut -f 1 -d . --complement)"
	mail_cert_match=$($BIN/v-list-mail-domain-ssl $user $domain | awk '/SUBJECT|ALIASES/' | grep -wE " $domain| $wildcard_domain")

	# Remove old mail certificates
	rm -f $HOMEDIR/$user/conf/mail/$domain/ssl/*

	# Remove dovecot configuration
	rm -f /etc/dovecot/conf.d/domains/$domain.conf

	# Remove SSL vhost configuration
	rm -f $HOMEDIR/$user/conf/mail/$domain/*.*ssl.conf
	rm -f /etc/$WEB_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
	rm -f /etc/$PROXY_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf

	# Remove SSL certificates
	rm -f $HOMEDIR/$user/conf/mail/$domain/ssl/*
	if [ -n "$mail_cert_match" ]; then
		rm -f $HESTIA/ssl/mail/$domain.crt $HESTIA/ssl/mail/$domain.key
	fi
	rm -f $HESTIA/ssl/mail/mail.$domain.crt $HESTIA/ssl/mail/mail.$domain.key
}

# Delete generated certificates from user configuration data directory
del_mail_ssl_certificates() {
	rm -f $USER_DATA/ssl/mail.$domain.ca
	rm -f $USER_DATA/ssl/mail.$domain.crt
	rm -f $USER_DATA/ssl/mail.$domain.key
	rm -f $USER_DATA/ssl/mail.$domain.pem
	rm -f $HOMEDIR/$user/conf/mail/$domain/ssl/*
}

# Add webmail config
add_webmail_config() {
	mkdir -p "$HOMEDIR/$user/conf/mail/$domain"
	conf="$HOMEDIR/$user/conf/mail/$domain/$1.conf"
	if [[ "$2" =~ stpl$ ]]; then
		conf="$HOMEDIR/$user/conf/mail/$domain/$1.ssl.conf"
	fi

	domain_idn=$domain
	format_domain_idn

	ssl_crt="$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.crt"
	ssl_key="$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.key"
	ssl_pem="$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.pem"
	ssl_ca="$HOMEDIR/$user/conf/mail/$domain/ssl/$domain.ca"

	override_alias=""
	if [ "$WEBMAIL_ALIAS" != "mail" ]; then
		override_alias="mail.$domain"
		override_alias_idn="mail.$domain_idn"
	fi

	# Note: Removing or renaming template variables will lead to broken custom templates.
	#   -If possible custom templates should be automatically upgraded to use the new format
	#   -Alternatively a depreciation period with proper notifications should be considered

	cat $MAILTPL/$1/$2 \
		| sed -e "s|%ip%|$local_ip|g" \
			-e "s|%domain%|$WEBMAIL_ALIAS.$domain|g" \
			-e "s|%domain_idn%|$WEBMAIL_ALIAS.$domain_idn|g" \
			-e "s|%root_domain%|$domain|g" \
			-e "s|%alias%|$override_alias|g" \
			-e "s|%alias_idn%|$override_alias_idn|g" \
			-e "s|%alias_string%|$alias_string|g" \
			-e "s|%email%|info@$domain|g" \
			-e "s|%web_system%|$WEB_SYSTEM|g" \
			-e "s|%web_port%|$WEB_PORT|g" \
			-e "s|%web_ssl_port%|$WEB_SSL_PORT|g" \
			-e "s|%backend_lsnr%|$backend_lsnr|g" \
			-e "s|%rgroups%|$WEB_RGROUPS|g" \
			-e "s|%proxy_system%|$PROXY_SYSTEM|g" \
			-e "s|%proxy_port%|$PROXY_PORT|g" \
			-e "s|%proxy_ssl_port%|$PROXY_SSL_PORT|g" \
			-e "s/%proxy_extensions%/${PROXY_EXT//,/|}/g" \
			-e "s|%user%|$user|g" \
			-e "s|%group%|$user|g" \
			-e "s|%home%|$HOMEDIR|g" \
			-e "s|%docroot%|$docroot|g" \
			-e "s|%sdocroot%|$sdocroot|g" \
			-e "s|%ssl_crt%|$ssl_crt|g" \
			-e "s|%ssl_key%|$ssl_key|g" \
			-e "s|%ssl_pem%|$ssl_pem|g" \
			-e "s|%ssl_ca_str%|$ssl_ca_str|g" \
			-e "s|%ssl_ca%|$ssl_ca|g" \
			> $conf

	process_http2_directive "$conf"

	chown root:$user $conf
	chmod 640 $conf

	if [[ "$2" =~ stpl$ ]]; then
		if [ -n "$WEB_SYSTEM" ]; then
			forcessl="$HOMEDIR/$user/conf/mail/$domain/$WEB_SYSTEM.forcessl.conf"
			rm -f /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
			ln -s $conf /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
		fi
		if [ -n "$PROXY_SYSTEM" ]; then
			forcessl="$HOMEDIR/$user/conf/mail/$domain/$PROXY_SYSTEM.forcessl.conf"
			rm -f /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
			ln -s $conf /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
		fi

		# Add rewrite rules to force HTTPS/SSL connections
		if [ -n "$PROXY_SYSTEM" ] || [ "$WEB_SYSTEM" = 'nginx' ]; then
			echo 'return 301 https://$server_name$request_uri;' > $forcessl
		else
			echo 'RewriteEngine On' > $forcessl
			echo 'RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]' >> $forcessl
		fi

		# Remove old configurations
		find $HOMEDIR/$user/conf/mail/ -maxdepth 1 -type f \( -name "$domain.*" -o -name "ssl.$domain.*" -o -name "*nginx.$domain.*" \) -exec rm {} \;
	else
		if [ -n "$WEB_SYSTEM" ]; then
			rm -f /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
			ln -s $conf /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
		fi
		if [ -n "$PROXY_SYSTEM" ]; then
			rm -f /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
			ln -s $conf /etc/$1/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
		fi
		# Clear old configurations
		find $HOMEDIR/$user/conf/mail/ -maxdepth 1 -type f \( -name "$domain.*" \) -exec rm {} \;
	fi
}

# Delete webmail support
del_webmail_config() {
	if [ -n "$WEB_SYSTEM" ]; then
		rm -f $HOMEDIR/$user/conf/mail/$domain/$WEB_SYSTEM.conf
		rm -f /etc/$WEB_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
	fi

	if [ -n "$PROXY_SYSTEM" ]; then
		rm -f $HOMEDIR/$user/conf/mail/$domain/$PROXY_SYSTEM.*conf
		rm -f /etc/$PROXY_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.conf
	fi
}

# Delete SSL webmail support
del_webmail_ssl_config() {
	if [ -n "$WEB_SYSTEM" ]; then
		rm -f $HOMEDIR/$user/conf/mail/$domain/$WEB_SYSTEM.*ssl.conf
		rm -f /etc/$WEB_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
	fi

	if [ -n "$PROXY_SYSTEM" ]; then
		rm -f $HOMEDIR/$user/conf/mail/$domain/$PROXY_SYSTEM.*ssl.conf
		rm -f /etc/$PROXY_SYSTEM/conf.d/domains/$WEBMAIL_ALIAS.$domain.ssl.conf
	fi
}

#----------------------------------------------------------#
#                        CMN                               #
#----------------------------------------------------------#

# Checking domain existence
is_domain_new() {
	type=$1
	for object in ${2//,/ }; do
		if [ -n "$MAIL_SYSTEM" ]; then
			is_mail_domain_new $object $type
		fi
	done
}

# Get domain variables
get_domain_values() {
	parse_object_kv_list $(grep "DOMAIN='$domain'" $USER_DATA/$1.conf)
}

#----------------------------------------------------------#
# 2 Char domain name detection                             #
#----------------------------------------------------------#

is_valid_extension() {
	local psl
	psl="https://publicsuffix.org/list/public_suffix_list.dat"
	if [ ! -e "$HESTIA/data/extensions/public_suffix_list.dat" ]; then
		mkdir -p "$HESTIA/data/extensions/"
		chmod 750 "$HESTIA/data/extensions/"
		if /usr/bin/wget --tries=3 --timeout=15 --read-timeout=15 --waitretry=3 --no-dns-cache --quiet -O "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$psl"; then
			mv "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$HESTIA/data/extensions/public_suffix_list.dat"
		else
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.tmp"
		fi
	elif find "$HESTIA/data/extensions/public_suffix_list.dat" -mtime +7 2> /dev/null | grep -q .; then
		mv "$HESTIA/data/extensions/public_suffix_list.dat" "$HESTIA/data/extensions/public_suffix_list.dat.save"
		if /usr/bin/wget --tries=3 --timeout=15 --read-timeout=15 --waitretry=3 --no-dns-cache --quiet -O "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$psl"; then
			mv "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$HESTIA/data/extensions/public_suffix_list.dat"
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.save"
		else
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.tmp"
			mv "$HESTIA/data/extensions/public_suffix_list.dat.save" "$HESTIA/data/extensions/public_suffix_list.dat"
		fi
	fi
	if [ ! -e "$HESTIA/data/extensions/public_suffix_list.dat" ]; then
		check_result "$E_NOTEXIST" "public_suffix_list.dat not found"
	fi
	test_domain=$(idn2 -d "$1")
	extension="${test_domain##*.}"
	exten=$(grep -Fx "$extension" "$HESTIA/data/extensions/public_suffix_list.dat")
}

is_valid_2_part_extension() {
	local psl
	psl="https://publicsuffix.org/list/public_suffix_list.dat"
	if [ ! -e "$HESTIA/data/extensions/public_suffix_list.dat" ]; then
		mkdir -p "$HESTIA/data/extensions/"
		chmod 750 "$HESTIA/data/extensions/"
		if /usr/bin/wget --tries=3 --timeout=15 --read-timeout=15 --waitretry=3 --no-dns-cache --quiet -O "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$psl"; then
			mv "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$HESTIA/data/extensions/public_suffix_list.dat"
		else
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.tmp"
		fi
	elif find "$HESTIA/data/extensions/public_suffix_list.dat" -mtime +7 2> /dev/null | grep -q .; then
		mv "$HESTIA/data/extensions/public_suffix_list.dat" "$HESTIA/data/extensions/public_suffix_list.dat.save"
		if /usr/bin/wget --tries=3 --timeout=15 --read-timeout=15 --waitretry=3 --no-dns-cache --quiet -O "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$psl"; then
			mv "$HESTIA/data/extensions/public_suffix_list.dat.tmp" "$HESTIA/data/extensions/public_suffix_list.dat"
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.save"
		else
			rm -f "$HESTIA/data/extensions/public_suffix_list.dat.tmp"
			mv "$HESTIA/data/extensions/public_suffix_list.dat.save" "$HESTIA/data/extensions/public_suffix_list.dat"
		fi
	fi
	if [ ! -e "$HESTIA/data/extensions/public_suffix_list.dat" ]; then
		check_result "$E_NOTEXIST" "public_suffix_list.dat not found"
	fi
	test_domain=$(idn2 -d "$1")
	extension=$(/bin/echo "${test_domain}" | awk -F. '{print $(NF-1)"."$NF}')
	exten=$(grep -Fx "$extension" "$HESTIA/data/extensions/public_suffix_list.dat")
}

get_base_domain() {
	test_domain=$1
	is_valid_extension "$test_domain"
	if [ $? -ne 0 ]; then
		basedomain=$(/bin/echo "${test_domain}" | /usr/bin/rev | /usr/bin/cut -d "." --output-delimiter="." -f 1-2 | /usr/bin/rev)
	else
		is_valid_2_part_extension "$test_domain"
		if [ $? -ne 0 ]; then
			basedomain=$(/bin/echo "${test_domain}" | /usr/bin/rev | /usr/bin/cut -d "." --output-delimiter="." -f 1-2 | /usr/bin/rev)
		else
			extension=$(/bin/echo "${test_domain}" | /usr/bin/rev | /usr/bin/cut -d "." --output-delimiter="." -f 1-2 | /usr/bin/rev)
			partdomain=$(/bin/echo "${test_domain}" | /usr/bin/rev | /usr/bin/cut -d "." --output-delimiter="." -f 3 | /usr/bin/rev)
			basedomain="$partdomain.$extension"
		fi
	fi
}

is_base_domain_owner() {
	for object in ${1//,/ }; do
		if [ "$object" != "none" ]; then
			get_base_domain $object
			web=$(grep -F -H -h "DOMAIN='$basedomain'" $HESTIA/data/users/*/web.conf)
			if [ "$ENFORCE_SUBDOMAIN_OWNERSHIP" = "yes" ]; then
				if [ -n "$web" ]; then
					parse_object_kv_list "$web"
					if [ -z "$ALLOW_USERS" ] || [ "$ALLOW_USERS" != "yes" ]; then
						# Don't care if $basedomain all ready exists only if the owner is of the base domain is the current user
						check=$(is_domain_new "" $basedomain)
						if [ $? -ne 0 ]; then
							echo "Error: Unable to add $object. $basedomain belongs to a different user"
							exit 4
						fi
					fi
				else
					check=$(is_domain_new "" "$basedomain")
					if [ $? -ne 0 ]; then
						echo "Error: Unable to add $object. $basedomain belongs to a different user"
						exit 4
					fi
				fi
			fi
		fi
	done
}

#----------------------------------------------------------#
#           Process "http2" directive for NGINX            #
#----------------------------------------------------------#

process_http2_directive() {
	if [ -e /etc/nginx/conf.d/http2-directive.conf ]; then
		while IFS= read -r old_param; do
			new_param="$(echo "$old_param" | sed 's/\shttp2//')"
			sed -i "s/$old_param/$new_param/" "$1"
		done < <(grep -E "listen.*(\bssl\b(\s|.+){1,}\bhttp2\b|\bhttp2\b(\s|.+){1,}\bssl\b).*;" "$1")
	else
		if version_ge "$(nginx -v 2>&1 | cut -d'/' -f2)" "1.25.1"; then
			echo "http2 on;" > /etc/nginx/conf.d/http2-directive.conf

			while IFS= read -r old_param; do
				new_param="$(echo "$old_param" | sed 's/\shttp2//')"
				sed -i "s/$old_param/$new_param/" "$1"
			done < <(grep -E "listen.*(\bssl\b(\s|.+){1,}\bhttp2\b|\bhttp2\b(\s|.+){1,}\bssl\b).*;" "$1")
		else
			listen_ssl="$(grep -E "listen.*\s\bssl\b(?:\s)*.*;" "$1")"
			listen_http2="$(grep -E "listen.*(\bssl\b(\s|.+){1,}\bhttp2\b|\bhttp2\b(\s|.+){1,}\bssl\b).*;" "$1")"

			if [ -n "$listen_ssl" ] && [ -z "$listen_http2" ]; then
				while IFS= read -r old_param; do
					new_param="$(echo "$old_param" | sed 's/\sssl/ ssl http2/')"
					sed -i "s/$old_param/$new_param/" "$1"
				done < <(grep -E "listen.*\s\bssl\b(?:\s)*.*;" "$1")
			fi
		fi
	fi
}
