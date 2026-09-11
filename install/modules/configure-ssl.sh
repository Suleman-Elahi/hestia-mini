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
		echo -e "\n${YELLOW}=== Panel Domain (Reverse Proxy + Let's Encrypt) ===${NC}"
		echo "  If you have a domain/subdomain (e.g. panel.example.com) pointed to this"
		echo "  server's IP, it will be added as a reverse-proxy domain and given a free"
		echo "  Let's Encrypt certificate, so the panel is reachable on the standard"
		echo "  HTTPS port (https://panel.example.com)."
		echo ""
		echo "  Requirements:"
		echo "    - The domain's DNS A record must point to this server"
		echo "    - Port 80 must be reachable from the internet (HTTP-01 challenge)"
		echo ""
		read -r -p "  Enter panel domain (or press Enter to skip): " panel_domain
	fi

	# Nothing to do if no domain provided
	if [ -z "$panel_domain" ]; then
		echo -e "\n[ * ] Skipping panel domain setup (no domain provided)."
		echo "      The panel will use a self-signed certificate on its own port."
		echo "      You can add it later from the panel:"
		echo "        Domains -> Add Domain -> https://127.0.0.1:$port"
		return 0
	fi

	echo -e "\n[ * ] Setting up panel domain: $panel_domain"

	# Validate domain format (basic check)
	if ! echo "$panel_domain" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'; then
		echo -e "  ${RED}Error: '$panel_domain' does not look like a valid domain.${NC}"
		echo "  Skipping Let's Encrypt setup. The panel will use a self-signed certificate."
		return 0
	fi

	# Resolve the panel backend (hestia-nginx HTTPS listener) port.
	local backend_port="${port:-${BACKEND_PORT:-8083}}"
	local backend_target="https://127.0.0.1:${backend_port}"

	# Register the panel domain as a managed reverse-proxy domain. Passing
	# SSL=yes makes Hestia issue and renew the Let's Encrypt certificate through
	# its own manager (no certbot), so the domain appears in Domains -> Reverse
	# Proxy and the panel becomes reachable on the standard HTTPS port (443).
	local domain_conf="$HESTIA/data/users/admin/domain.conf"
	if [ -f "$domain_conf" ] && grep -q "DOMAIN='$panel_domain'" "$domain_conf"; then
		echo "  Panel domain already configured, refreshing certificate..."
	else
		echo "  Creating reverse proxy for https://$panel_domain ..."
		if [ ! -x "$HESTIA/bin/v-add-domain" ]; then
			echo -e "  ${YELLOW}Warning: v-add-domain is unavailable. Skipping SSL setup.${NC}"
			return 0
		fi

		"$HESTIA/bin/v-add-domain" admin "$panel_domain" "$backend_target" \
			"round_robin" "yes" "yes" "manual" >> "$LOG" 2>&1
		if [ $? -ne 0 ]; then
			echo -e "  ${YELLOW}Warning: Could not create the panel reverse proxy / obtain a Let's Encrypt certificate.${NC}"
			echo "  The panel remains available at https://$panel_domain:${backend_port}"
			echo "  Check the log for details: $LOG"
			return 0
		fi
	fi

	# Reuse the issued certificate for the panel's own HTTPS listener so direct
	# :${backend_port} access is trusted as well. v-update-letsencrypt-ssl keeps
	# this copy refreshed on renewal.
	local user_ssl_dir="$HESTIA/data/users/admin/ssl"
	if [ -s "$user_ssl_dir/$panel_domain.crt" ] && [ -s "$user_ssl_dir/$panel_domain.key" ]; then
		cp -f "$user_ssl_dir/$panel_domain.crt" "$HESTIA/ssl/certificate.crt"
		cp -f "$user_ssl_dir/$panel_domain.key" "$HESTIA/ssl/certificate.key"
		chown root:mail "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
		chmod 660 "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
	fi

	# Update hostname in hestia.conf so the web terminal allow-list and
	# certificate renewal matching use the panel domain.
	if [ -f "$HESTIA/conf/hestia.conf" ]; then
		sed -i "s|^HOSTNAME=.*|HOSTNAME='$panel_domain'|" "$HESTIA/conf/hestia.conf"
	fi

	PANEL_DOMAIN="$panel_domain"

	# Reload the panel so the renewed certificate is served, then restart the
	# Web Terminal so WebSocket upgrades are accepted on both
	# https://<domain> and https://<domain>:<port>.
	systemctl restart hestia >> "$LOG" 2>&1 || true
	systemctl restart hestia-web-terminal >> "$LOG" 2>&1
	warn_only $? "Could not restart the web terminal service after setting the panel domain"

	echo -e "  ${GREEN}Panel reverse proxy and Let's Encrypt certificate configured!${NC}"
	echo "  Panel URL:  https://$panel_domain"
	echo "  Direct URL: https://$panel_domain:$backend_port"
	echo "  The certificate renews automatically with the rest of the panel."
}
