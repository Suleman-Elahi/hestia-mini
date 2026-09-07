#!/bin/bash

#===========================================================================#
#                                                                           #
# Hestia Control Panel - Domain Proxy Function Library                      #
#                                                                           #
#===========================================================================#

# Generate Nginx upstream block for a domain
# Usage: generate_upstream_block <domain> <algorithm> <targets>
generate_upstream_block() {
	local domain="$1"
	local algorithm="$2"
	local targets="$3"
	local upstream_name="$(echo "${domain}_backend" | tr '.-' '__')"

	echo "upstream ${upstream_name} {"

	case "$algorithm" in
		round_robin)
			# Default nginx behavior, no directive needed
			;;
		least_conn)
			echo "    least_conn;"
			;;
		ip_hash)
			echo "    ip_hash;"
			;;
		hash)
			echo "    hash \$request_uri consistent;"
			;;
		weighted)
			# Handled per-server line (weight=N)
			;;
	esac

	echo ""

	# Parse targets - each target is "IP:PORT [weight=N]"
	for target in $targets; do
		[ -z "$target" ] && continue
		echo "    server $target;"
	done

	echo "}"
}

# Generate Nginx server block for a domain
# Usage: generate_server_block <domain> <algorithm> <ssl_enabled> <ssl_cert_path> <ssl_key_path>
generate_server_block() {
	local domain="$1"
	local algorithm="$2"
	local ssl_enabled="$3"
	local ssl_cert_path="${4:-}"
	local ssl_key_path="${5:-}"
	local upstream_name="$(echo "${domain}_backend" | tr '.-' '__')"

	local has_valid_ssl="no"
	if [ "$ssl_enabled" = "yes" ] && [ -n "$ssl_cert_path" ] && [ -f "$ssl_cert_path" ] && [ -f "$ssl_key_path" ]; then
		has_valid_ssl="yes"
	fi

	echo "server {"
	echo "    listen 80;"
	if [ "$has_valid_ssl" = "yes" ]; then
		echo "    listen 443 ssl http2;"
	fi
	echo "    server_name $domain www.$domain;"
	echo ""

	# SSL configuration
	if [ "$has_valid_ssl" = "yes" ]; then
		echo "    ssl_certificate $ssl_cert_path;"
		echo "    ssl_certificate_key $ssl_key_path;"
		echo "    ssl_protocols TLSv1.2 TLSv1.3;"
		echo "    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;"
		echo "    ssl_prefer_server_ciphers off;"
		echo "    ssl_session_cache shared:SSL:10m;"
		echo "    ssl_session_timeout 1d;"
		echo "    ssl_session_tickets off;"
		echo ""

		echo "    if (\$scheme != \"https\") {"
		echo "        return 301 https://\$host\$request_uri;"
		echo "    }"
		echo ""
	fi

	echo "    location / {"
	echo "        proxy_pass http://${upstream_name};"
	echo "        proxy_set_header Host \$host;"
	echo "        proxy_set_header X-Real-IP \$remote_addr;"
	echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
	echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
	echo ""
	echo "        # WebSocket support"
	echo "        proxy_http_version 1.1;"
	echo "        proxy_set_header Upgrade \$http_upgrade;"
	echo "        proxy_set_header Connection \$http_connection;"
	echo ""
	echo "        # Timeouts"
	echo "        proxy_connect_timeout 60s;"
	echo "        proxy_send_timeout 60s;"
	echo "        proxy_read_timeout 60s;"
	echo "    }"
	echo "}"
}

# Write domain configuration to disk
# Usage: write_domain_config <user> <domain> <algorithm> <targets> <ssl_enabled>
write_domain_config() {
	local user="$1"
	local domain="$2"
	local algorithm="$3"
	local targets="$4"
	local ssl_enabled="${5:-no}"

	local conf_dir="$HOMEDIR/$user/conf/web"
	local domain_conf="$conf_dir/$domain.conf"
	local nginx_conf="/etc/nginx/conf.d/domain_${domain}.conf"

	# Ensure directories exist
	mkdir -p "$conf_dir"
	mkdir -p /etc/nginx/conf.d

	# Generate and write nginx config
	{
		generate_upstream_block "$domain" "$algorithm" "$targets"
		echo ""
		if [ "$ssl_enabled" = "yes" ]; then
			local cert_dir="$USER_DATA/ssl"
			generate_server_block "$domain" "$algorithm" "yes" \
				"$cert_dir/$domain.crt" "$cert_dir/$domain.key"
		else
			generate_server_block "$domain" "$algorithm" "no"
		fi
	} > "$nginx_conf"

	# Save user domain config
	echo "DOMAIN='$domain'" > "$domain_conf"
	echo "ALGORITHM='$algorithm'" >> "$domain_conf"
	echo "TARGETS='$targets'" >> "$domain_conf"
	echo "SSL='$ssl_enabled'" >> "$domain_conf"
	echo "SUSPENDED='no'" >> "$domain_conf"
	echo "TIME='$(date +'%T')'" >> "$domain_conf"
	echo "DATE='$(date +'%F')'" >> "$domain_conf"

	chmod 660 "$domain_conf"
}

# Remove domain Nginx configuration
# Usage: remove_domain_config <user> <domain>
remove_domain_config() {
	local user="$1"
	local domain="$2"

	rm -f "/etc/nginx/conf.d/domain_${domain}.conf"
	rm -f "/etc/nginx/conf.d/domains/${domain}.conf"
	rm -f "$HOMEDIR/$user/conf/web/$domain.conf"
}

# Test Nginx configuration
# Usage: test_nginx_config
test_nginx_config() {
	nginx -t 2>&1
	return $?
}

# Reload Nginx
# Usage: reload_nginx
reload_nginx() {
	systemctl reload nginx 2>&1
	return $?
}
