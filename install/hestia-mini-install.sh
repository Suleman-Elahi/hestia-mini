#!/bin/bash

# ======================================================== #
#
# Hestia-Mini Installer
# A stripped-down admin panel derived from HestiaCP
# Supports: Mail, Database, File Management
#
# ======================================================== #

export PATH=$PATH:/sbin
export DEBIAN_FRONTEND=noninteractive
unset LC_ALL LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION LANGUAGE
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
RHOST='apt.hestiacp.com'
VERSION='debian'
HESTIA='/usr/local/hestia'
LOG="/root/hestia_mini_install-$(date +%d%m%Y%H%M).log"
spinner="/\-|"
os=$(cat /etc/os-release | grep ^ID= | cut -f 2 -d =)
release=$(cat /etc/debian_version | tr "." "\n" | head -n1)
codename=$(cat /etc/os-release | grep VERSION= | cut -f 2 -d \( | cut -f 1 -d \))
architecture=$(arch)
HESTIA_INSTALL_DIR="$HESTIA/install/deb"
HESTIA_COMMON_DIR="$HESTIA/install/common"
VERBOSE='no'

# Directory of this script, so we can find bin/func/install sources
# regardless of where the repo was checked out.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HESTIA_MINI_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
MINIPANEL_SRC="$HESTIA_MINI_SRC"

# Define software versions
HESTIA_MINI_VERSION='1.0.0'
MINIPANEL_VERSION="$HESTIA_MINI_VERSION"
HESTIA_INSTALL_VER='1.10.4'

case "$os" in
	ubuntu)
		os_id="ubuntu${release}"
		;;
	debian)
		os_id="debian${release}"
		;;
	*)
		os_id=''
		;;
esac
HESTIA_BASE_VER="${HESTIA_INSTALL_VER%%~*}"
if [[ "$HESTIA_INSTALL_VER" == *"~"* ]]; then
	HESTIA_CHANNEL="~${HESTIA_INSTALL_VER#*~}"
else
	HESTIA_CHANNEL=""
fi
HESTIA_INSTALL_BUILD="${HESTIA_BASE_VER}-1+${os_id}${HESTIA_CHANNEL}"

# Supported PHP version (also used for phpMyAdmin/phpPgAdmin/panel PHP-FPM pool)
fpm_v="8.2"
# MariaDB version
mariadb_v="11.8"
# phpMyAdmin version to install
pma_v="5.2.3"
# phpPgAdmin version to install (Hestia-maintained fork, since upstream
# phppgadmin releases predate PHP 8 support)
pga_v="7.14.6"
# File Manager (Filegator) version
fm_v="7.15.1"

# Defining software pack - minimal: mail + database (MySQL/MariaDB) + file manager
software="acl apt-transport-https ca-certificates clamav-daemon cron curl dovecot-imapd
  dovecot-managesieved dovecot-pop3d dovecot-sieve exim4 exim4-daemon-heavy expect
  git hestia=${HESTIA_INSTALL_BUILD} hestia-nginx hestia-php hestia-web-terminal jq libmail-dkim-perl lsb-release
  mariadb-client mariadb-common mariadb-server mc net-tools nodejs
  nginx php${fpm_v} php${fpm_v}-apcu php${fpm_v}-bcmath php${fpm_v}-bz2 php${fpm_v}-cgi
  php${fpm_v}-cli php${fpm_v}-common php${fpm_v}-curl php${fpm_v}-gd php${fpm_v}-imagick
  php${fpm_v}-imap php${fpm_v}-intl php${fpm_v}-ldap php${fpm_v}-mbstring
  php${fpm_v}-mysql php${fpm_v}-pspell php${fpm_v}-readline
  php${fpm_v}-xml php${fpm_v}-zip php${fpm_v}-fpm spamd unrar-free
  unzip util-linux vim-common whois zip zstd restic composer"

installer_dependencies="apt-transport-https ca-certificates curl dirmngr gnupg openssl wget sudo"

#----------------------------------------------------------#
#                  Variables & Functions                     #
#----------------------------------------------------------#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Non-interactive flags (can be overridden via env or CLI flags below)
ASSUME_YES='no'
PURGE_STUB_MTA='ask'
PGSQL_ENABLE='no'
PMA_INSTALL='yes'
PGA_INSTALL='no'
FM_INSTALL='yes'
ADMIN_EMAIL=''
ADMIN_PASSWORD=''
PROXY_PORT='8080'
PMA_BACKEND_PORT='8081'
PGA_BACKEND_PORT='8082'

while [ $# -gt 0 ]; do
	case "$1" in
		--yes | -y)
			ASSUME_YES='yes'
			shift
			;;
		--purge-mta)
			PURGE_STUB_MTA='yes'
			shift
			;;
		--no-purge-mta)
			PURGE_STUB_MTA='no'
			shift
			;;
		--postgresql | --pgsql)
			PGSQL_ENABLE='yes'
			PGA_INSTALL='yes'
			shift
			;;
		--no-pgsql)
			PGSQL_ENABLE='no'
			PGA_INSTALL='no'
			shift
			;;
		--no-pma)
			PMA_INSTALL='no'
			shift
			;;
		--pga)
			PGA_INSTALL='yes'
			shift
			;;
		--no-pga)
			PGA_INSTALL='no'
			shift
			;;
		--no-filemanager)
			FM_INSTALL='no'
			shift
			;;
		--admin-email)
			ADMIN_EMAIL="$2"
			shift 2
			;;
		--admin-password)
			ADMIN_PASSWORD="$2"
			shift 2
			;;
		--proxy-port)
			PROXY_PORT="$2"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [options]"
			echo "  --yes, -y             Non-interactive: assume yes to all prompts"
			echo "  --purge-mta           Automatically purge a conflicting stub MTA on port 25"
			echo "  --no-purge-mta        Never purge, just warn"
			echo "  --no-pgsql            Skip enabling PostgreSQL"
			echo "  --no-pma              Skip installing phpMyAdmin"
			echo "  --no-pga              Skip installing phpPgAdmin"
			echo "  --no-filemanager      Skip installing the File Manager"
			echo "  --admin-email EMAIL   Admin contact email (default: admin@<hostname>)"
			echo "  --admin-password PASS Admin password (default: randomly generated)"
			echo "  --proxy-port PORT     Reverse-proxy port for phpMyAdmin/phpPgAdmin (default: 8080)"
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

spinner() {
	local pid=$1
	local delay=0.1
	local spinstr='|/-\'
	while [ "$(ps -p $pid -o pid=)" ] 2>/dev/null; do
		local temp=${spinstr#?}
		printf " [%c]  " "$spinstr"
		spinstr=$temp${spinstr%"${temp}"}
		sleep $delay
		printf "\b\b\b\b\b\b"
	done
	echo -ne '\b\b\b\b\b\b'
}

check_result() {
	if [ $1 -eq 0 ]; then
		echo -e "[${GREEN} OK ${NC}]"
	else
		echo -e "[${RED} FAILED ${NC}]"
		echo "  Error: $2"
		echo "  Details: $LOG"
		if [ "$VERBOSE" = 'yes' ]; then
			echo "  Last 5 lines of log:"
			tail -5 "$LOG"
		fi
		exit $1
	fi
}

warn_only() {
	if [ $1 -ne 0 ]; then
		echo -e "[${YELLOW} WARN ${NC}]"
		echo "  Warning: $2"
	else
		echo -e "[${GREEN} OK ${NC}]"
	fi
}

gen_pass() {
	local length=$1
	local chars=$2
	local password=""
	for i in $(seq 1 $length); do
		password+="${chars:RANDOM%${#chars}:1}"
	done
	echo "$password"
}

# Finds the first free TCP port in a candidate list; prints it and returns 0,
# or returns 1 if none are free.
find_free_port() {
	for p in "$@"; do
		if ! ss -tlnp 2>/dev/null | grep -q ":$p "; then
			echo "$p"
			return 0
		fi
	done
	return 1
}

port_in_use() {
	ss -tlnp 2>/dev/null | grep -q ":$1 "
}

sort_config_file() {
	local config_file="$HESTIA/conf/hestia.conf"
	if [ -f "$config_file" ]; then
		sort "$config_file" -o "$config_file"
	fi
	if [ -f "$config_file" ] && [ ! -e "$HESTIA/conf/minipanel.conf" ]; then
		ln -sf "$config_file" "$HESTIA/conf/minipanel.conf"
	fi
}

install_hestia_key() {
	mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
	local downloaded='no'
	rm -f /tmp/hestia_key.asc /tmp/hestia_key.gpg

	for url in "https://apt.hestiacp.com/pubkey.gpg" "https://gpg.hestiacp.com/deb_signing.key"; do
		if command -v curl > /dev/null 2>&1; then
			if curl -4 -fsSL --retry 3 "$url" -o /tmp/hestia_key.asc 2>> "$LOG" || curl -fsSL --retry 3 "$url" -o /tmp/hestia_key.asc 2>> "$LOG"; then
				downloaded='yes'
				break
			fi
		elif command -v wget > /dev/null 2>&1; then
			if wget -4 -qO /tmp/hestia_key.asc "$url" 2>> "$LOG" || wget -qO /tmp/hestia_key.asc "$url" 2>> "$LOG"; then
				downloaded='yes'
				break
			fi
		fi
	done

	if [ "$downloaded" != 'yes' ] || [ ! -s /tmp/hestia_key.asc ]; then
		cat << 'KEY_EOF' > /tmp/hestia_key.asc
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
a2xXGjpPOaH0xuLCMe+7bw==
=6H1w
-----END PGP PUBLIC KEY BLOCK-----
KEY_EOF
	fi

	if [ -s /tmp/hestia_key.asc ]; then
		if command -v gpg > /dev/null 2>&1; then
			gpg --batch --yes --dearmor -o /tmp/hestia_key.gpg /tmp/hestia_key.asc 2>> "$LOG"
			if [ -f /tmp/hestia_key.gpg ] && [ -s /tmp/hestia_key.gpg ]; then
				mv -f /tmp/hestia_key.gpg /usr/share/keyrings/hestia-keyring.gpg
			else
				cp -f /tmp/hestia_key.asc /usr/share/keyrings/hestia-keyring.gpg
			fi
		else
			cp -f /tmp/hestia_key.asc /usr/share/keyrings/hestia-keyring.gpg
		fi
		rm -f /tmp/hestia_key.asc /tmp/hestia_key.gpg
		return 0
	fi

	return 1
}

install_sury_key() {
	mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
	local downloaded='no'
	rm -f /tmp/sury_key.asc /tmp/sury_key.gpg

	for url in "https://packages.sury.org/php/apt.gpg"; do
		if command -v curl > /dev/null 2>&1; then
			if curl -4 -fsSL --retry 3 "$url" -o /tmp/sury_key.asc 2>> "$LOG" || curl -fsSL --retry 3 "$url" -o /tmp/sury_key.asc 2>> "$LOG"; then
				downloaded='yes'
				break
			fi
		elif command -v wget > /dev/null 2>&1; then
			if wget -4 -qO /tmp/sury_key.asc "$url" 2>> "$LOG" || wget -qO /tmp/sury_key.asc "$url" 2>> "$LOG"; then
				downloaded='yes'
				break
			fi
		fi
	done

	if [ "$downloaded" = 'yes' ] && [ -s /tmp/sury_key.asc ]; then
		if command -v gpg > /dev/null 2>&1; then
			gpg --batch --yes --dearmor -o /tmp/sury_key.gpg /tmp/sury_key.asc 2>> "$LOG"
			if [ -f /tmp/sury_key.gpg ] && [ -s /tmp/sury_key.gpg ]; then
				mv -f /tmp/sury_key.gpg /usr/share/keyrings/sury-keyring.gpg
			else
				cp -f /tmp/sury_key.asc /usr/share/keyrings/sury-keyring.gpg
			fi
		else
			cp -f /tmp/sury_key.asc /usr/share/keyrings/sury-keyring.gpg
		fi
		rm -f /tmp/sury_key.asc /tmp/sury_key.gpg
		return 0
	fi
	return 1
}

install_node_key() {
	mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
	rm -f /tmp/nodejs_key.asc /tmp/nodejs_key.gpg

	if curl -4 -fsSL --retry 3 https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodejs_key.asc 2>> "$LOG" ||
		curl -fsSL --retry 3 https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodejs_key.asc 2>> "$LOG"; then
		gpg --batch --yes --dearmor -o /tmp/nodejs_key.gpg /tmp/nodejs_key.asc 2>> "$LOG"
		if [ -s /tmp/nodejs_key.gpg ]; then
			mv -f /tmp/nodejs_key.gpg /usr/share/keyrings/nodejs.gpg
			rm -f /tmp/nodejs_key.asc
			return 0
		fi
	fi

	rm -f /tmp/nodejs_key.asc /tmp/nodejs_key.gpg
	return 1
}

#----------------------------------------------------------#
#                    Pre-flight checks                      #
#----------------------------------------------------------#

echo -e "\n"
echo "====================================================="
echo "       Hestia-Mini Installer v${HESTIA_MINI_VERSION}"
echo "   Derived from HestiaCP (https://hestiacp.com)"
echo "====================================================="
echo -e "\n"

# Root check
if [ "$(id -u)" -ne 0 ]; then
	echo -e "${RED}Error: This installer must be run as root.${NC}"
	exit 1
fi

# OS check
if [ "$os" != "debian" ] && [ "$os" != "ubuntu" ]; then
	echo -e "${RED}Error: Unsupported OS: $os${NC}"
	echo "  Supported: Debian 11/12/13, Ubuntu 22.04/24.04/26.04"
	exit 1
fi

if [ "$os" = "debian" ] && [ "$release" != "11" ] && [ "$release" != "12" ] && [ "$release" != "13" ]; then
	echo -e "${YELLOW}Warning: Debian $release is not an officially supported version (11/12/13).${NC}"
	if [ "$ASSUME_YES" != 'yes' ]; then
		read -r -p "Continue anyway? [y/N] " reply
		[[ "$reply" =~ ^[Yy]$ ]] || exit 1
	fi
fi
if [ "$os" = "ubuntu" ]; then
	ubuntu_ver=$(. /etc/os-release && echo "$VERSION_ID")
	case "$ubuntu_ver" in
		22.04 | 24.04 | 26.04) ;;
		*)
			echo -e "${YELLOW}Warning: Ubuntu $ubuntu_ver is not an officially supported version (22.04/24.04/26.04).${NC}"
			if [ "$ASSUME_YES" != 'yes' ]; then
				read -r -p "Continue anyway? [y/N] " reply
				[[ "$reply" =~ ^[Yy]$ ]] || exit 1
			fi
			;;
	esac
fi

echo "[ * ] Operating system: $os $release ($codename)"

case $architecture in
	x86_64)
		ARCH="amd64"
		;;
	aarch64)
		ARCH="arm64"
		;;
	*)
		echo -e "${RED}Error: unsupported architecture: $architecture${NC}"
		echo "  Supported: x86_64/amd64 and aarch64/arm64"
		exit 1
		;;
esac

# Port conflict check - panel port
echo -e "\n[ * ] Checking port conflicts..."
if port_in_use 8083; then
	echo -e "${YELLOW}Warning: Port 8083 is already in use.${NC}"
	echo "  Hestia-Mini will use a different port for the panel."
	port=$(find_free_port 8084 8085 8086 8087 8088 8089 8090)
	if [ -z "$port" ]; then
		echo -e "${RED}Error: Could not find an available port for the panel.${NC}"
		exit 1
	fi
	echo "  Using port $port for Hestia-Mini."
else
	port=8083
fi

# Port conflict check - reverse proxy port (phpMyAdmin/phpPgAdmin)
if port_in_use "$PROXY_PORT"; then
	echo -e "${YELLOW}Warning: Port $PROXY_PORT (reverse proxy) is already in use.${NC}"
	alt_port=$(find_free_port 8091 8092 8093 8094 8095)
	if [ -z "$alt_port" ]; then
		echo -e "${RED}Error: Could not find an available port for the reverse proxy.${NC}"
		exit 1
	fi
	echo "  Using port $alt_port for the reverse proxy instead."
	PROXY_PORT="$alt_port"
else
	echo "  Reverse proxy will use port $PROXY_PORT."
fi

# Port conflict check - phpMyAdmin/phpPgAdmin backend ports
if port_in_use "$PMA_BACKEND_PORT" || port_in_use "$PGA_BACKEND_PORT"; then
	echo -e "${YELLOW}Warning: Backend ports $PMA_BACKEND_PORT/$PGA_BACKEND_PORT are in use.${NC}"
	echo "  These are internal-only (bound to 127.0.0.1) but must still be free."
	exit 1
fi

# Check for existing MTA on port 25
if port_in_use 25; then
	echo -e "\n${YELLOW}Warning: Something is already listening on port 25.${NC}"
	echo "  This conflicts with Exim and must be resolved before mail will work."
	stub_pkg=""
	if dpkg -l 2>/dev/null | grep -qE '^ii\s+postfix\s'; then
		stub_pkg="postfix"
	elif dpkg -l 2>/dev/null | grep -qE '^ii\s+sendmail\s'; then
		stub_pkg="sendmail"
	fi
	do_purge='no'
	if [ "$PURGE_STUB_MTA" = 'yes' ]; then
		do_purge='yes'
	elif [ "$PURGE_STUB_MTA" = 'ask' ] && [ "$ASSUME_YES" != 'yes' ]; then
		if [ -n "$stub_pkg" ]; then
			read -r -p "  Purge $stub_pkg now so Exim can bind port 25? [y/N] " reply
		else
			read -r -p "  Attempt to stop whatever is listening on port 25 now? [y/N] " reply
		fi
		[[ "$reply" =~ ^[Yy]$ ]] && do_purge='yes'
	elif [ "$PURGE_STUB_MTA" = 'ask' ] && [ "$ASSUME_YES" = 'yes' ]; then
		# Non-interactive default: do not purge automatically unless asked
		do_purge='no'
	fi
	if [ "$do_purge" = 'yes' ]; then
		if [ -n "$stub_pkg" ]; then
			echo "  Purging $stub_pkg..."
			systemctl stop "$stub_pkg" > /dev/null 2>&1
			apt-get -y purge "$stub_pkg" >> $LOG 2>&1
			warn_only $? "Failed to purge $stub_pkg, please remove it manually before continuing"
		else
			pid_on_25=$(ss -tlnp 2>/dev/null | awk '/:25 /{print $NF}' | grep -oP 'pid=\K[0-9]+' | head -n1)
			if [ -n "$pid_on_25" ]; then
				proc_name=$(ps -p "$pid_on_25" -o comm= 2>/dev/null)
				echo "  Stopping process on port 25 (pid $pid_on_25, $proc_name)..."
				systemctl stop "$proc_name" > /dev/null 2>&1
			fi
		fi
	else
		echo "  Continuing without purging; mail delivery will not work until port 25 is freed."
	fi
fi

# Check for existing MySQL/MariaDB
if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
	echo -e "\n${YELLOW}Warning: MySQL/MariaDB is already running.${NC}"
	if [ "$ASSUME_YES" != 'yes' ]; then
		echo "  MiniPanel normally installs its own MariaDB instance."
		read -r -p "  Reuse the existing instance instead of installing a new one? [y/N] " reply
		if [[ "$reply" =~ ^[Yy]$ ]]; then
			software=$(echo "$software" | sed -E 's/\bmariadb-server\b//')
			echo "  Will reuse the existing database server; skipping mariadb-server install."
		else
			echo "  Proceeding to install MiniPanel's own MariaDB alongside the existing one."
			echo "  NOTE: this may fail if the existing instance already holds port 3306."
		fi
	else
		echo "  --yes specified: attempting to reuse the existing instance."
		software=$(echo "$software" | sed -E 's/\bmariadb-server\b//')
	fi
fi

# Check for existing PostgreSQL
if systemctl is-active --quiet postgresql; then
	echo -e "\n${YELLOW}Warning: PostgreSQL is already running.${NC}"
	echo "  MiniPanel will reuse the existing instance rather than installing a second one."
	software=$(echo "$software" | sed -E 's/\bpostgresql\b//; s/\bpostgresql-contrib\b//')
fi

#----------------------------------------------------------#
#                    Install software                       #
#----------------------------------------------------------#

# Generate locales to suppress locale warnings during apt install
sed -i "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen 2>/dev/null
sed -i "s/# en_IN.UTF-8 UTF-8/en_IN.UTF-8 UTF-8/g" /etc/locale.gen 2>/dev/null
locale-gen > /dev/null 2>&1

# Let exim4-config create and own its initial configuration. Pre-creating
# /etc/exim4 files before its post-install script runs can leave dpkg unable to
# configure the Exim package chain.
if [ ! -f /etc/mailname ]; then
	(hostname -f 2>/dev/null || hostname) > /etc/mailname
fi
if command -v debconf-set-selections > /dev/null 2>&1; then
	echo "exim4-config exim4/dc_eximconfig_configtype select internet site; mail is sent and received directly using SMTP" | debconf-set-selections
	echo "exim4-config exim4/mailname string $(cat /etc/mailname)" | debconf-set-selections
	echo "exim4-config exim4/no_config boolean false" | debconf-set-selections
	echo "exim4-config exim4/use_split_config boolean false" | debconf-set-selections
	check_result $? "Failed to preseed Exim package configuration"
fi

# A partially configured package database must be repaired before installing
# Mini. Do not hide this failure: its output is required to diagnose the host.
dpkg --configure -a >> "$LOG" 2>&1
check_result $? "Failed to configure existing packages. Check details in: $LOG"
apt-get -f install -y >> "$LOG" 2>&1
check_result $? "Failed to repair package dependencies. Check details in: $LOG"

# Disable daemon autostart during apt-get install (matches original HestiaCP)
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod a+x /usr/sbin/policy-rc.d

# Clean up any leftover hestia repo list before initial dependency check
rm -f /etc/apt/sources.list.d/hestia.list /etc/apt/sources.list.d/hestia.list.tmp

if [ "$release" -lt 12 ]; then
	software=$(echo "$software" | sed -e "s/spamd/spamassassin/g")
fi

echo -e "\n[ * ] Installing installer dependencies..."
apt-get -qq update >> "$LOG" 2>&1
apt-get -y install $installer_dependencies >> "$LOG" 2>&1
check_result $? "Failed to install installer dependencies"

# Add PHP (Ondřej Surý) and Hestia repositories
echo -e "\n[ * ] Adding PHP and Hestia repositories..."
mkdir -p /usr/share/keyrings /etc/apt/sources.list.d

if install_sury_key; then
	echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/sury-keyring.gpg] https://packages.sury.org/php/ $codename main" > /etc/apt/sources.list.d/php.list
fi

if ! install_hestia_key; then
	check_result 1 "Failed to install the Hestia repository key."
fi

echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/hestia-keyring.gpg] https://$RHOST/ $codename main" > /etc/apt/sources.list.d/hestia.list

if ! install_node_key; then
	check_result 1 "Failed to install the NodeSource repository key."
fi
echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/nodejs.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodejs.list

apt-get -qq update >> "$LOG" 2>&1
check_result $? "Failed to update package index after adding repositories."

# Install Hestia-Mini software in background with animated spinner (matches original HestiaCP)
echo -e "\n[ * ] Installing Hestia-Mini software packages..."
echo "  NOTE: This process may take 5 to 15 minutes. Please wait..."

if [ "$PGSQL_ENABLE" = 'yes' ]; then
	software="$software postgresql postgresql-contrib php${fpm_v}-pgsql"
fi

apt-get -y install $software >> "$LOG" 2>&1 &
BACK_PID=$!

spin_i=1
while kill -0 $BACK_PID > /dev/null 2>&1; do
	printf " [%c]  " "${spinner:spin_i++%${#spinner}:1}"
	sleep 0.5
	printf "\b\b\b\b\b\b"
done
echo -ne '\b\b\b\b\b\b'

wait $BACK_PID
check_result $? "Failed to install required software packages. Check details in: $LOG"

# Restore service autostart policy
rm -f /usr/sbin/policy-rc.d

#----------------------------------------------------------#
#                 Configure Hestia base                     #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring MiniPanel base..."

# System users needed by kept bin/func scripts (mirrors upstream Hestia)
if ! getent group hestia-users > /dev/null 2>&1; then
	groupadd hestia-users 2>> $LOG
fi
if ! id "hestiamail" > /dev/null 2>&1; then
	useradd "hestiamail" -c "MiniPanel mail/db service account" --no-create-home 2>> $LOG
	adduser hestiamail hestia-users > /dev/null 2>&1
fi
if ! id "hestiaweb" > /dev/null 2>&1; then
	useradd -r -s /bin/false -d $HESTIA hestiaweb 2>> $LOG
fi

# Create Hestia directories
mkdir -p $HESTIA/{bin,func,data/{users,packages,queue},ssl,ssl/mail,conf,install,log,web}
mkdir -p $HESTIA/data/sessions
chown hestiaweb:hestiaweb $HESTIA/data/sessions

# Copy install/ resources (needed at runtime by bin/func scripts and by
# this installer itself for exim/dovecot/phpmyadmin/phppgadmin/filemanager
# templates). Prefer the minipanel source tree, then the base hestia package
# installed by apt, then a sibling checkout of the upstream hestiacp repo.
echo "[ * ] Staging install resources..."
if [ -d "$MINIPANEL_SRC/install/deb" ]; then
	cp -rf "$MINIPANEL_SRC/install/deb" "$HESTIA/install/" 2>> $LOG
fi
if [ -d "$MINIPANEL_SRC/install/common" ]; then
	cp -rf "$MINIPANEL_SRC/install/common" "$HESTIA/install/" 2>> $LOG
fi
if [ ! -d "$HESTIA/install/deb/exim" ] || [ ! -d "$HESTIA/install/common/dovecot" ]; then
	UPSTREAM_HESTIA_SRC="$(cd "$MINIPANEL_SRC/.." 2> /dev/null && pwd)"
	if [ -d "$UPSTREAM_HESTIA_SRC/install/deb" ]; then
		echo "  Using upstream hestiacp install resources from $UPSTREAM_HESTIA_SRC"
		cp -rf "$UPSTREAM_HESTIA_SRC/install/deb" "$HESTIA/install/" 2>> $LOG
		cp -rf "$UPSTREAM_HESTIA_SRC/install/common" "$HESTIA/install/" 2>> $LOG
	else
		echo -e "${RED}Error: could not find install/deb + install/common resources.${NC}"
		echo "  Expected at $MINIPANEL_SRC/install/ or a sibling hestiacp checkout."
		exit 1
	fi
fi
mkdir -p "$HESTIA/install/upgrade"
if [ -f "$MINIPANEL_SRC/install/upgrade/upgrade.conf" ]; then
	cp -f "$MINIPANEL_SRC/install/upgrade/upgrade.conf" "$HESTIA/install/upgrade/" 2>> $LOG
elif [ -n "${UPSTREAM_HESTIA_SRC:-}" ] && [ -f "$UPSTREAM_HESTIA_SRC/install/upgrade/upgrade.conf" ]; then
	cp -f "$UPSTREAM_HESTIA_SRC/install/upgrade/upgrade.conf" "$HESTIA/install/upgrade/" 2>> $LOG
fi

# Copy bin/ scripts from the minipanel source tree (this is the trimmed set)
cp -f "$MINIPANEL_SRC/bin/"* $HESTIA/bin/ 2>> $LOG
check_result $? "Failed to copy bin/ scripts from $MINIPANEL_SRC/bin"
chmod 755 $HESTIA/bin/*

# Copy func/ libraries
cp -rf "$MINIPANEL_SRC/func/"* $HESTIA/func/ 2>> $LOG
check_result $? "Failed to copy func/ libraries from $MINIPANEL_SRC/func"
mkdir -p $HESTIA/func/internal
cp -rf "$MINIPANEL_SRC/func/internal/"* $HESTIA/func/internal/ 2>> $LOG

# Copy web/ UI
cp -rf "$MINIPANEL_SRC/web/"* $HESTIA/web/ 2>> $LOG
check_result $? "Failed to copy web/ UI from $MINIPANEL_SRC/web"

# Copy default data packages, templates, firewall, and api definitions into $HESTIA/data/
if [ -d "$HESTIA/install/common/packages" ]; then
	cp -rf "$HESTIA/install/common/packages" "$HESTIA/data/" 2>> $LOG
fi
if [ -d "$HESTIA/install/deb/templates" ]; then
	cp -rf "$HESTIA/install/deb/templates" "$HESTIA/data/" 2>> $LOG
fi
if [ -d "$HESTIA/install/common/templates" ]; then
	mkdir -p "$HESTIA/data/templates"
	cp -rf "$HESTIA/install/common/templates/"* "$HESTIA/data/templates/" 2>> $LOG
fi
if [ -d "$HESTIA/install/common/firewall" ]; then
	cp -rf "$HESTIA/install/common/firewall" "$HESTIA/data/" 2>> $LOG
fi
if [ -d "$HESTIA/install/common/api" ]; then
	cp -rf "$HESTIA/install/common/api" "$HESTIA/data/" 2>> $LOG
fi

# Keep the upstream bootstrap config path. The inherited bin/func scripts
# source /etc/hestiacp/hestia.conf first, then read $HESTIA/conf/hestia.conf.
mkdir -p /etc/hestiacp
cat > /etc/hestiacp/hestia.conf << EOF
# Do not edit this file, it can be overwritten on upgrade.
export HESTIA='$HESTIA'
[[ -f /etc/hestiacp/local.conf ]] && source /etc/hestiacp/local.conf
EOF

# Create hestia.conf and a backward-compatible minipanel.conf symlink
echo -e "\n[ * ] Creating configuration..."
if [ -z "$ADMIN_EMAIL" ]; then
	ADMIN_EMAIL="admin@$(hostname -f 2> /dev/null || hostname)"
fi
rm -f "$HESTIA/conf/minipanel.conf"
cat > $HESTIA/conf/hestia.conf << EOF
MAIL_SYSTEM='exim'
ANTIVIRUS_SYSTEM='clamav-daemon'
ANTISPAM_SYSTEM='$([ "$release" -lt 12 ] && echo 'spamassassin' || echo 'spamd')'
IMAP_SYSTEM='dovecot'
DB_SYSTEM='mysql$([ "$PGSQL_ENABLE" = 'yes' ] && echo ',pgsql')'
DB_PGSQL_SYSTEM='$([ "$PGSQL_ENABLE" = 'yes' ] && echo 'pgsql')'
DB_PMA_ALIAS='phpmyadmin'
DB_PGA_ALIAS='phppgadmin'
FILE_MANAGER='$([ "$FM_INSTALL" = 'yes' ] && echo 'true' || echo 'false')'
API='yes'
LANGUAGE='en'
THEME='default'
BACKEND_PORT='$port'
PROXY_PORT='$PROXY_PORT'
ROOT_USER='admin'
HOSTNAME='$(hostname -f 2> /dev/null || hostname)'
HESTIA_VERSION='$MINIPANEL_VERSION'
MINIPANEL_VERSION='$MINIPANEL_VERSION'
API_SYSTEM='1'
API_ALLOWED_IP='allow-all'
POLICY_SYSTEM_HIDE_ADMIN='no'
POLICY_SYSTEM_PROTECTED_ADMIN='no'
POLICY_USER_VIEW_SUSPENDED='no'
POLICY_USER_CHANGE_THEME='yes'
INACTIVE_SESSION_TIMEOUT='60'
DEBUG_MODE='false'
RELEASE_BRANCH='release'
DISABLE_IP_CHECK='no'
DEFAULT_THEME='default'
HIDE_DOCS='no'
USE_SERVER_SMTP='false'
SERVER_SMTP_HOST=''
SERVER_SMTP_PORT='465'
SERVER_SMTP_USER=''
SERVER_SMTP_PASSWD=''
SERVER_SMTP_SECURITY='ssl'
WEB_TERMINAL='true'
WEB_TERMINAL_PORT='8085'
EOF
ln -sf "$HESTIA/conf/hestia.conf" "$HESTIA/conf/minipanel.conf"

#----------------------------------------------------------#
#                Configure Mail Services                    #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring Exim (mail transfer agent)..."
gpasswd -a Debian-exim mail > /dev/null 2>&1
if [ -d "$HESTIA_INSTALL_DIR/exim" ]; then
	mkdir -p /etc/exim4/domains /etc/exim4/domains_debug
	cp -f "$HESTIA_INSTALL_DIR/exim/exim4.conf.template" /etc/exim4/exim4.conf.template 2>> "$LOG"
	cp -f "$HESTIA_INSTALL_DIR/exim/dnsbl.conf" /etc/exim4/dnsbl.conf 2>> "$LOG"
	cp -f "$HESTIA_INSTALL_DIR/exim/spam-blocks.conf" /etc/exim4/spam-blocks.conf 2>> "$LOG"
	cp -f "$HESTIA_INSTALL_DIR/exim/limit.conf" /etc/exim4/limit.conf 2>> "$LOG"
	cp -f "$HESTIA_INSTALL_DIR/exim/system.filter" /etc/exim4/system.filter 2>> "$LOG"
	touch /etc/exim4/white-blocks.conf
	update-exim4.conf >> "$LOG" 2>&1
	check_result $? "Failed to generate the Exim configuration. Check details in: $LOG"
	exim4 -bP >> "$LOG" 2>&1
	check_result $? "Exim configuration validation failed. Check details in: $LOG"
fi

echo -e "\n[ * ] Configuring Dovecot (IMAP/POP3)..."
gpasswd -a dovecot mail > /dev/null 2>&1
mkdir -p /etc/dovecot/conf.d/domains
dovecot_version="$(dovecot --version 2> /dev/null | cut -f -2 -d .)"
if [ "$dovecot_version" = "2.4" ]; then
	[ -d "$HESTIA_COMMON_DIR/dovecot/2.4" ] || check_result 1 "Dovecot 2.4 templates are missing"
	cp -f "$HESTIA_COMMON_DIR/dovecot/2.4/dovecot.conf" /etc/dovecot/ 2>> "$LOG"
	cp -f "$HESTIA_COMMON_DIR/dovecot/2.4/conf.d/"* /etc/dovecot/conf.d/ 2>> "$LOG"
else
	[ -d "$HESTIA_COMMON_DIR/dovecot/2.3" ] || check_result 1 "Dovecot 2.3 templates are missing"
	cp -f "$HESTIA_COMMON_DIR/dovecot/2.3/dovecot.conf" /etc/dovecot/ 2>> "$LOG"
	cp -f "$HESTIA_COMMON_DIR/dovecot/2.3/conf.d/"* /etc/dovecot/conf.d/ 2>> "$LOG"
	rm -f /etc/dovecot/conf.d/15-mailboxes.conf
fi
chown -R root:root /etc/dovecot* 2>> "$LOG"
touch /var/log/dovecot.log
chown dovecot:mail /var/log/dovecot.log
chmod 660 /var/log/dovecot.log

echo -e "\n[ * ] Configuring ClamAV (antivirus)..."
systemctl enable clamav-daemon 2>/dev/null
freshclam > /dev/null 2>&1 &

echo -e "\n[ * ] Configuring SpamAssassin (antispam)..."
if [ "$release" -lt 12 ]; then
	systemctl enable spamassassin 2>/dev/null
else
	systemctl enable spamd 2>/dev/null
fi

#----------------------------------------------------------#
#               Configure Database Services                 #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring MariaDB..."
systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null
systemctl start mysql 2>/dev/null || systemctl start mariadb 2>/dev/null

if [ "$PGSQL_ENABLE" = 'yes' ]; then
	echo -e "\n[ * ] Configuring PostgreSQL..."
	systemctl enable postgresql 2>/dev/null
	systemctl start postgresql 2>/dev/null
	check_result $? "Failed to start PostgreSQL"
else
	echo -e "\n[ * ] Skipping PostgreSQL (disabled via --no-pgsql)."
fi

#----------------------------------------------------------#
#            Configure PHP-FPM pool (panel utilities:       #
#            phpMyAdmin / phpPgAdmin / File Manager)        #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring PHP-FPM pool for phpMyAdmin/phpPgAdmin..."
mkdir -p /etc/php/${fpm_v}/fpm/pool.d
if [ -f "$HESTIA_INSTALL_DIR/php-fpm/www.conf" ]; then
	cp -f "$HESTIA_INSTALL_DIR/php-fpm/www.conf" /etc/php/${fpm_v}/fpm/pool.d/www.conf 2>> $LOG
else
	cat > /etc/php/${fpm_v}/fpm/pool.d/www.conf << PHPFPM
[www]
listen = /run/php/www.sock
listen.owner = hestiamail
listen.group = www-data
listen.mode = 0660
user = hestiamail
group = hestiamail
pm = ondemand
pm.max_children = 4
pm.max_requests = 4000
pm.process_idle_timeout = 10s
PHPFPM
fi
systemctl enable php${fpm_v}-fpm 2>/dev/null
systemctl restart php${fpm_v}-fpm 2>/dev/null
check_result $? "Failed to start php${fpm_v}-fpm"

#----------------------------------------------------------#
#                 Configure phpMyAdmin                      #
#----------------------------------------------------------#

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

#----------------------------------------------------------#
#                 Configure phpPgAdmin                      #
#----------------------------------------------------------#

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

#----------------------------------------------------------#
#                  Configure Nginx                          #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring Nginx (reverse proxy for DB web UIs)..."

cat > /etc/nginx/conf.d/minipanel.conf << NGINX
server {
    listen $PROXY_PORT;
    server_name _;

    location /phpmyadmin {
        alias /usr/share/phpmyadmin/;
        index index.php;

        location ~ /(libraries|setup|templates|locale) {
            deny all;
            return 404;
        }

        location ~ ^/phpmyadmin/(.*\.php)\$ {
            alias /usr/share/phpmyadmin/\$1;
            include fastcgi_params;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_pass unix:/run/php/www.sock;
        }
    }

    location /phppgadmin {
        alias /usr/share/phppgadmin/;
        index index.php;

        location ~ ^/phppgadmin/(.*\.php)\$ {
            alias /usr/share/phppgadmin/\$1;
            include fastcgi_params;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_pass unix:/run/php/www.sock;
        }
    }
}
NGINX

nginx -t >> $LOG 2>&1
check_result $? "Nginx configuration test failed - check $LOG"

#----------------------------------------------------------#
#               Configure Sudoers                          #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring sudoers..."
cat > /etc/sudoers.d/hestiaweb << 'SUDOERS'
Defaults:root !requiretty
# MiniPanel: sudo limited to hestia scripts
hestiaweb   ALL=NOPASSWD:/usr/local/hestia/bin/*
SUDOERS

chmod 440 /etc/sudoers.d/hestiaweb

#----------------------------------------------------------#
#                  Configure Cron                           #
#----------------------------------------------------------#

echo -e "\n[ * ] Setting up cron jobs..."
mkdir -p /var/spool/cron/crontabs
rm -f /var/spool/cron/crontabs/hestiaweb

cat > /var/spool/cron/crontabs/hestiaweb << CRON
MAILTO=""
CONTENT_TYPE="text/plain; charset=utf-8"
*/2 * * * * sudo /usr/local/hestia/bin/v-update-sys-queue restart
10 00 * * * sudo /usr/local/hestia/bin/v-update-sys-queue daily
15 02 * * * sudo /usr/local/hestia/bin/v-update-sys-queue disk
10 00 * * * sudo /usr/local/hestia/bin/v-update-sys-queue traffic
CRON

chmod 600 /var/spool/cron/crontabs/hestiaweb
chown hestiaweb:hestiaweb /var/spool/cron/crontabs/hestiaweb

#----------------------------------------------------------#
#               Generate SSL Certificate                    #
#----------------------------------------------------------#

echo -e "\n[ * ] Generating self-signed SSL certificate..."
ssl_bundle=$(mktemp)
$HESTIA/bin/v-generate-ssl-cert "$(hostname -f 2>/dev/null || hostname)" "$ADMIN_EMAIL" 'US' 'California' 'San Francisco' 'Hestia Control Panel' 'IT' > "$ssl_bundle" 2>> "$LOG"
check_result $? "Failed to generate the default SSL certificate"

crt_end=$(grep -n "END CERTIFICATE-" "$ssl_bundle" | head -n1 | cut -f1 -d:)
key_start=$(grep -nE "BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY" "$ssl_bundle" | head -n1 | cut -f1 -d:)
key_end=$(grep -nE "END (RSA |EC |ENCRYPTED )?PRIVATE KEY" "$ssl_bundle" | head -n1 | cut -f1 -d:)
if [ -z "$crt_end" ] || [ -z "$key_start" ] || [ -z "$key_end" ]; then
	rm -f "$ssl_bundle"
	check_result 1 "Failed to parse the generated SSL certificate"
fi

mkdir -p "$HESTIA/ssl"
sed -n "1,${crt_end}p" "$ssl_bundle" > "$HESTIA/ssl/certificate.crt"
sed -n "${key_start},${key_end}p" "$ssl_bundle" > "$HESTIA/ssl/certificate.key"
openssl x509 -noout -in "$HESTIA/ssl/certificate.crt" >> "$LOG" 2>&1
check_result $? "Generated SSL certificate is invalid"
openssl pkey -noout -in "$HESTIA/ssl/certificate.key" >> "$LOG" 2>&1
check_result $? "Generated SSL private key is invalid"
chown root:mail "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
chmod 660 "$HESTIA/ssl/certificate.crt" "$HESTIA/ssl/certificate.key"
rm -f "$ssl_bundle"

[ -f "$HESTIA_INSTALL_DIR/ssl/dhparam.pem" ] || check_result 1 "Dovecot DH parameters are missing"
install -o root -g root -m 644 "$HESTIA_INSTALL_DIR/ssl/dhparam.pem" /etc/ssl/dhparam.pem
check_result $? "Failed to install Dovecot DH parameters"
#----------------------------------------------------------#
#                Create admin user                          #
#----------------------------------------------------------#

echo -e "\n[ * ] Creating admin user..."
if [ -z "$ADMIN_PASSWORD" ]; then
	adminpass=$(gen_pass '8' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')$(gen_pass '4' 'abcdefghijklmnopqrstuvwxyz')$(gen_pass '4' '0123456789')
else
	adminpass="$ADMIN_PASSWORD"
fi

if [ -e "$HESTIA/data/users/admin" ]; then
	echo "  Admin user already exists, skipping creation."
else
	$HESTIA/bin/v-add-user admin "$adminpass" "$ADMIN_EMAIL" default Admin >> $LOG 2>&1
	check_result $? "Failed to create admin user - check $LOG"
	$HESTIA/bin/v-change-user-role admin admin >> $LOG 2>&1
	warn_only $? "Failed to grant admin role - run manually: v-change-user-role admin admin"
fi

#----------------------------------------------------------#
#                Set default values                         #
#----------------------------------------------------------#

echo -e "\n[ * ] Setting default configuration values..."
BIN="$HESTIA/bin"
export HESTIA BIN
if [ -f "$HESTIA/func/syshealth.sh" ]; then
	source $HESTIA/func/syshealth.sh
	syshealth_repair_system_config 2>/dev/null
fi

# Set backend port
$HESTIA/bin/v-change-sys-port $port > /dev/null 2>&1

# Update defaults
$HESTIA/bin/v-update-sys-defaults > /dev/null 2>&1

#----------------------------------------------------------#
#                Install File Manager                       #
#----------------------------------------------------------#

if [ "$FM_INSTALL" = 'yes' ]; then
	echo -e "\n[ * ] Installing File Manager..."
	export HOMEDIR='/home'
	export APP_NAME='Hestia-Mini'
	if [ ! -d "/home/admin" ]; then
		mkdir -p /home/admin/.composer /home/admin/.config
	fi
	$HESTIA/bin/v-add-sys-filemanager quiet >> $LOG 2>&1
	warn_only $? "File Manager installation failed - re-run manually with: /usr/local/hestia/bin/v-add-sys-filemanager"
else
	echo -e "\n[ * ] Skipping File Manager install (disabled via --no-filemanager)."
fi

#----------------------------------------------------------#
#                  Enable Services                          #
#----------------------------------------------------------#

echo -e "\n[ * ] Starting services..."

systemctl enable exim4 2>/dev/null
systemctl start exim4 >> "$LOG" 2>&1
check_result $? "Failed to start Exim"

systemctl enable dovecot 2>/dev/null
doveconf -n >> "$LOG" 2>&1
check_result $? "Dovecot configuration validation failed - check $LOG"
systemctl start dovecot >> "$LOG" 2>&1
check_result $? "Failed to start Dovecot"

systemctl enable nginx 2>/dev/null
systemctl restart nginx 2>/dev/null
check_result $? "Failed to start Nginx"

systemctl daemon-reload > /dev/null 2>&1
systemctl enable hestia-web-terminal > /dev/null 2>&1
systemctl restart hestia-web-terminal > /dev/null 2>&1
warn_only $? "Could not (re)start the web terminal service - check manually with 'systemctl status hestia-web-terminal'"

systemctl enable hestia 2>/dev/null
systemctl restart hestia 2>/dev/null
warn_only $? "Could not (re)start the hestia panel service - check manually with 'systemctl status hestia'"

echo -e "\n====================================================="
echo -e "  Hestia-Mini has been installed successfully!"
echo -e "\n"
echo -e "  Admin URL:  https://$(hostname):$port"
echo -e "  Username:   admin"
echo -e "  Password:   $adminpass"
echo -e "\n"
echo -e "  Database web UIs (reverse-proxied on port $PROXY_PORT):"
echo -e "    - phpMyAdmin:  http://$(hostname):$PROXY_PORT/phpmyadmin/"
if [ "$PGSQL_ENABLE" = 'yes' ] && [ "$PGA_INSTALL" = 'yes' ]; then
	echo -e "    - phpPgAdmin:  http://$(hostname):$PROXY_PORT/phppgadmin/"
fi
echo -e "\n"
echo -e "  Features enabled:"
echo -e "    - Mail (Exim + Dovecot + ClamAV + SpamAssassin)"
echo -e "    - Database (MySQL/MariaDB$([ "$PGSQL_ENABLE" = 'yes' ] && echo ' + PostgreSQL') + phpMyAdmin$([ "$PGA_INSTALL" = 'yes' ] && [ "$PGSQL_ENABLE" = 'yes' ] && echo ' + phpPgAdmin'))"
if [ "$FM_INSTALL" = 'yes' ]; then
	echo -e "    - File Manager"
fi
echo -e "\n"
echo -e "  Please change the admin password after first login."
echo -e "  See docs/INSTALL.md for DNS/mail-deliverability setup (SPF/DKIM/PTR)."
echo -e "====================================================="
echo -e "\n"

# Sort config
sort_config_file 2>/dev/null

echo "[ ! ] IMPORTANT: You must restart the system before continuing!"
