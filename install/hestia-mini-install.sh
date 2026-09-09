#!/bin/bash

# ======================================================== #
#
# Hestia-Mini Installer
# A stripped-down admin panel derived from HestiaCP
# Supports: Mail, Domain Management (Reverse Proxy/Load Balancing), File Management
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
# Ubuntu can expose a Debian compatibility value (for example "trixie/sid")
# in /etc/debian_version. Use /etc/os-release for Ubuntu and reserve that file
# for deriving the Debian major release only.
. /etc/os-release
os="${ID,,}"
case "$os" in
	ubuntu)
		release="$VERSION_ID"
		codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
		;;
	debian)
		release=$(grep -o "[0-9]\\{1,2\\}" /etc/debian_version | head -n1)
		codename="${VERSION_CODENAME:-}"
		;;
	*)
		release=''
		codename=''
		;;
esac
VERSION="$os"
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

# Supported PHP version (also used for panel PHP-FPM pool)
fpm_v="8.2"
# File Manager (Filegator) version
fm_v="7.15.1"

# Defining software pack - minimal: mail + file manager (no database)
software="acl apt-transport-https ca-certificates clamav-daemon cron curl dnsutils dovecot-imapd
  dovecot-managesieved dovecot-pop3d dovecot-sieve exim4 exim4-daemon-heavy expect
  git hestia=${HESTIA_INSTALL_BUILD} hestia-nginx hestia-php hestia-web-terminal jq libmail-dkim-perl lsb-release
  mc net-tools nodejs
  nginx php${fpm_v} php${fpm_v}-apcu php${fpm_v}-bcmath php${fpm_v}-bz2 php${fpm_v}-cgi
  php${fpm_v}-cli php${fpm_v}-common php${fpm_v}-curl php${fpm_v}-gd php${fpm_v}-imagick
  php${fpm_v}-imap php${fpm_v}-intl php${fpm_v}-ldap php${fpm_v}-mbstring
  php${fpm_v}-pspell php${fpm_v}-readline
  php${fpm_v}-xml php${fpm_v}-zip php${fpm_v}-sqlite3 php${fpm_v}-fpm sqlite3 spamd unrar-free
  unzip util-linux vim-common xxd whois zip zstd restic composer"

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
FM_INSTALL='yes'
ADMIN_EMAIL=''
ADMIN_PASSWORD=''
PANEL_DOMAIN=''
POLICY_RC_D_BACKUP=''
POLICY_RC_D_ACTIVE='no'

cleanup_policy_rc_d() {
	if [ "$POLICY_RC_D_ACTIVE" != 'yes' ]; then
		return
	fi

	if [ -n "$POLICY_RC_D_BACKUP" ] && [ -f "$POLICY_RC_D_BACKUP" ]; then
		mv -f "$POLICY_RC_D_BACKUP" /usr/sbin/policy-rc.d
	else
		rm -f /usr/sbin/policy-rc.d
	fi
	POLICY_RC_D_ACTIVE='no'
}

trap cleanup_policy_rc_d EXIT

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
		--panel-domain)
			PANEL_DOMAIN="$2"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [options]"
			echo "  --yes, -y             Non-interactive: assume yes to all prompts"
			echo "  --purge-mta           Automatically purge a conflicting stub MTA on port 25"
			echo "  --no-purge-mta        Never purge, just warn"
			echo "  --no-filemanager      Skip installing the File Manager"
			echo "  --admin-email EMAIL   Admin contact email (default: admin@<hostname>)"
			echo "  --admin-password PASS Admin password (default: randomly generated)"
			echo "  --panel-domain DOMAIN Panel domain for Let's Encrypt SSL (e.g. panel.example.com)"
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
	echo "  Using port $port for Hestia-Mini panel."
else
	port=8083
	echo "  Hestia-Mini panel will use port $port."
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

#----------------------------------------------------------#
#                    Install software                       #
#----------------------------------------------------------#

# Generate locales to suppress locale warnings during apt install
sed -i "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen 2>/dev/null
sed -i "s/# en_IN.UTF-8 UTF-8/en_IN.UTF-8 UTF-8/g" /etc/locale.gen 2>/dev/null
locale-gen > /dev/null 2>&1

# Let exim4-config create and own its initial configuration. Older Mini
# installers wrote an incomplete package-owned file before exim4-config ran.
# Migrate only that exact legacy signature, keeping a dated recovery copy.
legacy_exim_config='/etc/exim4/update-exim4.conf.conf'
if [ -f "$legacy_exim_config" ] &&
	grep -Fqx "dc_eximconfig_configtype='internet'" "$legacy_exim_config" &&
	grep -Fqx "dc_local_interfaces='127.0.0.1 ; ::1'" "$legacy_exim_config" &&
	! grep -Fq 'dc_use_split_config=' "$legacy_exim_config"; then
	legacy_exim_backup="/root/hestia_mini_legacy_exim4_config-$(date +%d%m%Y%H%M%S).conf"
	cp -a "$legacy_exim_config" "$legacy_exim_backup"
	check_result $? "Failed to back up legacy Exim configuration"
	rm -f "$legacy_exim_config"
	echo "[ ! ] Removed legacy Mini Exim configuration; backup: $legacy_exim_backup"
fi

# A legacy interrupted install can leave exim4-config selected for an unsplit
# configuration but without the template it requires. This template is only a
# recovery bridge for an already-unpacked package; Mini replaces it with the
# Hestia template after the package transaction completes.
if dpkg-query -W -f='${db:Status-Status}' exim4-config 2>/dev/null | grep -Eq 'unpacked|half-configured' &&
	[ ! -f /etc/exim4/exim4.conf.template ]; then
	debian_exim_template='/usr/share/doc/exim4-base/examples/example.conf.gz'
	[ -f "$debian_exim_template" ] || check_result 1 "Missing Debian Exim recovery template: $debian_exim_template"
	mkdir -p /etc/exim4
	zcat "$debian_exim_template" > /etc/exim4/exim4.conf.template
	check_result $? "Failed to restore the Debian Exim recovery template"
	echo "[ ! ] Restored missing Exim template so dpkg can complete configuration"
fi

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

# Disable daemon autostart during apt-get install (matches original HestiaCP).
# Preserve any host policy and restore it if the installation exits early.
if [ -e /usr/sbin/policy-rc.d ]; then
	POLICY_RC_D_BACKUP="/tmp/hestia-mini-policy-rc.d.$$"
	cp -a /usr/sbin/policy-rc.d "$POLICY_RC_D_BACKUP"
	check_result $? "Failed to back up the existing policy-rc.d"
fi
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod a+x /usr/sbin/policy-rc.d
POLICY_RC_D_ACTIVE='yes'

# Clean up package sources owned by a previous Mini installation before the
# dependency update. This also removes an invalid Debian Sury source left by
# older installer versions on Ubuntu.
rm -f /etc/apt/sources.list.d/hestia.list /etc/apt/sources.list.d/hestia.list.tmp \
	/etc/apt/sources.list.d/php.list /etc/apt/sources.list.d/nodejs.list

if [ "$os" = 'debian' ] && [ "$release" -lt 12 ]; then
	software=$(echo "$software" | sed -e "s/spamd/spamassassin/g")
fi

echo -e "\n[ * ] Installing installer dependencies..."
apt-get -qq update >> "$LOG" 2>&1
apt-get -y install $installer_dependencies >> "$LOG" 2>&1
check_result $? "Failed to install installer dependencies"

# Add PHP (Ondřej Surý) and Hestia repositories
echo -e "\n[ * ] Adding PHP and Hestia repositories..."
mkdir -p /usr/share/keyrings /etc/apt/sources.list.d

case "$os" in
	debian)
		if ! install_sury_key; then
			check_result 1 "Failed to install the Sury PHP repository key."
		fi
		echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/sury-keyring.gpg] https://packages.sury.org/php/ $codename main" > /etc/apt/sources.list.d/php.list
		;;
	ubuntu)
		case "$release" in
			22.04 | 24.04)
				# Ubuntu uses the Ondřej PHP PPA; packages.sury.org is Debian-only
				# for these releases. Noble needs this temporary weak-key workaround.
				# software-properties-common (provides add-apt-repository) no longer
				# exists on Debian 13, so install it here on Ubuntu only.
				apt-get -y install software-properties-common >> "$LOG" 2>&1
				if [ "$release" = '24.04' ]; then
					echo 'APT::Key::Assert-Pubkey-Algo "";' > /etc/apt/apt.conf.d/99weakkey-warning
				fi
				add-apt-repository -y ppa:ondrej/php >> "$LOG" 2>&1
				check_result $? "Failed to add the Ondřej PHP repository."
				;;
			*)
				if ! install_sury_key; then
					check_result 1 "Failed to install the Sury PHP repository key."
				fi
				echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/sury-keyring.gpg] https://packages.sury.org/php/ $codename main" > /etc/apt/sources.list.d/php.list
				;;
		esac
		;;
esac

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
install_status=$?
if [ "$install_status" -ne 0 ]; then
	echo -e "\n[ ! ] Package manager diagnostics (last 120 log lines):"
	tail -n 120 "$LOG"
	check_result "$install_status" "Failed to install required software packages. Check details in: $LOG"
fi

# Restore the daemon autostart policy and disable the exit trap after success.
cleanup_policy_rc_d
trap - EXIT

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
if ! getent group hestiaweb > /dev/null 2>&1; then
	groupadd -r hestiaweb 2>> $LOG
fi
if ! id "hestiaweb" > /dev/null 2>&1; then
	useradd -r -g hestiaweb -s /bin/false -d "$HESTIA" hestiaweb 2>> $LOG
fi

# Create log path and symbolic link (mirrors upstream Hestia)
rm -rf /var/log/hestia "$HESTIA/log"
mkdir -p /var/log/hestia
ln -sf /var/log/hestia "$HESTIA/log"

# Create Hestia directories and queue pipes
mkdir -p "$HESTIA"/{bin,func,data/{users,packages,queue,ips},ssl,ssl/mail,conf,conf/defaults,install,web}
mkdir -p "$HESTIA/data/sessions"
touch "$HESTIA/data/queue/backup.pipe" "$HESTIA/data/queue/disk.pipe" \
	"$HESTIA/data/queue/webstats.pipe" "$HESTIA/data/queue/restart.pipe" \
	"$HESTIA/data/queue/traffic.pipe" "$HESTIA/data/queue/daily.pipe"
touch /var/log/hestia/system.log /var/log/hestia/nginx-error.log \
	/var/log/hestia/nginx-access.log /var/log/hestia/auth.log \
	/var/log/hestia/backup.log
chmod 750 "$HESTIA/conf" "$HESTIA/data/users" "$HESTIA/data/ips" /var/log/hestia
chmod -R 750 "$HESTIA/data/queue"
chmod 660 /var/log/hestia/*
chown -R root:hestiaweb /var/log/hestia
chmod 770 "$HESTIA/data/sessions"
chown hestiaweb:hestiaweb "$HESTIA/data/sessions"

if [ -f "$HESTIA_INSTALL_DIR/logrotate/hestia" ]; then
	cp -f "$HESTIA_INSTALL_DIR/logrotate/hestia" /etc/logrotate.d/hestia
fi

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

# Copy web-terminal backend
if [ -d "$MINIPANEL_SRC/src/deb/web-terminal" ]; then
	mkdir -p "$HESTIA/web-terminal"
	cp -rf "$MINIPANEL_SRC/src/deb/web-terminal/"* "$HESTIA/web-terminal/" 2>> $LOG
	check_result $? "Failed to copy web-terminal backend"
	# Install npm dependencies
	echo -e "\n[ * ] Installing web terminal npm dependencies..."
	(cd "$HESTIA/web-terminal" && npm install --production >> "$LOG" 2>&1)
	warn_only $? "Failed to install web terminal npm dependencies"
	# Install systemd service
	if [ -f "$HESTIA/web-terminal/hestia-web-terminal.service" ]; then
		cp -f "$HESTIA/web-terminal/hestia-web-terminal.service" /lib/systemd/system/hestia-web-terminal.service
		systemctl daemon-reload
	fi
fi

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
mkdir -p /etc/hestiacp /etc/profile.d
cat > /etc/hestiacp/hestia.conf << EOF
# Do not edit this file, it can be overwritten on upgrade.
export HESTIA='$HESTIA'
[[ -f /etc/hestiacp/local.conf ]] && source /etc/hestiacp/local.conf
EOF

# The hestia-nginx package's SysV service sources this file before launching
# the private Hestia Nginx and PHP-FPM binaries.
cat > /etc/profile.d/hestia.sh << EOF
export HESTIA='$HESTIA'
PATH=\$PATH:$HESTIA/bin
export PATH
EOF
chmod 755 /etc/profile.d/hestia.sh
source /etc/profile.d/hestia.sh

# Create hestia.conf and a backward-compatible minipanel.conf symlink
echo -e "\n[ * ] Creating configuration..."
if [ -z "$ADMIN_EMAIL" ]; then
	ADMIN_EMAIL="admin@$(hostname -f 2> /dev/null || hostname)"
fi
rm -f "$HESTIA/conf/minipanel.conf"
cat > $HESTIA/conf/hestia.conf << EOF
MAIL_SYSTEM='exim'
ANTIVIRUS_SYSTEM='clamav-daemon'
ANTISPAM_SYSTEM='$([ "$os" = 'debian' ] && [ "$release" -lt 12 ] && echo 'spamassassin' || echo 'spamd')'
IMAP_SYSTEM='dovecot'
# Roundcube webmail (SQLite backend)
WEB_SYSTEM='nginx'
WEB_PORT='80'
WEB_SSL_PORT='443'
WEBMAIL_ALIAS='webmail'
WEBMAIL_SYSTEM='roundcube'
FILE_MANAGER='$([ "$FM_INSTALL" = 'yes' ] && echo 'true' || echo 'false')'
API='yes'
LANGUAGE='en'
THEME='default'
BACKEND_PORT='$port'
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
APP_NAME='Hestia-Mini'
EOF
ln -sf "$HESTIA/conf/hestia.conf" "$HESTIA/conf/minipanel.conf"
mkdir -p "$HESTIA/conf/defaults"
cp -f "$HESTIA/conf/hestia.conf" "$HESTIA/conf/defaults/hestia.conf"

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
if [ "$os" = 'debian' ] && [ "$release" -lt 12 ]; then
	systemctl enable spamassassin 2>/dev/null
else
	systemctl enable spamd 2>/dev/null
fi

#----------------------------------------------------------#
#            Configure PHP-FPM pool (panel + File Manager)   #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring PHP-FPM pool..."
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
#                  Configure Nginx                          #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring Nginx..."

# Ensure domain config directory exists for reverse proxy configurations
mkdir -p /etc/nginx/conf.d/domains
# Nginx templates (webmail etc.) log to per-domain files under this directory;
# it must exist before the first v-add-mail-domain-webmail or nginx -t will fail.
mkdir -p /var/log/nginx/domains

# Create minimal nginx config (domains are added dynamically via v-add-domain)
cat > /etc/nginx/conf.d/minipanel.conf << NGINX
# Hestia-Mini domain configurations are managed via v-add-domain
# and placed in /etc/nginx/conf.d/domains/*.conf
include /etc/nginx/conf.d/domains/*.conf;
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
$HESTIA/bin/v-generate-ssl-cert "$(hostname -f 2>/dev/null || hostname)" "$ADMIN_EMAIL" 'US' 'California' 'San Francisco' 'Hestia-Mini' 'IT' > "$ssl_bundle" 2>> "$LOG"
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
	# The default package intentionally uses nologin for tenant accounts. The
	# initial panel administrator needs an interactive shell for Web Terminal.
	$HESTIA/bin/v-change-user-shell admin bash >> $LOG 2>&1
	check_result $? "Failed to grant the admin user an interactive shell - check $LOG"
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
	source "$HESTIA/func/syshealth.sh"
	syshealth_repair_system_config 2>> "$LOG"
	syshealth_adapt_hestia_nginx_listen_ports 2>> "$LOG"
	syshealth_adapt_nginx_resolver 2>> "$LOG"
fi

# Set backend port
$HESTIA/bin/v-change-sys-port "$port" >> "$LOG" 2>&1
warn_only $? "v-change-sys-port encountered a warning"

# Register system IP address
$HESTIA/bin/v-update-sys-ip >> "$LOG" 2>&1
warn_only $? "v-update-sys-ip encountered a warning"

# Update defaults
$HESTIA/bin/v-update-sys-defaults >> "$LOG" 2>&1
warn_only $? "v-update-sys-defaults encountered a warning"

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
#                Install Roundcube Webmail                 #
#----------------------------------------------------------#

echo -e "\n[ * ] Installing Roundcube Webmail (SQLite)..."
export HOMEDIR='/home'
export HESTIA_COMMON_DIR="$HESTIA/install/common"
$HESTIA/bin/v-add-sys-roundcube >> $LOG 2>&1
warn_only $? "Roundcube installation failed - re-run manually with: /usr/local/hestia/bin/v-add-sys-roundcube"

#----------------------------------------------------------#
#             Configure PHP Dependencies                   #
#----------------------------------------------------------#

echo -e "\n[ * ] Configuring PHP dependencies (Composer)..."
$HESTIA/bin/v-add-sys-dependencies quiet >> $LOG 2>&1
check_result $? "Failed to install Hestia PHP dependencies - check $LOG"

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

# Ensure log directory and files exist with correct permissions before service startup
mkdir -p /var/log/hestia "$HESTIA/data/sessions"
touch /var/log/hestia/nginx-error.log /var/log/hestia/nginx-access.log /var/log/hestia/system.log
chown -R root:hestiaweb /var/log/hestia
chmod 750 /var/log/hestia
chmod 660 /var/log/hestia/*
chown hestiaweb:hestiaweb "$HESTIA/data/sessions"
chmod 770 "$HESTIA/data/sessions"

# Re-run listen ports and resolver adaptation after port configuration
if [ -f "$HESTIA/func/syshealth.sh" ]; then
	source "$HESTIA/func/syshealth.sh"
	syshealth_adapt_hestia_nginx_listen_ports 2>> "$LOG"
	syshealth_adapt_nginx_resolver 2>> "$LOG"
fi

# Ensure /etc/init.d/hestia is executable
if [ -f /etc/init.d/hestia ]; then
	chmod 755 /etc/init.d/hestia
fi

# Clean up any stale sockets/pidfiles
rm -f /run/hestia-nginx.pid /run/hestia-php.pid /run/hestia-php.sock

# Validate panel internal Nginx and PHP-FPM configuration before starting
if [ -x "$HESTIA/nginx/sbin/hestia-nginx" ] && [ -f "$HESTIA/nginx/conf/nginx.conf" ]; then
	"$HESTIA/nginx/sbin/hestia-nginx" -t -c "$HESTIA/nginx/conf/nginx.conf" >> "$LOG" 2>&1
	check_result $? "Hestia panel Nginx configuration test failed - check $LOG"
fi
if [ -x "$HESTIA/php/sbin/hestia-php" ] && [ -f "$HESTIA/php/etc/php-fpm.conf" ]; then
	"$HESTIA/php/sbin/hestia-php" -t -y "$HESTIA/php/etc/php-fpm.conf" >> "$LOG" 2>&1
	check_result $? "Hestia panel PHP-FPM configuration test failed - check $LOG"
fi

systemctl daemon-reload > /dev/null 2>&1
update-rc.d hestia defaults >> "$LOG" 2>&1
check_result $? "Failed to register the Hestia panel service"
systemctl daemon-reload > /dev/null 2>&1
systemctl reset-failed hestia > /dev/null 2>&1 || true

if ! systemctl restart hestia >> "$LOG" 2>&1 && ! systemctl start hestia >> "$LOG" 2>&1; then
	echo "--- systemctl status hestia ---" >> "$LOG" 2>&1
	systemctl status hestia >> "$LOG" 2>&1 || true
	echo "--- journalctl -n 30 -u hestia ---" >> "$LOG" 2>&1
	journalctl -n 30 -u hestia >> "$LOG" 2>&1 || true
	if [ -f /var/log/hestia/nginx-error.log ]; then
		echo "--- /var/log/hestia/nginx-error.log ---" >> "$LOG" 2>&1
		tail -n 30 /var/log/hestia/nginx-error.log >> "$LOG" 2>&1 || true
	fi
	check_result 1 "Failed to start the Hestia panel service - check $LOG"
else
	echo -e "[${GREEN} OK ${NC}]"
fi

#----------------------------------------------------------#
#              Configure Panel SSL (Let's Encrypt)         #
#----------------------------------------------------------#

if [ -f "$SCRIPT_DIR/modules/configure-ssl.sh" ]; then
	source "$SCRIPT_DIR/modules/configure-ssl.sh"
	configure_panel_ssl
fi

echo -e "\n====================================================="
echo -e "  Hestia-Mini has been installed successfully!"
echo -e "\n"
if [ -n "${PANEL_DOMAIN:-}" ]; then
	echo -e "  Admin URL:  https://$PANEL_DOMAIN:$port"
else
	echo -e "  Admin URL:  https://$(hostname):$port"
fi
echo -e "  Username:   admin"
echo -e "  Password:   $adminpass"
echo -e "\n"
echo -e "  Features enabled:"
echo -e "    - Mail (Exim + Dovecot + ClamAV + SpamAssassin)"
echo -e "    - Domain Management (Nginx reverse proxy + load balancing)"
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
