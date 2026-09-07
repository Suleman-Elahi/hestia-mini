#!/bin/bash
# ======================================================== #
# Hestia-Mini Install Module: SSL Configuration
# Called from hestia-mini-install.sh after services are up
# ======================================================== #

# This script is sourced by hestia-mini-install.sh and inherits:
#   $HESTIA, $LOG, $ADMIN_EMAIL, $ASSUME_YES, $port,
#   $PANEL_DOMAIN (CLI flag, may be empty),
#   check_result(), warn_only(), and color variables.

configure_panel_ssl() {
	local panel_domain="${PANEL_DOMAIN:-}"

	# If no domain was provided via CLI and we're interactive, ask
	if [ -z "$panel_domain" ] && [ "$ASSUME_YES" != 'yes' ]; then
		echo -e "\n${YELLOW}=== Panel SSL Configuration (Let's Encrypt) ===${NC}"
		echo "  If you have a domain/subdomain (e.g. panel.example.com) pointed to this"
		echo "  server's IP, we can automatically obtain a free Let's Encrypt SSL"
		echo "  certificate for the panel."
		echo ""
		echo "  Requirements:"
		echo "    - The domain's DNS A record must point to this server"
		echo "    - Port 80 must be temporarily available for the ACME challenge"
		echo ""
		read -r -p "  Enter panel domain (or press Enter to skip): " panel_domain
	fi

	# Nothing to do if no domain provided
	if [ -z "$panel_domain" ]; then
		echo -e "\n[ * ] Skipping Let's Encrypt SSL (no panel domain provided)."
		echo "      The panel will use a self-signed certificate."
		echo "      You can set up SSL later by running:"
		echo "        certbot certonly --standalone -d your-domain.com"
		echo "        Then copy certs to $HESTIA/ssl/ and restart hestia."
		return 0
	fi

	echo -e "\n[ * ] Setting up Let's Encrypt SSL for: $panel_domain"

	# Validate domain format (basic check)
	if ! echo "$panel_domain" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'; then
		echo -e "  ${RED}Error: '$panel_domain' does not look like a valid domain.${NC}"
		echo "  Skipping Let's Encrypt setup. The panel will use a self-signed certificate."
		return 0
	fi

	# Install certbot if not present
	if ! command -v certbot > /dev/null 2>&1; then
		echo "  Installing certbot..."
		apt-get -y install certbot >> "$LOG" 2>&1
		if [ $? -ne 0 ]; then
			echo -e "  ${YELLOW}Warning: Failed to install certbot. Skipping SSL setup.${NC}"
			return 0
		fi
	fi

	# Check if port 80 is free (temporarily stop nginx if it's using it)
	local nginx_was_on_80='no'
	if ss -tlnp 2>/dev/null | grep -q ':80 '; then
		if ss -tlnp 2>/dev/null | grep ':80 ' | grep -q 'nginx'; then
			echo "  Temporarily stopping nginx for ACME challenge..."
			systemctl stop nginx >> "$LOG" 2>&1
			nginx_was_on_80='yes'
		else
			echo -e "  ${YELLOW}Warning: Port 80 is in use by another service.${NC}"
			echo "  Let's Encrypt requires port 80 for domain validation."
			echo "  Skipping SSL setup. You can configure it manually later."
			return 0
		fi
	fi

	# Request certificate
	echo "  Requesting certificate from Let's Encrypt..."
	certbot certonly \
		--standalone \
		--non-interactive \
		--agree-tos \
		--email "$ADMIN_EMAIL" \
		--domain "$panel_domain" \
		--preferred-challenges http \
		>> "$LOG" 2>&1
	local cert_status=$?

	# Restart nginx if we stopped it
	if [ "$nginx_was_on_80" = 'yes' ]; then
		systemctl start nginx >> "$LOG" 2>&1
	fi

	if [ "$cert_status" -ne 0 ]; then
		echo -e "  ${YELLOW}Warning: Let's Encrypt certificate request failed.${NC}"
		echo "  The panel will continue with its self-signed certificate."
		echo "  Check the log for details: $LOG"
		echo "  You can retry later with:"
		echo "    certbot certonly --standalone -d $panel_domain"
		return 0
	fi

	# Deploy certificate
	local le_live="/etc/letsencrypt/live/$panel_domain"
	if [ ! -f "$le_live/fullchain.pem" ] || [ ! -f "$le_live/privkey.pem" ]; then
		echo -e "  ${YELLOW}Warning: Certificate files not found at $le_live${NC}"
		return 0
	fi

	echo "  Deploying certificate..."
	cp -L "$le_live/fullchain.pem" "$HESTIA/ssl/certificate.crt"
	cp -L "$le_live/privkey.pem" "$HESTIA/ssl/certificate.key"
	chown root:mail "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
	chmod 660 "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"

	# Create renewal deploy hook
	mkdir -p /etc/letsencrypt/renewal-hooks/deploy
	cat > /etc/letsencrypt/renewal-hooks/deploy/hestia-mini.sh << 'DEPLOY_HOOK'
#!/bin/bash
# Hestia-Mini: deploy renewed Let's Encrypt certificate
HESTIA='/usr/local/hestia'

for domain in $RENEWED_DOMAINS; do
	HOSTNAME_CONF=$(grep "^HOSTNAME=" "$HESTIA/conf/hestia.conf" 2>/dev/null | cut -d "'" -f2)
	if [ "$domain" = "$HOSTNAME_CONF" ]; then
		cp -L "$RENEWED_LINEAGE/fullchain.pem" "$HESTIA/ssl/certificate.crt"
		cp -L "$RENEWED_LINEAGE/privkey.pem" "$HESTIA/ssl/certificate.key"
		chown root:mail "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
		chmod 660 "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
		systemctl restart hestia 2>/dev/null || true
		systemctl restart dovecot 2>/dev/null || true
		systemctl restart exim4 2>/dev/null || true
		break
	fi
done
DEPLOY_HOOK
	chmod 755 /etc/letsencrypt/renewal-hooks/deploy/hestia-mini.sh

	# Enable certbot auto-renewal timer
	if systemctl list-unit-files certbot.timer > /dev/null 2>&1; then
		systemctl enable certbot.timer >> "$LOG" 2>&1
		systemctl start certbot.timer >> "$LOG" 2>&1
	else
		if ! crontab -l 2>/dev/null | grep -q 'certbot renew'; then
			(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/hestia-mini.sh") | crontab -
		fi
	fi

	# Update hostname in hestia.conf
	if [ -f "$HESTIA/conf/hestia.conf" ]; then
		sed -i "s|^HOSTNAME=.*|HOSTNAME='$panel_domain'|" "$HESTIA/conf/hestia.conf"
	fi

	PANEL_DOMAIN="$panel_domain"

	echo -e "  ${GREEN}Let's Encrypt SSL certificate installed successfully!${NC}"
	echo "  Certificate will auto-renew via certbot timer."
	echo "  Panel domain: https://$panel_domain:$port"
}
