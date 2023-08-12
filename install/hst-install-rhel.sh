#!/bin/bash

# ======================================================== #
#
# Hestia Control Panel Installer for Ubuntu
# https://www.hestiacp.com/
#
# Currently Supported Versions:
# Ubuntu 20.04, 22.04 LTS
#
# ======================================================== #

#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
export PATH=$PATH:/sbin
source /etc/os-release
RHOST='rpm.hestiacp.com'
VERSION=$ID
HESTIA='/usr/local/hestia'
#LOG="tee -a /root/hst_install_backups/hst_install-$(date +%d%m%Y%H%M).log"
LOG='logger --tag hestia-install'
memory=$(grep 'MemTotal' /proc/meminfo | tr ' ' '\n' | grep [0-9])
hst_backups="/root/hst_install_backups/$(date +%d%m%Y%H%M)"
spinner="/-\|"
os=$ID
release=${VERSION_ID%.*}
codename=$PLATFORM_ID
architecture="$(arch)"
HESTIA_INSTALL_DIR="$HESTIA/install/rpm"
HESTIA_COMMON_DIR="$HESTIA/install/common"
VERBOSE='no'

# Define software versions
HESTIA_INSTALL_VER='1.8.3'
# Dependencies
multiphp_v=("7.4" "8.0" "8.1" "8.2")
fpm_v="8.1"
sysphp="8.2"
mariadb_v="11.0"

# Defining software pack for all distros
software="acl awstats bash-completion bc bind ca-certificates crudini curl expect flex ftp gnupg2 
  idn2 ImageMagick ipset jq mc nodejs openssl openssh-server
  php php-apcu php-cgi php-cli php-common php-curl php-gd php-imagick php-imap php-intl 
  php-ldap php-mbstring php-mysqlnd php-opcache php-pgsql php-pspell php-readline php-xml php-zip 
  postgresql pwgen quota rrdtool rsyslog sudo sysstat unzip util-linux vim wget whois zip zstd"

installer_dependencies="ca-certificates curl glibc-langpack-en gnupg2 openssl rng-tools wget yum-utils"

# Defining help function
help() {
	echo "Usage: $0 [OPTIONS]
  -a, --apache            Install Apache        [yes|no]  default: yes
  -w, --phpfpm            Install PHP-FPM       [yes|no]  default: yes
  -o, --multiphp          Install Multi-PHP     [yes|no]  default: no
  -v, --vsftpd            Install Vsftpd        [yes|no]  default: yes
  -j, --proftpd           Install ProFTPD       [yes|no]  default: no
  -k, --named             Install Bind          [yes|no]  default: yes
  -m, --mysql             Install MariaDB       [yes|no]  default: yes
  -M, --mysql8            Install MySQL         [yes|no]  default: no
  -g, --postgresql        Install PostgreSQL    [yes|no]  default: no
  -x, --exim              Install Exim          [yes|no]  default: yes
  -z, --dovecot           Install Dovecot       [yes|no]  default: yes
  -Z, --sieve             Install Sieve         [yes|no]  default: no
  -c, --clamav            Install ClamAV        [yes|no]  default: yes
  -t, --spamassassin      Install SpamAssassin  [yes|no]  default: yes
  -i, --iptables          Install Iptables      [yes|no]  default: no (unused)
  -b, --fail2ban          Install Fail2ban      [yes|no]  default: yes
  -q, --quota             Filesystem Quota      [yes|no]  default: no
  -d, --api               Activate API          [yes|no]  default: yes
  -r, --port              Change Backend Port             default: 8083
  -l, --lang              Default language                default: en
  -y, --interactive       Interactive install   [yes|no]  default: yes
  -s, --hostname          Set hostname
  -e, --email             Set admin email
  -p, --password          Set admin password
  -D, --with-debs         Path to Hestia debs (unused)
  -V, --from-vesta        Migrate from VestaCP
  -f, --force             Force installation
  -h, --help              Print this help

  Example: bash $0 -e demo@hestiacp.com -p p4ssw0rd --multiphp yes"
	exit 1
}

# Defining file download function
download_file() {
	wget $1 -q --show-progress --progress=bar:force
}

# Defining password-gen function
gen_pass() {
	matrix=$1
	length=$2
	if [ -z "$matrix" ]; then
		matrix="A-Za-z0-9"
	fi
	if [ -z "$length" ]; then
		length=16
	fi
	head /dev/urandom | tr -dc $matrix | head -c$length
}

# Defining return code check function
check_result() {
	if [ $1 -ne 0 ]; then
		echo "Error: $2"
		exit $1
	fi
}

# Defining function to set default value
set_default_value() {
	eval variable=\$$1
	if [ -z "$variable" ]; then
		eval $1=$2
	fi
	if [ "$variable" != 'yes' ] && [ "$variable" != 'no' ]; then
		eval $1=$2
	fi
}

# Defining function to set default language value
set_default_lang() {
	if [ -z "$lang" ]; then
		eval lang=$1
	fi
	lang_list="ar az bg bn bs ca cs da de el en es fa fi fr hr hu id it ja ka ku ko nl no pl pt pt-br ro ru sk sq sr sv th tr uk ur vi zh-cn zh-tw"
	if ! (echo $lang_list | grep -w $lang > /dev/null 2>&1); then
		eval lang=$1
	fi
}

# Define the default backend port
set_default_port() {
	if [ -z "$port" ]; then
		eval port=$1
	fi
}

# Write configuration KEY/VALUE pair to $HESTIA/conf/hestia.conf
write_config_value() {
	local key="$1"
	local value="$2"
	echo "$key='$value'" >> $HESTIA/conf/hestia.conf
}

# Sort configuration file values
# Write final copy to $HESTIA/conf/hestia.conf for active usage
# Duplicate file to $HESTIA/conf/defaults/hestia.conf to restore known good installation values
sort_config_file() {
	sort $HESTIA/conf/hestia.conf -o /tmp/updconf
	mv $HESTIA/conf/hestia.conf $HESTIA/conf/hestia.conf.bak
	mv /tmp/updconf $HESTIA/conf/hestia.conf
	rm -f $HESTIA/conf/hestia.conf.bak
	if [ ! -d "$HESTIA/conf/defaults/" ]; then
		mkdir -p "$HESTIA/conf/defaults/"
	fi
	cp $HESTIA/conf/hestia.conf $HESTIA/conf/defaults/hestia.conf
}

# Validate hostname according to RFC1178
validate_hostname() {
	# remove extra .
	servername=$(echo "$servername" | sed -e "s/[.]*$//g")
	servername=$(echo "$servername" | sed -e "s/^[.]*//")
	if [[ $(echo "$servername" | grep -o "\." | wc -l) -gt 1 ]] && [[ ! $servername =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		# Hostname valid
		return 1
	else
		# Hostname invalid
		return 0
	fi
}

validate_email() {
	if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[[:alnum:].-]+\.[A-Za-z]{2,63}$ ]]; then
		# Email invalid
		return 0
	else
		# Email valid
		return 1
	fi
}

version_ge() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" -o -n "$1" -a "$1" = "$2"; }

#----------------------------------------------------------#
#                    Verifications                         #
#----------------------------------------------------------#

# Creating temporary file
tmpfile=$(mktemp -p /tmp)

# Translating argument to --gnu-long-options
for arg; do
	delim=""
	case "$arg" in
		--apache) args="${args}-a " ;;
		--phpfpm) args="${args}-w " ;;
		--vsftpd) args="${args}-v " ;;
		--proftpd) args="${args}-j " ;;
		--named) args="${args}-k " ;;
		--mysql) args="${args}-m " ;;
		--mariadb) args="${args}-m " ;;
		--mysql-classic) args="${args}-M " ;;
		--mysql8) args="${args}-M " ;;
		--postgresql) args="${args}-g " ;;
		--exim) args="${args}-x " ;;
		--dovecot) args="${args}-z " ;;
		--sieve) args="${args}-Z " ;;
		--clamav) args="${args}-c " ;;
		--spamassassin) args="${args}-t " ;;
		--iptables) args="${args}-i " ;;
		--fail2ban) args="${args}-b " ;;
		--multiphp) args="${args}-o " ;;
		--quota) args="${args}-q " ;;
		--port) args="${args}-r " ;;
		--lang) args="${args}-l " ;;
		--interactive) args="${args}-y " ;;
		--api) args="${args}-d " ;;
		--hostname) args="${args}-s " ;;
		--email) args="${args}-e " ;;
		--password) args="${args}-p " ;;
		--force) args="${args}-f " ;;
		--with-debs) args="${args}-D " ;;
		--from-vesta) args="${args}-V" ;;
		--help) args="${args}-h " ;;
		*)
			[[ "${arg:0:1}" == "-" ]] || delim="\""
			args="${args}${delim}${arg}${delim} "
			;;
	esac
done
eval set -- "$args"

# Parsing arguments
while getopts "a:w:v:j:k:m:M:g:d:x:z:Z:c:t:i:b:r:o:q:l:y:s:e:p:D:V:fh" Option; do
	case $Option in
		a) apache=$OPTARG ;;      # Apache
		w) phpfpm=$OPTARG ;;      # PHP-FPM
		o) multiphp=$OPTARG ;;    # Multi-PHP
		v) vsftpd=$OPTARG ;;      # Vsftpd
		j) proftpd=$OPTARG ;;     # Proftpd
		k) named=$OPTARG ;;       # Named
		m) mysql=$OPTARG ;;       # MariaDB
		M) mysql8=$OPTARG ;;      # MySQL
		g) postgresql=$OPTARG ;;  # PostgreSQL
		x) exim=$OPTARG ;;        # Exim
		z) dovecot=$OPTARG ;;     # Dovecot
		Z) sieve=$OPTARG ;;       # Sieve
		c) clamd=$OPTARG ;;       # ClamAV
		t) spamd=$OPTARG ;;       # SpamAssassin
		i) iptables=$OPTARG ;;    # Iptables
		b) fail2ban=$OPTARG ;;    # Fail2ban
		q) quota=$OPTARG ;;       # FS Quota
		r) port=$OPTARG ;;        # Backend Port
		l) lang=$OPTARG ;;        # Language
		d) api=$OPTARG ;;         # Activate API
		y) interactive=$OPTARG ;; # Interactive install
		s) servername=$OPTARG ;;  # Hostname
		e) email=$OPTARG ;;       # Admin email
		p) vpass=$OPTARG ;;       # Admin password
		D) withdebs=$OPTARG ;;    # Hestia debs path
		V) fromvesta=$OPTARG ;;   # Migrate from VestaCP
		f) force='yes' ;;         # Force install
		h) help ;;                # Help
		*) help ;;                # Print help (default)
	esac
done

# Defining default software stack
set_default_value 'nginx' 'yes'
set_default_value 'apache' 'yes'
set_default_value 'phpfpm' 'yes'
set_default_value 'multiphp' 'no'
set_default_value 'vsftpd' 'yes'
set_default_value 'proftpd' 'no'
set_default_value 'named' 'yes'
set_default_value 'mysql' 'yes'
set_default_value 'mysql8' 'no'
set_default_value 'postgresql' 'no'
set_default_value 'exim' 'yes'
set_default_value 'dovecot' 'yes'
set_default_value 'sieve' 'no'
if [ $memory -lt 1500000 ]; then
	set_default_value 'clamd' 'no'
	set_default_value 'spamd' 'no'
elif [ $memory -lt 3000000 ]; then
	set_default_value 'clamd' 'no'
	set_default_value 'spamd' 'yes'
else
	set_default_value 'clamd' 'yes'
	set_default_value 'spamd' 'yes'
fi
set_default_value 'iptables' 'no'
set_default_value 'fail2ban' 'yes'
set_default_value 'quota' 'no'
set_default_value 'interactive' 'yes'
set_default_value 'api' 'yes'
set_default_port '8083'
set_default_lang 'en'

# Checking software conflicts
if [ "$proftpd" = 'yes' ]; then
	vsftpd='no'
fi
if [ "$exim" = 'no' ]; then
	clamd='no'
	spamd='no'
	dovecot='no'
fi
if [ "$dovecot" = 'no' ]; then
	sieve='no'
fi
#if [ "$iptables" = 'no' ]; then
#	fail2ban='no'
#fi
if [ "$apache" = 'no' ]; then
	phpfpm='yes'
fi
if [ "$mysql" = 'yes' ] && [ "$mysql8" = 'yes' ]; then
	mysql='no'
fi

# Checking root permissions
if [ "x$(id -u)" != 'x0' ]; then
	check_result 1 "Script can be run executed only by root"
fi

if [ -e "$HESTIA/conf/hestia.conf" ]; then
	check_result 1 "Hestia install detected. Unable to continue"
fi

# Checking admin user account
if [ -n "$(grep ^admin: /etc/passwd /etc/group)" ] && [ -z "$force" ]; then
	echo 'Please remove admin user account before proceeding.'
	echo 'If you want to do it automatically run installer with -f option:'
	echo -e "Example: bash $0 --force\n"
	check_result 1 "User admin exists"
fi

# Clear the screen once launch permissions have been verified
clear

# Welcome message
echo "Welcome to the Hestia Control Panel installer!"
echo
echo "Please wait, the installer is now checking for missing dependencies..."
echo

# Creating backup directory
mkdir -p "$hst_backups"

# Pre-install packages
echo "[ * ] Installing dependencies..."
yum -y install $installer_dependencies | $LOG
check_result $? "Package installation failed, check log file for more details."

systemctl enable rngd
systemctl start rngd

## Check repository availability
#wget --quiet "https://$RHOST" -O /dev/null
#check_result $? "Unable to connect to the Hestia APT repository"

# Check installed packages
conflicts_pkg="mariadb-server|MariaDB-server|httpd|nginx|hestia|ufw"
# Add mail servers to the list if exim will be installe
if [ "$exim" = 'yes' ]; then
        conflicts_pkg="$conflicts_pkg|postfix|exim"
fi

conflicts=$(rpm -qa | grep -P "^($conflicts_pkg)-\d" | sed "s/$/ /")
if [ -n "$conflicts" ] && [ -z "$force" ]; then
	echo '!!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!!'
	echo
	echo 'WARNING: The following packages are already installed'
	echo "$conflicts"
	echo
	echo 'It is highly recommended that you remove them before proceeding.'
	echo
	echo '!!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!! !!!'
	echo
	read -p 'Would you like to remove the conflicting packages? [y/n] ' answer
	if [ "$answer" = 'y' ] || [ "$answer" = 'Y' ]; then
		unset $answer
		yum -y remove $conflicts
		check_result $? "Package installation failed, check log file for more details."
	else
		check_result 1 "Hestia Control Panel should be installed on a clean server."
	fi
fi

# Check network configuration
nmcli general status | grep connected > /dev/null
if [ ! $? ] && [ -z "$force" ]; then
	check_result 1 "Unable to detect network configuration."
fi

case $architecture in
	x86_64)
		ARCH="amd64"
		;;
	*)
		echo
		echo -e "\e[91mInstallation aborted\e[0m"
		echo "===================================================================="
		echo -e "\e[33mERROR: $architecture is currently not supported!\e[0m"
		echo -e "\e[33mPlease verify the achitecture used is currenlty supported\e[0m"
		echo ""
		echo -e "\e[33mhttps://github.com/hestiacp/hestiacp/blob/main/README.md\e[0m"
		echo ""
		check_result 1 "Installation aborted"
		;;
esac

#----------------------------------------------------------#
#                       Brief Info                         #
#----------------------------------------------------------#

install_welcome_message() {
	DISPLAY_VER=$(echo $HESTIA_INSTALL_VER | sed "s|~alpha||g" | sed "s|~beta||g")
	echo
	echo '                _   _           _   _        ____ ____                  '
	echo '               | | | | ___  ___| |_(_) __ _ / ___|  _ \                 '
	echo '               | |_| |/ _ \/ __| __| |/ _` | |   | |_) |                '
	echo '               |  _  |  __/\__ \ |_| | (_| | |___|  __/                 '
	echo '               |_| |_|\___||___/\__|_|\__,_|\____|_|                    '
	echo "                                                                        "
	echo "                          Hestia Control Panel                          "
	if [[ "$HESTIA_INSTALL_VER" =~ "beta" ]]; then
		echo "                              BETA RELEASE                          "
	fi
	if [[ "$HESTIA_INSTALL_VER" =~ "alpha" ]]; then
		echo "                          DEVELOPMENT SNAPSHOT                      "
		echo "                    NOT INTENDED FOR PRODUCTION USE                 "
		echo "                          USE AT YOUR OWN RISK                      "
	fi
	echo "                                  ${DISPLAY_VER}                        "
	echo "                            www.hestiacp.com                            "
	echo
	echo "========================================================================"
	echo
	echo "Thank you for downloading Hestia Control Panel! In a few moments,"
	echo "we will begin installing the following components on your server:"
	echo
}

# Printing nice ASCII logo
clear
install_welcome_message

# Web stack
echo '   - NGINX Web / Proxy Server'
if [ "$apache" = 'yes' ]; then
	echo '   - Apache Web Server (as backend)'
fi
if [ "$phpfpm" = 'yes' ] && [ "$multiphp" = 'no' ]; then
	echo '   - PHP-FPM Application Server'
fi
if [ "$multiphp" = 'yes' ]; then
	phpfpm='yes'
	echo '   - Multi-PHP Environment (Currently just partially supprted on RHEL/CentOS)'
fi

# DNS stack
if [ "$named" = 'yes' ]; then
	echo '   - Bind DNS Server'
fi

# Mail stack
if [ "$exim" = 'yes' ]; then
	echo -n '   - Exim Mail Server'
	if [ "$clamd" = 'yes' ] || [ "$spamd" = 'yes' ]; then
		echo -n ' + '
		if [ "$clamd" = 'yes' ]; then
			echo -n 'ClamAV '
		fi
		if [ "$spamd" = 'yes' ]; then
			if [ "$clamd" = 'yes' ]; then
				echo -n '+ '
			fi
			echo -n 'SpamAssassin'
		fi
	fi
	echo
	if [ "$dovecot" = 'yes' ]; then
		echo -n '   - Dovecot POP3/IMAP Server'
		if [ "$sieve" = 'yes' ]; then
			echo -n '+ Sieve'
		fi
	fi
fi

echo

# Database stack
if [ "$mysql" = 'yes' ]; then
	echo '   - MariaDB Database Server'
fi
if [ "$mysql8" = 'yes' ]; then
	echo '   - MySQL8 Database Server'
fi
if [ "$postgresql" = 'yes' ]; then
	echo '   - PostgreSQL Database Server'
fi

# FTP stack
if [ "$vsftpd" = 'yes' ]; then
	echo '   - Vsftpd FTP Server'
fi
if [ "$proftpd" = 'yes' ]; then
	echo '   - ProFTPD FTP Server'
fi

# Firewall stack
if [ "$iptables" = 'yes' ]; then
	echo -n '   - Firewall (iptables)'
fi
if [ "$fail2ban" = 'yes' ]; then
	echo -n ' + Fail2Ban Access Monitor'
fi
echo -e "\n"
echo "========================================================================"
echo -e "\n"

# Asking for confirmation to proceed
if [ "$interactive" = 'yes' ]; then
	read -p 'Would you like to continue with the installation? [Y/N]: ' answer
	if [ "$answer" != 'y' ] && [ "$answer" != 'Y' ]; then
		echo 'Goodbye'
		exit 1
	fi
fi

# Validate Email / Hostname even when interactive = no
# Asking for contact email
if [ -z "$email" ]; then
	while validate_email; do
		echo -e "\nPlease use a valid emailadress (ex. info@domain.tld)."
		read -p 'Please enter admin email address: ' email
	done
else
	if validate_email; then
		echo "Please use a valid emailadress (ex. info@domain.tld)."
		exit 1
	fi
fi

# Asking to set FQDN hostname
if [ -z "$servername" ]; then
	# Ask and validate FQDN hostname.
	read -p "Please enter FQDN hostname [$(hostname -f)]: " servername

	# Set hostname if it wasn't set
	if [ -z "$servername" ]; then
		servername=$(hostname -f)
	fi

	# Validate Hostname, go to loop if the validation fails.
	while validate_hostname; do
		echo -e "\nPlease use a valid hostname according to RFC1178 (ex. hostname.domain.tld)."
		read -p "Please enter FQDN hostname [$(hostname -f)]: " servername
	done
else
	# Validate FQDN hostname if it is preset
	if validate_hostname; then
		echo "Please use a valid hostname according to RFC1178 (ex. hostname.domain.tld)."
		exit 1
	fi
fi

# Generating admin password if it wasn't set
displaypass="The password you chose during installation."
if [ -z "$vpass" ]; then
	vpass=$(gen_pass)
	displaypass=$vpass
fi

# Set FQDN if it wasn't set
mask1='(([[:alnum:]](-?[[:alnum:]])*)\.)'
mask2='*[[:alnum:]](-?[[:alnum:]])+\.[[:alnum:]]{2,}'
if ! [[ "$servername" =~ ^${mask1}${mask2}$ ]]; then
	if [[ -n "$servername" ]]; then
		servername="$servername.example.com"
	else
		servername="example.com"
	fi
	echo "127.0.0.1 $servername" >> /etc/hosts
fi

if [[ -z $(grep -i "$servername" /etc/hosts) ]]; then
	echo "127.0.0.1 $servername" >> /etc/hosts
fi

# Set email if it wasn't set
if [[ -z "$email" ]]; then
	email="admin@$servername"
fi

# Defining backup directory
echo -e "Installation backup directory: $hst_backups"

# Print Log File Path
echo "Installation log: journalctl -u hestia-install"

# Print new line
echo

#----------------------------------------------------------#
#                      Checking swap                       #
#----------------------------------------------------------#

# Checking swap on small instances
if [ -z "$(swapon -s)" ] && [ "$memory" -lt 1000000 ]; then
	fallocate -l 1G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	echo "/swapfile	none	swap	sw	0	0" >> /etc/fstab
fi

#----------------------------------------------------------#
#                   Install repository                     #
#----------------------------------------------------------#

# Updating system
echo "Adding required repositories to proceed with installation:"
echo

# Installing EPEL repo
if [ $VERSION = "rhel" ] ; then
	subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
	check_result $? "Package installation failed, check log file for more details."
else
	yum config-manager --set-enabled crb
	yum -y install epel-release epel-next-release
	check_result $? "Package installation failed, check log file for more details."
fi

# Installing Nginx repo
echo "[ * ] NGINX"
cat >/etc/yum.repos.d/nginx.repo <<EOF
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

# Installing PHP repos
echo "[ * ] PHP"
yum -y install https://rpms.remirepo.net/enterprise/remi-release-$release.rpm > /dev/null 2>&1
check_result $? "Package installation failed, check log file for more details."

# Installing NodeJS repos
yum module enable nodejs:18/common

# Installing MariaDB repo
if [ "$mysql" == 'yes' ]; then
	echo "[ * ] MariaDB"
	if [ "$VERSION" == "rhel" ] ; then
		str=rhel
	else
		str=centos
	fi
	cat >/etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name=MariaDB
baseurl=https://rpm.mariadb.org/$mariadb_v/$str/\$releasever/\$basearch
gpgkey=https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
enabled=1
EOF
fi

# Installing PostgreSQL repo
if [ "$postgresql" = 'yes' ]; then
	echo "[ * ] PostgreSQL"
	yum -y module enable postgresql/server | $LOG
	check_result $? "Package installation failed, check log file for more details."
fi

yum -y module enable php:remi-$sysphp/common
check_result $? "Package installation failed, check log file for more details."

# Echo for a new line
echo

# Updating system
echo -ne "Updating currently installed packages, please wait... "
yum -y upgrade | $LOG
check_result $? "Package installation failed, check log file for more details."

# Start install dhparam.pem
openssl dhparam -out /etc/pki/tls/dhparm.pem 4096 >/dev/null 2>&1 &
DHPARAM_PID=$!

#----------------------------------------------------------#
#                         Backup                           #
#----------------------------------------------------------#

# Creating backup directory tree
mkdir -p $hst_backups
cd $hst_backups
mkdir nginx httpd php vsftpd proftpd bind exim dovecot clamd spamassassin mysql postgresql openssl hestia

# Backup OpenSSL configuration
cp /etc/ssl/openssl.cnf $hst_backups/openssl > /dev/null 2>&1

# Backup nginx configuration
systemctl stop nginx > /dev/null 2>&1
cp -r /etc/nginx/* $hst_backups/nginx > /dev/null 2>&1

# Backup Apache configuration
systemctl stop httpd > /dev/null 2>&1
cp -r /etc/httpd/ $hst_backups/httpd > /dev/null 2>&1
rm -rf /etc/httpd/conf.d/* > /dev/null 2>&1

# Backup PHP-FPM configuration
systemctl stop php*-fpm > /dev/null 2>&1
cp -r /etc/php* $hst_backups/php > /dev/null 2>&1
mkdir -p $hst_backups/php/remi
cp -r /etc/opt/remi/php* $hst_backups/php/remi/ > /dev/null 2>&1

# Backup Bind configuration
systemctl stop named > /dev/null 2>&1
mkdir $hst_backups/bind
cp -r /etc/named* $hst_backups/bind/ > /dev/null 2>&1

# Backup Vsftpd configuration
systemctl stop vsftpd > /dev/null 2>&1
cp /etc/vsftpd.conf $hst_backups/vsftpd > /dev/null 2>&1

# Backup ProFTPD configuration
systemctl stop proftpd > /dev/null 2>&1
cp /etc/proftpd/* $hst_backups/proftpd > /dev/null 2>&1

# Backup Exim configuration
systemctl stop exim > /dev/null 2>&1
cp -r /etc/exim/* $hst_backups/exim4 > /dev/null 2>&1

# Backup ClamAV configuration
systemctl stop clamav-daemon clamd@vesta clamd@hestia clamav-freshclam clamd > /dev/null 2>&1
cp -r /etc/clamav/* $hst_backups/clamav > /dev/null 2>&1

# Backup SpamAssassin configuration
systemctl stop spamassassin > /dev/null 2>&1
cp -r /etc/spamassassin/* $hst_backups/spamassassin > /dev/null 2>&1

# Backup Dovecot configuration
systemctl stop dovecot > /dev/null 2>&1
cp /etc/dovecot.conf $hst_backups/dovecot > /dev/null 2>&1
cp -r /etc/dovecot/* $hst_backups/dovecot > /dev/null 2>&1

# Backup MySQL/MariaDB configuration and data
systemctl stop mysql > /dev/null 2>&1
killall -9 mysqld > /dev/null 2>&1
mv /var/lib/mysql $hst_backups/mysql/mysql_datadir > /dev/null 2>&1
cp -r /etc/mysql/* $hst_backups/mysql > /dev/null 2>&1
mv -f /root/.my.cnf $hst_backups/mysql > /dev/null 2>&1

#----------------------------------------------------------#
#                     Package Includes                     #
#----------------------------------------------------------#

if [ "$phpfpm" = 'yes' ]; then
	fpm_v=${fpm_v/./}
	fpm="php$fpm_v php$fpm_v-php php$fpm_v-php-common php$fpm_v-php-bcmath php$fpm_v-php-cli
         php$fpm_v-php-curl php$fpm_v-php-fpm php$fpm_v-php-gd php$fpm_v-php-intl
         php$fpm_v-php-soap php$fpm_v-php-xml php$fpm_v-php-zip php$fpm_v-php-mbstring 
	 php$fpm_v-php-pspell php$fpm_v-php-imagick"
	software="$software $fpm"
	if [[ $fpm_v =~ 81|74 ]]; then
	       software="$software php$fpm_v-php-ioncube-loader"
	fi
fi

#----------------------------------------------------------#
#                     Package Includes                     #
#----------------------------------------------------------#

# Including packages
if [ "$apache" = 'yes' ]; then
	software="$software httpd mod_ssl"
fi
if [ "$vsftpd" = 'yes' ]; then
	software="$software vsftpd"
fi
if [ "$proftpd" = 'yes' ]; then
	software="$software proftpd"
fi
if [ "$named" = 'yes' ]; then
	software="$software bind"
fi
if [ "$exim" = 'yes' ]; then
	software="$software exim"
fi
if [ "$clamd" = 'yes' ]; then
	software="$software clamd clamav"
fi
if [ "$spamd" = 'yes' ]; then
	software="$software spamassassin"
fi
if [ "$dovecot" = 'yes' ]; then
	software="$software dovecot"
fi
if [ "$sieve" = 'yes' ]; then
	software="$software dovecot-pigeonhole"
fi
if [ "$mysql" = 'yes' ]; then
	software="$software MariaDB-client MariaDB-client-compat MariaDB-server MariaDB-server-compat"
fi
if [ "$mysql8" = 'yes' ]; then
	software="$software mysql-server mysql-client"
fi
if [ "$mysql" = 'yes' ] || [ "$mysql8" = 'yes' ]; then
	if [ "$multiphp" = 'yes' ]; then
		for v in "${multiphp_v[@]}"; do
			v=${v/./}
			software="$software php$v-php-mysqlnd"
			if [[ $v =~ 81|74 ]]; then
			       software="$software php$v-php-ioncube-loader"
			fi
		done
	else
		software="$software php$fpm_v-php-mysqlnd"
	fi
fi
if [ "$postgresql" = 'yes' ]; then
	software="$software postgresql php$fpm_v-php-pgsql"
fi
if [ "$fail2ban" = 'yes' ]; then
	software="$software fail2ban fail2ban-firewalld"
fi
if [ "$phpfpm" = 'yes' ]; then
	software="$software"
fi

#----------------------------------------------------------#
#                     Install packages                     #
#----------------------------------------------------------#

# Enable en_US.UTF-8
localectl set-locale en_US.UTF-8

# Installing apt packages
echo "The installer is now downloading and installing all required packages."
echo -ne "NOTE: This process may take 10 to 15 minutes to complete, please wait... "
echo
yum -y install $software | $LOG
check_result $? "Package installation failed, check log file for more details."

echo
echo "========================================================================"
echo

## Install Hestia packages from local folder
#if [ -n "$withdebs" ] && [ -d "$withdebs" ]; then
#	echo "[ * ] Installing local package files..."
#	echo "    - hestia core package"
#	dpkg -i $withdebs/hestia_*.deb > /dev/null 2>&1
#
#	if [ -z $(ls $withdebs/hestia-php_*.deb 2> /dev/null) ]; then
#		echo "    - hestia-php backend package (from apt)"
#		apt-get -y install hestia-php > /dev/null 2>&1
#	else
#		echo "    - hestia-php backend package"
#		dpkg -i $withdebs/hestia-php_*.deb > /dev/null 2>&1
#	fi
#
#	if [ -z $(ls $withdebs/hestia-nginx_*.deb 2> /dev/null) ]; then
#		echo "    - hestia-nginx backend package (from apt)"
#		apt-get -y install hestia-nginx > /dev/null 2>&1
#	else
#		echo "    - hestia-nginx backend package"
#		dpkg -i $withdebs/hestia-nginx_*.deb > /dev/null 2>&1
#	fi
#fi
cp -f $HESTIA_INSTALL_DIR/hestia/hestia.service /etc/systemd/system
cp -f $HESTIA_INSTALL_DIR/nginx/hestia-nginx.service /etc/systemd/system
cp -f $HESTIA_INSTALL_DIR/php/hestia-php.service /etc/systemd/system
systemctl daemon-reload
systemctl enable hestia hestia-php hestia-nginx
systemctl start hestia hestia-php hestia-nginx

#----------------------------------------------------------#
#                     Configure system                     #
#----------------------------------------------------------#

echo "[ * ] Configuring system settings..."

# Enable SFTP subsystem for SSH
sftp_subsys_enabled=$(grep -iE "^#?.*subsystem.+(sftp )?sftp-server" /etc/ssh/sshd_config)
if [ -n "$sftp_subsys_enabled" ]; then
	sed -i -E "s/^#?.*Subsystem.+(sftp )?sftp-server/Subsystem sftp internal-sftp/g" /etc/ssh/sshd_config
fi

# Reduce SSH login grace time
sed -i "s/[#]LoginGraceTime [[:digit:]]m/LoginGraceTime 1m/g" /etc/ssh/sshd_config

# Restart SSH daemon
systemctl restart ssh

# Register /usr/sbin/nologin
if [ -z "$(grep '/usr/sbin/nologin' /etc/shells)" ]; then
	echo "/usr/sbin/nologin" >> /etc/shells
fi

# Configuring NTP
timedatectl set-ntp 1

# Restrict access to /proc fs
# - Prevent unpriv users from seeing each other running processes
mount -o remount,defaults,hidepid=2 /proc > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Info: Cannot remount /proc (LXC containers require additional perm added to host apparmor profile)"
else
	echo "@reboot root sleep 5 && mount -o remount,defaults,hidepid=2 /proc" > /etc/cron.d/hestia-proc
fi

#----------------------------------------------------------#
#                     Configure Hestia                     #
#----------------------------------------------------------#

echo "[ * ] Configuring Hestia Control Panel..."
# Installing sudo configuration
mkdir -p /etc/sudoers.d
cp -f $HESTIA_INSTALL_DIR/sudo/admin /etc/sudoers.d/
chmod 440 /etc/sudoers.d/admin

# Add Hestia global config
if [[ ! -e /etc/hestiacp/hestia.conf ]]; then
	mkdir -p /etc/hestiacp
	echo -e "# Do not edit this file, will get overwritten on next upgrade, use /etc/hestiacp/local.conf instead\n\nexport HESTIA='$HESTIA'\n\n[[ -f /etc/hestiacp/local.conf ]] && source /etc/hestiacp/local.conf" > /etc/hestiacp/hestia.conf
fi

# Configuring system env
echo "export HESTIA='$HESTIA'" > /etc/profile.d/hestia.sh
echo 'PATH=$PATH:'$HESTIA'/bin' >> /etc/profile.d/hestia.sh
echo 'export PATH' >> /etc/profile.d/hestia.sh
chmod 755 /etc/profile.d/hestia.sh
source /etc/profile.d/hestia.sh

# Configuring logrotate for Hestia logs
cp -f $HESTIA_INSTALL_DIR/logrotate/hestia /etc/logrotate.d/hestia

# Create log path and symbolic link
rm -f /var/log/hestia
mkdir -p /var/log/hestia
ln -s /var/log/hestia $HESTIA/log

# Building directory tree and creating some blank files for Hestia
mkdir -p $HESTIA/conf $HESTIA/ssl $HESTIA/data/ips \
	$HESTIA/data/queue $HESTIA/data/users $HESTIA/data/firewall \
	$HESTIA/data/sessions
touch $HESTIA/data/queue/backup.pipe $HESTIA/data/queue/disk.pipe \
	$HESTIA/data/queue/webstats.pipe $HESTIA/data/queue/restart.pipe \
	$HESTIA/data/queue/traffic.pipe $HESTIA/data/queue/daily.pipe $HESTIA/log/system.log \
	$HESTIA/log/nginx-error.log $HESTIA/log/auth.log $HESTIA/log/backup.log
chmod 750 $HESTIA/conf $HESTIA/data/users $HESTIA/data/ips $HESTIA/log
chmod -R 750 $HESTIA/data/queue
chmod 660 /var/log/hestia/*
chmod 770 $HESTIA/data/sessions

# Generating Hestia configuration
rm -f $HESTIA/conf/hestia.conf > /dev/null 2>&1
touch $HESTIA/conf/hestia.conf
chmod 660 $HESTIA/conf/hestia.conf

# Write default port value to hestia.conf
# If a custom port is specified it will be set at the end of the installation process.
write_config_value "BACKEND_PORT" "8083"

# Web stack
if [ "$apache" = 'yes' ]; then
	write_config_value "WEB_SYSTEM" "httpd"
	write_config_value "WEB_RGROUPS" "www-data"
	write_config_value "WEB_PORT" "8080"
	write_config_value "WEB_SSL_PORT" "8443"
	write_config_value "WEB_SSL" "mod_ssl"
	write_config_value "PROXY_SYSTEM" "nginx"
	write_config_value "PROXY_PORT" "80"
	write_config_value "PROXY_SSL_PORT" "443"
	write_config_value "STATS_SYSTEM" "awstats"
fi
if [ "$apache" = 'no' ]; then
	write_config_value "WEB_SYSTEM" "nginx"
	write_config_value "WEB_PORT" "80"
	write_config_value "WEB_SSL_PORT" "443"
	write_config_value "WEB_SSL" "openssl"
	write_config_value "STATS_SYSTEM" "awstats"
fi
if [ "$phpfpm" = 'yes' ] || [ "$multiphp" = 'yes' ]; then
	write_config_value "WEB_BACKEND" "php-fpm"
fi

# Database stack
if [ "$mysql" = 'yes' ] || [ "$mysql8" = 'yes' ]; then
	installed_db_types='mysql'
fi
if [ "$postgresql" = 'yes' ]; then
	installed_db_types="$installed_db_types,pgsql"
fi
if [ -n "$installed_db_types" ]; then
	db=$(echo "$installed_db_types" \
		| sed "s/,/\n/g" \
		| sort -r -u \
		| sed "/^$/d" \
		| sed ':a;N;$!ba;s/\n/,/g')
	write_config_value "DB_SYSTEM" "$db"
fi

# FTP stack
if [ "$vsftpd" = 'yes' ]; then
	write_config_value "FTP_SYSTEM" "vsftpd"
fi
if [ "$proftpd" = 'yes' ]; then
	write_config_value "FTP_SYSTEM" "proftpd"
fi

# DNS stack
if [ "$named" = 'yes' ]; then
	write_config_value "DNS_SYSTEM" "bind9"
fi

# Mail stack
if [ "$exim" = 'yes' ]; then
	write_config_value "MAIL_SYSTEM" "exim4"
	if [ "$clamd" = 'yes' ]; then
		write_config_value "ANTIVIRUS_SYSTEM" "clamav-daemon"
	fi
	if [ "$spamd" = 'yes' ]; then
		write_config_value "ANTISPAM_SYSTEM" "spamassassin"
	fi
	if [ "$dovecot" = 'yes' ]; then
		write_config_value "IMAP_SYSTEM" "dovecot"
	fi
	if [ "$sieve" = 'yes' ]; then
		write_config_value "SIEVE_SYSTEM" "yes"
	fi
fi

# Cron daemon
write_config_value "CRON_SYSTEM" "cron"

# Firewall stack
if [ "$fail2ban" = 'yes' ]; then
	write_config_value "FIREWALL_EXTENSION" "fail2ban"
fi

# Disk quota
if [ "$quota" = 'yes' ]; then
	write_config_value "DISK_QUOTA" "yes"
else
	write_config_value "DISK_QUOTA" "no"
fi

# Backups
write_config_value "BACKUP_SYSTEM" "local"
write_config_value "BACKUP_GZIP" "4"
write_config_value "BACKUP_MODE" "zstd"

# Language
write_config_value "LANGUAGE" "$lang"

# Login in screen
write_config_value "LOGIN_STYLE" "default"

# Theme
write_config_value "THEME" "dark"

# Inactive session timeout
write_config_value "INACTIVE_SESSION_TIMEOUT" "60"

# Version & Release Branch
write_config_value "VERSION" "${HESTIA_INSTALL_VER}"
write_config_value "RELEASE_BRANCH" "release"

# Email notifications after upgrade
write_config_value "UPGRADE_SEND_EMAIL" "true"
write_config_value "UPGRADE_SEND_EMAIL_LOG" "false"

# Installing hosting packages
cp -rf $HESTIA_COMMON_DIR/packages $HESTIA/data/

# Update nameservers in hosting package
IFS='.' read -r -a domain_elements <<< "$servername"
if [ -n "${domain_elements[-2]}" ] && [ -n "${domain_elements[-1]}" ]; then
	serverdomain="${domain_elements[-2]}.${domain_elements[-1]}"
	sed -i s/"domain.tld"/"$serverdomain"/g $HESTIA/data/packages/*.pkg
fi

# Installing templates
cp -rf $HESTIA_INSTALL_DIR/templates $HESTIA/data/
cp -rf $HESTIA_COMMON_DIR/templates/web/ $HESTIA/data/templates
cp -rf $HESTIA_COMMON_DIR/templates/dns/ $HESTIA/data/templates

mkdir -p /var/www/html
mkdir -p /var/www/document_errors

# Install default success page
cp -rf $HESTIA_COMMON_DIR/templates/web/unassigned/index.html /var/www/html/
cp -rf $HESTIA_COMMON_DIR/templates/web/skel/document_errors/* /var/www/document_errors/

# Installing firewall rules
cp -rf $HESTIA_COMMON_DIR/firewall $HESTIA/data/
rm -f $HESTIA/data/firewall/ipset/blacklist.sh $HESTIA/data/firewall/ipset/blacklist.ipv6.sh

# Installing apis
cp -rf $HESTIA_COMMON_DIR/api $HESTIA/data/

# Configuring server hostname
$HESTIA/bin/v-change-sys-hostname $servername > /dev/null 2>&1

# Configuring global OpenSSL options
echo "[ * ] Configuring OpenSSL to improve TLS performance..."
# configured by default RHEL install

# Generating SSL certificate
echo "[ * ] Generating default self-signed SSL certificate..."
$HESTIA/bin/v-generate-ssl-cert $(hostname) '' 'US' 'California' \
	'San Francisco' 'Hestia Control Panel' 'IT' > /tmp/hst.pem

# Parsing certificate file
crt_end=$(grep -n "END CERTIFICATE-" /tmp/hst.pem | cut -f 1 -d: | tail -1)
key_start=$(grep -Pn "BEGIN (RSA )?PRIVATE KEY" /tmp/hst.pem | cut -f 1 -d:)
key_end=$(grep -Pn "END (RSA )?PRIVATE KEY" /tmp/hst.pem | cut -f 1 -d:)

# Adding SSL certificate
echo "[ * ] Adding SSL certificate to Hestia Control Panel..."
sed -n "1,${crt_end}p" /tmp/hst.pem > $HESTIA/ssl/certificate.crt
sed -n "${key_start},${key_end}p" /tmp/hst.pem > $HESTIA/ssl/certificate.key
chown root:mail $HESTIA/ssl/*
chmod 660 $HESTIA/ssl/*
rm /tmp/hst.pem

# Continue install dhparam.pem

kill -0 $DHPARAM_PID
if [ $? ] ; then
	echo Wait for the completing of the DHParam generation
	spin_i=1
	while kill -0 $DHPARAM_PID > /dev/null 2>&1; do
	        printf "\b${spinner:spin_i++%${#spinner}:1}"
        	sleep 0.5
	done
fi
# Do a blank echo to get the \n back
echo
wait $DHPARAM_PID
ln -s /etc/pki/tls/dhparm.pem /etc/ssl/dhparam.pem

# Deleting old admin user
if [ -n "$(grep ^admin: /etc/passwd)" ] && [ "$force" = 'yes' ]; then
	chattr -i /home/admin/conf > /dev/null 2>&1
	userdel -f admin > /dev/null 2>&1
	chattr -i /home/admin/conf > /dev/null 2>&1
	mv -f /home/admin $hst_backups/home/ > /dev/null 2>&1
	rm -f /tmp/sess_* > /dev/null 2>&1
fi
if [ -n "$(grep ^admin: /etc/group)" ] && [ "$force" = 'yes' ]; then
	groupdel admin > /dev/null 2>&1
fi

# Remove sudo "default" sudo permission admin user group should not exists any way
sed -i "s/%admin ALL=(ALL) ALL/#%admin ALL=(ALL) ALL/g" /etc/sudoers

# Enable sftp jail
echo "[ * ] Enabling SFTP jail..."
$HESTIA/bin/v-add-sys-sftp-jail > /dev/null 2>&1
check_result $? "can't enable sftp jail"

# Adding Hestia admin account
echo "[ * ] Creating default admin account..."
$HESTIA/bin/v-add-user admin $vpass $email "system" "System Administrator"
check_result $? "can't create admin user"
$HESTIA/bin/v-change-user-shell admin nologin
$HESTIA/bin/v-change-user-role admin admin
$HESTIA/bin/v-change-user-language admin $lang
$HESTIA/bin/v-change-sys-config-value 'POLICY_SYSTEM_PROTECTED_ADMIN' 'yes'

#----------------------------------------------------------#
#                     Configure Nginx                      #
#----------------------------------------------------------#

echo "[ * ] Configuring NGINX..."
rm -f /etc/nginx/conf.d/*.conf
cp -f $HESTIA_INSTALL_DIR/nginx/nginx.conf /etc/nginx/
cp -f $HESTIA_INSTALL_DIR/nginx/status.conf /etc/nginx/conf.d/
cp -f $HESTIA_INSTALL_DIR/nginx/0rtt-anti-replay.conf /etc/nginx/conf.d/
cp -f $HESTIA_INSTALL_DIR/nginx/agents.conf /etc/nginx/conf.d/
cp -f $HESTIA_INSTALL_DIR/nginx/phpmyadmin.inc /etc/nginx/conf.d/
cp -f $HESTIA_INSTALL_DIR/nginx/phppgadmin.inc /etc/nginx/conf.d/
cp -f $HESTIA_INSTALL_DIR/logrotate/nginx /etc/logrotate.d/
mkdir -p /etc/nginx/conf.d/domains
mkdir -p /etc/nginx/conf.d/main
mkdir -p /etc/nginx/modules-enabled
mkdir -p /var/log/nginx/domains

# Update dns servers in nginx.conf
for nameserver in $(grep -is '^nameserver' /etc/resolv.conf | cut -d' ' -f2 | tr '\r\n' ' ' | xargs); do
	if [[ "$nameserver" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
		if [ -z "$resolver" ]; then
			resolver="$nameserver"
		else
			resolver="$resolver $nameserver"
		fi
	fi
done
if [ -n "$resolver" ]; then
	sed -i "s/1.0.0.1 8.8.4.4 1.1.1.1 8.8.8.8/$resolver/g" /etc/nginx/nginx.conf
fi

# https://github.com/ergin/nginx-cloudflare-real-ip/
cf_ips="$(curl -fsLm5 --retry 2 https://api.cloudflare.com/client/v4/ips)"

if [ -n "$cf_ips" ] && [ "$(echo "$cf_ips" | jq -r '.success//""')" = "true" ]; then
	cf_inc="/etc/nginx/conf.d/cloudflare.inc"

	echo "[ * ] Updating Cloudflare IP Ranges for Nginx..."
	echo "# Cloudflare IP Ranges" > $cf_inc
	echo "" >> $cf_inc
	echo "# IPv4" >> $cf_inc
	for ipv4 in $(echo "$cf_ips" | jq -r '.result.ipv4_cidrs[]//""' | sort); do
		echo "set_real_ip_from $ipv4;" >> $cf_inc
	done
	echo "" >> $cf_inc
	echo "# IPv6" >> $cf_inc
	for ipv6 in $(echo "$cf_ips" | jq -r '.result.ipv6_cidrs[]//""' | sort); do
		echo "set_real_ip_from $ipv6;" >> $cf_inc
	done
	echo "" >> $cf_inc
	echo "real_ip_header CF-Connecting-IP;" >> $cf_inc
fi

systemctl start nginx | $LOG
check_result $? "nginx start failed"

#----------------------------------------------------------#
#                    Configure Apache                      #
#----------------------------------------------------------#

if [ "$apache" = 'yes' ]; then
	echo "[ * ] Configuring Apache Web Server..."

	mkdir -p /etc/httpd/conf.d/domains

	# Copy configuration files
	cp -f $HESTIA_INSTALL_DIR/httpd/httpd.conf /etc/httpd/
	cp -f $HESTIA_INSTALL_DIR/httpd/status.conf /etc/httpd/conf.d/hestia-status.conf
	cp -f $HESTIA_INSTALL_DIR/logrotate/httpd /etc/logrotate.d/

	# Enable needed modules

	mkdir -p /var/log/httpd/domains
	chmod a+x /var/log/httpd
	chmod 751 /var/log/httpd/domains

	# Prevent remote access to server-status page
	sed -i '/Allow from all/d' /etc/httpd/conf.d/hestia-status.conf

	systemctl start httpd | $LOG
	check_result $? "httpd start failed"
else
	systemctl disable httpd > /dev/null 2>&1
	systemctl stop httpd > /dev/null 2>&1
fi

#----------------------------------------------------------#
#                     Configure PHP-FPM                    #
#----------------------------------------------------------#

if [ "$phpfpm" = "yes" ]; then
	if [ "$multiphp" = 'yes' ]; then
		for v in "${multiphp_v[@]}"; do
			echo "[ * ] Installing PHP $v..."
			$HESTIA/bin/v-add-web-php "$v" > /dev/null 2>&1
		done
	else
		echo "[ * ] Installing PHP $fpm_v..."
		$HESTIA/bin/v-add-web-php "$fpm_v" > /dev/null 2>&1
	fi

	echo "[ * ] Configuring PHP-FPM $fpm_v..."
	# Create www.conf for webmail and php(*)admin
	cp -f $HESTIA_INSTALL_DIR/php-fpm/www.conf /etc/opt/remi/php$fpm_v/php-fpm.d/www.conf
	systemctl enable php$fpm_v-php-fpm > /dev/null 2>&1
	systemctl start php$fpm_v-php-fpm | $LOG
	check_result $? "php-fpm start failed"
	# Set default php version to $fpm_v
	#update-alternatives --set php /usr/bin/php$fpm_v > /dev/null 2>&1
fi

#----------------------------------------------------------#
#                     Configure PHP                        #
#----------------------------------------------------------#

echo "[ * ] Configuring PHP..."
ZONE=$(timedatectl > /dev/null 2>&1 | grep Time zone | awk '{print $3}')
if [ -z "$ZONE" ]; then
	ZONE='UTC'
fi
for pconf in $(ls /etc/opt/remi/php*/php.d/ -d); do
	echo "date.timezone = $ZONE" >> $pconf/99-hestia.ini
	echo "short_open_tag = On" >> $pconf/99-hestia.ini
done

# Cleanup php session files not changed in the last 7 days (60*24*7 minutes)
echo '#!/bin/sh' > /etc/cron.daily/php-session-cleanup
echo "find -O3 /home/*/tmp/ -ignore_readdir_race -depth -mindepth 1 -name 'sess_*' -type f -cmin '+10080' -delete > /dev/null 2>&1" >> /etc/cron.daily/php-session-cleanup
echo "find -O3 $HESTIA/data/sessions/ -ignore_readdir_race -depth -mindepth 1 -name 'sess_*' -type f -cmin '+10080' -delete > /dev/null 2>&1" >> /etc/cron.daily/php-session-cleanup
chmod 755 /etc/cron.daily/php-session-cleanup

#----------------------------------------------------------#
#                    Configure Vsftpd                      #
#----------------------------------------------------------#

if [ "$vsftpd" = 'yes' ]; then
	echo "[ * ] Configuring Vsftpd server..."
	cp -f $HESTIA_INSTALL_DIR/vsftpd/vsftpd.conf /etc/
	touch /var/log/vsftpd.log
	chown root:adm /var/log/vsftpd.log
	chmod 640 /var/log/vsftpd.log
	touch /var/log/xferlog
	chown root:adm /var/log/xferlog
	chmod 640 /var/log/xferlog
	systemctl enable vsftpd > /dev/null 2>&1
	systemctl start vsftpd | $LOG
	check_result $? "vsftpd start failed"
fi

#----------------------------------------------------------#
#                    Configure ProFTPD                     #
#----------------------------------------------------------#

if [ "$proftpd" = 'yes' ]; then
	echo "[ * ] Configuring ProFTPD server..."
	[[ -z $(grep -i "$servername" /etc/hosts) ]] && echo "127.0.0.1 $servername" >> /etc/hosts
	cp -f $HESTIA_INSTALL_DIR/proftpd/proftpd.conf /etc/proftpd/
	cp -f $HESTIA_INSTALL_DIR/proftpd/tls.conf /etc/proftpd/

	systemctl enable proftpd > /dev/null 2>&1
	systemctl start proftpd | $LOG
	check_result $? "proftpd start failed"
fi

#----------------------------------------------------------#
#               Configure MariaDB / MySQL                  #
#----------------------------------------------------------#

if [ "$mysql" = 'yes' ] || [ "$mysql8" = 'yes' ]; then
	[ "$mysql" = 'yes' ] && mysql_type="MariaDB" || mysql_type="MySQL"
	echo "[ * ] Configuring $mysql_type database server..."
	mycnf="my-small.cnf"
	if [ $memory -gt 1200000 ]; then
		mycnf="my-medium.cnf"
	fi
	if [ $memory -gt 3900000 ]; then
		mycnf="my-large.cnf"
	fi

	if [ "$mysql_type" = 'MariaDB' ]; then
		# Run mysql_install_db
		mysql_install_db | $LOG
	fi

	# Remove symbolic link
	rm -f /etc/mysql/my.cnf
	# Configuring MariaDB
	cp -f $HESTIA_INSTALL_DIR/mysql/$mycnf /etc/mysql/my.cnf

	# Switch MariaDB inclusions to the MySQL
	if [ "$mysql_type" = 'MySQL' ]; then
		sed -i '/query_cache_size/d' /etc/mysql/my.cnf
		sed -i 's|mariadb.conf.d|mysql.conf.d|g' /etc/mysql/my.cnf
	fi

	if [ "$mysql_type" = 'MariaDB' ]; then
		systemctl enable mariadb 2> /dev/null
		systemctl start mariadb | $LOG
		check_result $? "${mysql_type,,} start failed"
	fi

	if [ "$mysql_type" = 'MySQL' ]; then
		systemctl enable mysql 2> /dev/null
		systemctl start mysql | $LOG
		check_result $? "${mysql_type,,} start failed"
	fi

	# Securing MariaDB/MySQL installation
	mpass=$(gen_pass)
	echo -e "[client]\npassword='$mpass'\n" > /root/.my.cnf
	chmod 600 /root/.my.cnf

	if [ -f '/usr/bin/mariadb' ]; then
		mysql_server="mariadb"
	else
		mysql_server="mysql"
	fi
	# Alter root password
	$mysql_server -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$mpass'; FLUSH PRIVILEGES;"
	if [ "$mysql_type" = 'MariaDB' ]; then
		# Allow mysql access via socket for startup
		$mysql_server -e "UPDATE mysql.global_priv SET priv=json_set(priv, '$.password_last_changed', UNIX_TIMESTAMP(), '$.plugin', 'mysql_native_password', '$.authentication_string', 'invalid', '$.auth_or', json_array(json_object(), json_object('plugin', 'unix_socket'))) WHERE User='root';"
		# Disable anonymous users
		$mysql_server -e "DELETE FROM mysql.global_priv WHERE User='';"
	else
		$mysql_server -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$mpass';"
		$mysql_server -e "DELETE FROM mysql.user WHERE User='';"
		$mysql_server -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
	fi
	# Drop test database
	$mysql_server -e "DROP DATABASE IF EXISTS test"
	$mysql_server -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
	# Flush privileges
	$mysql_server -e "FLUSH PRIVILEGES;"
fi

#----------------------------------------------------------#
#                    Configure phpMyAdmin                  #
#----------------------------------------------------------#

# Source upgrade.conf with phpmyadmin versions
# shellcheck source=/usr/local/hestia/install/upgrade/upgrade.conf
source $HESTIA/install/upgrade/upgrade.conf

if [ "$mysql" = 'yes' ] || [ "$mysql8" = 'yes' ]; then
	# Display upgrade information
	echo "[ * ] Installing phpMyAdmin version v$pma_v..."

	# Download latest phpmyadmin release
	yum -y install phpMyAdmin
	check_result $? "Package installation failed, check log file for more details."

	## Create copy of config file
	#cp -f $HESTIA_INSTALL_DIR/phpmyadmin/config.inc.php /etc/phpmyadmin/
	#mkdir -p /var/lib/phpmyadmin/tmp
	#chmod 770 /var/lib/phpmyadmin/tmp
	#chown root:www-data /usr/share/phpmyadmin/tmp

	## Set config and log directory
	#sed -i "s|'configFile' => ROOT_PATH . 'config.inc.php',|'configFile' => '/etc/phpmyadmin/config.inc.php',|g" /usr/share/phpmyadmin/libraries/vendor_config.php

	## Create temporary folder and change permission
	#chmod 770 /usr/share/phpmyadmin/tmp
	#chown root:www-data /usr/share/phpmyadmin/tmp

	# Generate blow fish
	blowfish=$(pwgen -s 32 1)
	PMADB=phpmyadmin
	PMAUSER=phpmyadmin
	PMAPASS=$(gen_pass)
	sed -i "s|\$cfg['blowfish_secret'].*|\$cfg['blowfish_secret'] = '$blowfish';|" /etc/phpMyAdmin/config.inc.php
	sed -i "s|\$cfg['Servers'][$i]['controluser'].*|\$cfg['Servers'][$i]['controluser'] = '$PMAUSER';|" /etc/phpMyAdmin/config.inc.php
	sed -i "s|\$cfg['Servers'][$i]['controlpass'].*|\$cfg['Servers'][$i]['controlpass'] = '$PMAPASS';|" /etc/phpMyAdmin/config.inc.php
	sed -i "s|\$cfg['Servers'][\$i]['pmadb']|\$cfg['Servers'][\$i]['pmadb'] = '$PMADB';|" /etc/phpMyAdmin/config.inc.php

	write_config_value "DB_PMA_ALIAS" $PMADB
	$HESTIA/bin/v-change-sys-db-alias 'pma' "phpmyadmin"

	#DROP USER and TABLE
	mysql -uroot << EOF
DROP USER '$PMAUSER'@'localhost';
DROP DATABASE $PMADB;
FLUSH PRIVILEGES;
CREATE USER '$PMAUSER'@'localhost' IDENTIFIED BY '$PASS';
CREATE DATABASE $PMADB;
USE $PMADB;
GRANT USAGE ON $PMADB.* TO '$PMAUSER'@'localhost' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON $PMADB.* TO '$PMAUSER'@'localhost';
FLUSH PRIVILEGES;
EOF

	#MYSQL DB and TABLES ADDITION
	mysql -uroot < /usr/share/phpMyAdmin/sql/create_tables.sql
fi

#----------------------------------------------------------#
#                   Configure PostgreSQL                   #
#----------------------------------------------------------#

if [ "$postgresql" = 'yes' ]; then
	echo "[ * ] Configuring PostgreSQL database server..."
	ppass=$(gen_pass)
	cp -f $HESTIA_INSTALL_DIR/postgresql/pg_hba.conf /etc/postgresql/*/main/
	systemctl restart postgresql
	sudo -iu postgres psql -c "ALTER USER postgres WITH PASSWORD '$ppass'" > /dev/null 2>&1

	mkdir -p /etc/phppgadmin/
	mkdir -p /usr/share/phppgadmin/

	wget --retry-connrefused --quiet https://github.com/hestiacp/phppgadmin/releases/download/v$pga_v/phppgadmin-v$pga_v.tar.gz
	tar xzf phppgadmin-v$pga_v.tar.gz -C /usr/share/phppgadmin/

	cp -f $HESTIA_INSTALL_DIR/pga/config.inc.php /etc/phppgadmin/

	ln -s /etc/phppgadmin/config.inc.php /usr/share/phppgadmin/conf/

	# Configuring phpPgAdmin
	if [ "$apache" = 'yes' ]; then
		cp -f $HESTIA_INSTALL_DIR/pga/phppgadmin.conf /etc/httpd/conf.d/phppgadmin.inc
	fi

	rm phppgadmin-v$pga_v.tar.gz
	write_config_value "DB_PGA_ALIAS" "phppgadmin"
	$HESTIA/bin/v-change-sys-db-alias 'pga' "phppgadmin"
fi

#----------------------------------------------------------#
#                      Configure Bind                      #
#----------------------------------------------------------#

if [ "$named" = 'yes' ]; then
	echo "[ * ] Configuring Bind DNS server..."
	cp -f $HESTIA_INSTALL_DIR/bind/named.conf /etc/
	cp -f $HESTIA_INSTALL_DIR/bind/named.conf.options /etc/
	chown root:named /etc/named.conf
	chown root:named /etc/named.conf.options
	chown named:named /var/cache/bind
	chmod 640 /etc/named.conf
	chmod 640 /etc/named.conf.options
	systemctl enable named > /dev/null 2>&1
	systemctl start named
	check_result $? "named start failed"

	# Workaround for OpenVZ/Virtuozzo
	if [ -e "/proc/vz/veinfo" ] && [ -e "/etc/rc.local" ]; then
		sed -i "s/^exit 0/systemctl restart named \nexit 0/" /etc/rc.local
	fi
fi

#----------------------------------------------------------#
#                      Configure Exim                      #
#----------------------------------------------------------#

if [ "$exim" = 'yes' ]; then
	echo "[ * ] Configuring Exim mail server..."
	gpasswd -a exim mail > /dev/null 2>&1
	exim_version=$(exim --version 2>/dev/null | head -1 | awk '{print $3}' | cut -f -2 -d .)
	# if Exim version > 4.9.4 or greater!
	if ! version_ge "4.9.4" "$exim_version"; then
		# Ubuntu 22.04 (Jammy) uses Exim 4.95 instead but config works with Exim4.94
		cp -f $HESTIA_INSTALL_DIR/exim/exim4.conf.4.95.template /etc/exim/exim.conf.template
	else
		cp -f $HESTIA_INSTALL_DIR/exim/exim4.conf.template /etc/exim/exim.conf.template
	fi
	cp -f $HESTIA_INSTALL_DIR/exim/dnsbl.conf /etc/exim/
	cp -f $HESTIA_INSTALL_DIR/exim/spam-blocks.conf /etc/exim/
	cp -f $HESTIA_INSTALL_DIR/exim/limit.conf /etc/exim/
	cp -f $HESTIA_INSTALL_DIR/exim/system.filter /etc/exim/
	touch /etc/exim/white-blocks.conf

	if [ "$spamd" = 'yes' ]; then
		sed -i "s/#SPAM/SPAM/g" /etc/exim/exim.conf.template
	fi
	if [ "$clamd" = 'yes' ]; then
		sed -i "s/#CLAMD/CLAMD/g" /etc/exim/exim.conf.template
		gpasswd -a exim virusgroup
	fi

	# Generate SRS KEY If not support just created it will get ignored anyway
	srs=$(gen_pass)
	echo $srs > /etc/exim/srs.conf
	chmod 640 /etc/exim/srs.conf
	chmod 640 /etc/exim/exim.conf.template
	chown root:exim /etc/exim/srs.conf

	rm -rf /etc/exim/domains
	mkdir -p /etc/exim/domains

	#rm -f /etc/alternatives/mta
	#ln -s /usr/sbin/exim4 /etc/alternatives/mta
	systemctl enable exim > /dev/null 2>&1
	systemctl start exim | $LOG
	check_result $? "exim4 start failed"
fi

#----------------------------------------------------------#
#                     Configure Dovecot                    #
#----------------------------------------------------------#

if [ "$dovecot" = 'yes' ]; then
	echo "[ * ] Configuring Dovecot POP/IMAP mail server..."
	gpasswd -a dovecot mail > /dev/null 2>&1
	cp -rf $HESTIA_COMMON_DIR/dovecot /etc/
	cp -f $HESTIA_INSTALL_DIR/logrotate/dovecot /etc/logrotate.d/
	rm -f /etc/dovecot/conf.d/15-mailboxes.conf
	chown -R root:root /etc/dovecot*

	#Alter config for 2.2
	version=$(dovecot --version | cut -f -2 -d .)
	if [ "$version" = "2.2" ]; then
		echo "[ * ] Downgrade dovecot config to sync with 2.2 settings"
		sed -i 's|#ssl_dh_parameters_length = 4096|ssl_dh_parameters_length = 4096|g' /etc/dovecot/conf.d/10-ssl.conf
		sed -i 's|ssl_dh = </etc/ssl/dhparam.pem|#ssl_dh = </etc/ssl/dhparam.pem|g' /etc/dovecot/conf.d/10-ssl.conf
		sed -i 's|ssl_min_protocol = TLSv1.2|ssl_protocols = !SSLv3 !TLSv1 !TLSv1.1|g' /etc/dovecot/conf.d/10-ssl.conf
	fi

	systemctl enable dovecot > /dev/null 2>&1
	systemctl start dovecot | $LOG
	check_result $? "dovecot start failed"
fi

#----------------------------------------------------------#
#                     Configure ClamAV                     #
#----------------------------------------------------------#

if [ "$clamd" = 'yes' ]; then
	gpasswd -a clamav mail > /dev/null 2>&1
	gpasswd -a clamav exim > /dev/null 2>&1
	cp -f $HESTIA_INSTALL_DIR/clamav/clamd.conf /etc/clamd.d/hestia.conf
	update-rc.d clamav-daemon defaults
	echo -ne "[ * ] Installing ClamAV anti-virus definitions... "
	echo
	systemctl enable clamd@hestia.service clamav-freshclam > /dev/null 2>&1
	systemctl start clamd@hestia.service clamav-freshclam | $LOG
	check_result $? "clamav start failed"
fi

#----------------------------------------------------------#
#                  Configure SpamAssassin                  #
#----------------------------------------------------------#

if [ "$spamd" = 'yes' ]; then
	echo "[ * ] Configuring SpamAssassin..."
	systemctl enable spamassassin > /dev/null 2>&1
	systemctl start spamassassin | $LOG
	check_result $? "spamassassin start failed"
fi

#----------------------------------------------------------#
#                    Configure Fail2Ban                    #
#----------------------------------------------------------#

if [ "$fail2ban" = 'yes' ]; then
	echo "[ * ] Configuring fail2ban access monitor..."
	cp -rf $HESTIA_INSTALL_DIR/fail2ban /etc/
	cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h

[sshd]
enabled = true

[hestia]
enabled = true
filter  = hestia
logpath = /var/log/hestia/auth.log

EOF
	if [ "$dovecot" = 'yes' ]; then
		echo "[dovecot]" >> /etc/fail2ban/jail.local
		echo "enabled = true" >> /etc/fail2ban/jail.local
	fi
	if [ "$exim" = 'yes' ]; then
		echo "[exim]" >> /etc/fail2ban/jail.local
		echo "enabled = true" >> /etc/fail2ban/jail.local
	fi
	if [ "$sieve" = 'yes' ]; then
		echo "[sieve]" >> /etc/fail2ban/jail.local
		echo "enabled = true" >> /etc/fail2ban/jail.local
	fi
	if [ "$vsftpd" = 'yes' ]; then
		echo "[vsftpd]" >> /etc/fail2ban/jail.local
		echo "enabled = true" >> /etc/fail2ban/jail.local
	fi
	if [ "$proftpd" = 'yes' ]; then
		echo "[proftpd]" >> /etc/fail2ban/jail.local
		echo "enabled = true" >> /etc/fail2ban/jail.local
	fi

	systemctl enable fail2ban > /dev/null 2>&1
	systemctl start fail2ban | $LOG
	check_result $? "fail2ban start failed"
fi

# Configuring MariaDB/MySQL host
if [ "$mysql" = 'yes' ] || [ "$mysql8" = 'yes' ]; then
	$HESTIA/bin/v-add-database-host mysql localhost root $mpass
fi

# Configuring PostgreSQL host
if [ "$postgresql" = 'yes' ]; then
	$HESTIA/bin/v-add-database-host pgsql localhost postgres $ppass
fi

#----------------------------------------------------------#
#                       Install Roundcube                  #
#----------------------------------------------------------#

# Min requirements Dovecot + Exim + Mysql
if ([ "$mysql" == 'yes' ] || [ "$mysql8" == 'yes' ]) && [ "$dovecot" == "yes" ]; then
	echo "[ * ] Installing Roundcube..."
	$HESTIA/bin/v-add-sys-roundcube
	write_config_value "WEBMAIL_ALIAS" "webmail"
else
	write_config_value "WEBMAIL_ALIAS" ""
	write_config_value "WEBMAIL_SYSTEM" ""
fi

#----------------------------------------------------------#
#                     Install Sieve                        #
#----------------------------------------------------------#

# Min requirements Dovecot + Exim + Mysql + Roundcube
if [ "$sieve" = 'yes' ]; then
	# Folder paths
	RC_INSTALL_DIR="/var/lib/roundcube"
	RC_CONFIG_DIR="/etc/roundcube"

	echo "[ * ] Installing Sieve Mail Filter..."

	# dovecot.conf install
	sed -i "s/namespace/service stats \{\n  unix_listener stats-writer \{\n    group = mail\n    mode = 0660\n    user = dovecot\n  \}\n\}\n\nnamespace/g" /etc/dovecot/dovecot.conf

	# Dovecot conf files
	#  10-master.conf
	sed -i -E -z "s/  }\n  user = dovecot\n}/  \}\n  unix_listener auth-master \{\n    group = mail\n    mode = 0660\n    user = dovecot\n  \}\n  user = dovecot\n\}/g" /etc/dovecot/conf.d/10-master.conf
	#  15-lda.conf
	sed -i "s/\#mail_plugins = \\\$mail_plugins/mail_plugins = \$mail_plugins quota sieve\n  auth_socket_path = \/var\/run\/dovecot\/auth-master/g" /etc/dovecot/conf.d/15-lda.conf
	#  20-imap.conf
	sed -i "s/mail_plugins = quota imap_quota/mail_plugins = quota imap_quota imap_sieve/g" /etc/dovecot/conf.d/20-imap.conf

	# Replace dovecot-sieve config files
	cp -f $HESTIA_COMMON_DIR/dovecot/sieve/* /etc/dovecot/conf.d

	# Dovecot default file install
	echo -e "require [\"fileinto\"];\n# rule:[SPAM]\nif header :contains \"X-Spam-Flag\" \"YES\" {\n    fileinto \"INBOX.Spam\";\n}\n" > /etc/dovecot/sieve/default

	# exim4 install
	sed -i "s/\stransport = local_delivery/ transport = dovecot_virtual_delivery/" /etc/exim4/exim4.conf.template
	sed -i "s/address_pipe:/dovecot_virtual_delivery:\n  driver = pipe\n  command = \/usr\/lib\/dovecot\/dovecot-lda -e -d \${extract{1}{:}{\${lookup{\$local_part}lsearch{\/etc\/exim4\/domains\/\${lookup{\$domain}dsearch{\/etc\/exim4\/domains\/}}\/accounts}}}}@\${lookup{\$domain}dsearch{\/etc\/exim4\/domains\/}}\n  delivery_date_add\n  envelope_to_add\n  return_path_add\n  log_output = true\n  log_defer_output = true\n  user = \${extract{2}{:}{\${lookup{\$local_part}lsearch{\/etc\/exim4\/domains\/\${lookup{\$domain}dsearch{\/etc\/exim4\/domains\/}}\/passwd}}}}\n  group = mail\n  return_output\n\naddress_pipe:/g" /etc/exim4/exim4.conf.template

	if [ -d "/var/lib/roundcube" ]; then
		# Modify Roundcube config
		mkdir -p $RC_CONFIG_DIR/plugins/managesieve
		cp -f $HESTIA_COMMON_DIR/roundcube/plugins/config_managesieve.inc.php $RC_CONFIG_DIR/plugins/managesieve/config.inc.php
		ln -s $RC_CONFIG_DIR/plugins/managesieve/config.inc.php $RC_INSTALL_DIR/plugins/managesieve/config.inc.php
		chown -R root:www-data $RC_CONFIG_DIR/
		chmod 751 -R $RC_CONFIG_DIR
		chmod 644 $RC_CONFIG_DIR/*.php
		chmod 644 $RC_CONFIG_DIR/plugins/managesieve/config.inc.php
		sed -i "s/\"archive\"/\"archive\", \"managesieve\"/g" $RC_CONFIG_DIR/config.inc.php
	fi

	# Restart Dovecot and exim4
	systemctl restart dovecot > /dev/null 2>&1
	systemctl restart exim > /dev/null 2>&1
fi

#----------------------------------------------------------#
#                       Configure API                      #
#----------------------------------------------------------#

if [ "$api" = "yes" ]; then
	# Keep legacy api enabled until transition is complete
	write_config_value "API" "yes"
	write_config_value "API_SYSTEM" "1"
	write_config_value "API_ALLOWED_IP" ""
else
	write_config_value "API" "no"
	write_config_value "API_SYSTEM" "0"
	write_config_value "API_ALLOWED_IP" ""
	$HESTIA/bin/v-change-sys-api disable
fi

#----------------------------------------------------------#
#                  Configure File Manager                  #
#----------------------------------------------------------#

echo "[ * ] Configuring File Manager..."
$HESTIA/bin/v-add-sys-filemanager quiet

#----------------------------------------------------------#
#                  Configure dependencies                  #
#----------------------------------------------------------#

echo "[ * ] Configuring PHP dependencies..."
$HESTIA/bin/v-add-sys-dependencies quiet

echo "[ * ] Installing Rclone..."
yum -y install rclone | $LOG
check_result $? "Package installation failed, check log file for more details."

#----------------------------------------------------------#
#                   Configure IP                           #
#----------------------------------------------------------#

# Configuring system IPs
echo "[ * ] Configuring System IP..."
$HESTIA/bin/v-update-sys-ip > /dev/null 2>&1

# Get primary IP
default_nic="$(ip -d -j route show | jq -r '.[] | if .dst == "default" then .dev else empty end')"
# IPv4
primary_ipv4="$(ip -4 -d -j addr show "$default_nic" | jq -r '.[] | select(length > 0) | .addr_info[] | if .scope == "global" then .local else empty end' | head -n1)"
# IPv6
#primary_ipv6="$(ip -6 -d -j addr show "$default_nic" | jq -r '.[] | select(length > 0) | .addr_info[] | if .scope == "global" then .local else empty end' | head -n1)"
ip="$primary_ipv4"
local_ip="$primary_ipv4"

# Configuring firewall
if [ "$iptables" = 'yes' ]; then
	$HESTIA/bin/v-update-firewall
else
	for I in ftp http https ssh smtp smtps submission imap imaps pop3 pop3s; do
		firewall-cmd --add-service=$I
		firewall-cmd --add-service=$I --permanent
	done
	for I in 8083/tcp 12000-12100/tcp ; do
		firewall-cmd --add-port=$I
		firewall-cmd --add-port=$I --permanent
	done
fi

# Get public IP
pub_ipv4="$(curl -fsLm5 --retry 2 --ipv4 https://ip.hestiacp.com/)"
if [ -n "$pub_ipv4" ] && [ "$pub_ipv4" != "$ip" ]; then
	if [ -e /etc/rc.local ]; then
		sed -i '/exit 0/d' /etc/rc.local
	else
		touch /etc/rc.local
	fi

	check_rclocal=$(cat /etc/rc.local | grep "#!")
	if [ -z "$check_rclocal" ]; then
		echo "#!/bin/sh" >> /etc/rc.local
	fi

	# Fix for Proxmox VE containers where hostname is reset to non-FQDN format on reboot
	check_pve=$(uname -r | grep pve)
	if [ ! -z "$check_pve" ]; then
		echo 'hostname=$(hostname --fqdn)' >> /etc/rc.local
		echo ""$HESTIA/bin/v-change-sys-hostname" "'"$hostname"'"" >> /etc/rc.local
	fi
	echo "$HESTIA/bin/v-update-sys-ip" >> /etc/rc.local
	echo "exit 0" >> /etc/rc.local
	chmod +x /etc/rc.local
	systemctl enable rc-local > /dev/null 2>&1
	$HESTIA/bin/v-change-sys-ip-nat "$ip" "$pub_ipv4" > /dev/null 2>&1
	ip="$pub_ipv4"
fi

if [ "$apache" = 'yes' ] && [ "$nginx" = 'yes' ]; then
	echo "<IfModule mod_remoteip.c>" > /etc/httpd/modules/remoteip.conf
	echo "  RemoteIPHeader X-Real-IP" >> /etc/httpd/modules/remoteip.conf
	if [ "$local_ip" != "127.0.0.1" ] && [ "$pub_ipv4" != "127.0.0.1" ]; then
		echo "  RemoteIPInternalProxy 127.0.0.1" >> /etc/httpd/modules/remoteip.conf
	fi
	if [ -n "$local_ip" ] && [ "$local_ip" != "$pub_ipv4" ]; then
		echo "  RemoteIPInternalProxy $local_ip" >> /etc/httpd/modules/remoteip.conf
	fi
	if [ -n "$pub_ipv4" ]; then
		echo "  RemoteIPInternalProxy $pub_ipv4" >> /etc/httpd/modules/remoteip.conf
	fi
	echo "</IfModule>" >> /etc/httpd/modules/remoteip.conf
	sed -i "s/LogFormat \"%h/LogFormat \"%a/g" /etc/httpd/conf/httpd.conf
	systemctl restart httpd
fi

# Adding default domain
$HESTIA/bin/v-add-web-domain admin "$servername" "$ip"
check_result $? "can't create $servername domain"

# Adding cron jobs
export SCHEDULED_RESTART="yes"
command="sudo $HESTIA/bin/v-update-sys-queue restart"
$HESTIA/bin/v-add-cron-job 'admin' '*/2' '*' '*' '*' '*' "$command"
systemctl restart cron

command="sudo $HESTIA/bin/v-update-sys-queue daily"
$HESTIA/bin/v-add-cron-job 'admin' '10' '00' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-sys-queue disk"
$HESTIA/bin/v-add-cron-job 'admin' '15' '02' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-sys-queue traffic"
$HESTIA/bin/v-add-cron-job 'admin' '10' '00' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-sys-queue webstats"
$HESTIA/bin/v-add-cron-job 'admin' '30' '03' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-sys-queue backup"
$HESTIA/bin/v-add-cron-job 'admin' '*/5' '*' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-backup-users"
$HESTIA/bin/v-add-cron-job 'admin' '10' '05' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-user-stats"
$HESTIA/bin/v-add-cron-job 'admin' '20' '00' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-sys-rrd"
$HESTIA/bin/v-add-cron-job 'admin' '*/5' '*' '*' '*' '*' "$command"
command="sudo $HESTIA/bin/v-update-letsencrypt-ssl"
min=$(gen_pass '012345' '2')
hour=$(gen_pass '1234567' '1')
$HESTIA/bin/v-add-cron-job 'admin' "$min" "$hour" '*' '*' '*' "$command"

# Enable automatic updates
#$HESTIA/bin/v-add-cron-hestia-autoupdate apt
cat > /etc/cron.daily/hestia-autoupdate.sh <<EOF
#!/bin/bash
. /etc/profile.d/hestia.sh
cd $HESTIA
git fetch
systemctl restart hestia hestia-php hestia-nginx
EOF

# Building initital rrd images
$HESTIA/bin/v-update-sys-rrd

# Enabling file system quota
if [ "$quota" = 'yes' ]; then
	$HESTIA/bin/v-add-sys-quota
fi

# Set backend port
$HESTIA/bin/v-change-sys-port $port > /dev/null 2>&1

# Create default configuration files
$HESTIA/bin/v-update-sys-defaults

# Update remaining packages since repositories have changed
echo -ne "[ * ] Installing remaining software updates..."
yum -y upgrade | $LOG
echo

# Starting Hestia service
systemctl enable hestia
systemctl start hestia
check_result $? "hestia start failed"
chown admin:admin $HESTIA/data/sessions

# Create backup folder and set correct permission
mkdir -p /backup/
chmod 755 /backup/

# Create cronjob to generate ssl
echo "@reboot root sleep 10 && rm /etc/cron.d/hestia-ssl && PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:' && /usr/local/hestia/bin/v-add-letsencrypt-host" > /etc/cron.d/hestia-ssl

#----------------------------------------------------------#
#              Set hestia.conf default values              #
#----------------------------------------------------------#

echo "[ * ] Updating configuration files..."

if [ "$fromvesta" = "yes" ] ; then
	for I in packages templates users ; do
		cp -fr /usr/local/vesta/data/$I/* $HESTIA/data/$I/
	done
fi

BIN="$HESTIA/bin"
source $HESTIA/func/syshealth.sh
syshealth_repair_system_config

$HESTIA/bin/v-list-users | tail -n +3 | awk '{print $1}' | xargs -n 1 v-rebuild-user | $LOG

# Add /usr/local/hestia/bin/ to path variable
echo 'if [ "${PATH#*/usr/local/hestia/bin*}" = "$PATH" ]; then
    . /etc/profile.d/hestia.sh
fi' >> /root/.bashrc

#----------------------------------------------------------#
#                   Hestia Access Info                     #
#----------------------------------------------------------#

# Comparing hostname and IP
host_ip=$(host $servername | head -n 1 | awk '{print $NF}')
if [ "$host_ip" = "$ip" ]; then
	ip="$servername"
fi

echo -e "\n"
echo "===================================================================="
echo -e "\n"

# Sending notification to admin email
echo -e "Congratulations!

You have successfully installed Hestia Control Panel on your server.

Ready to get started? Log in using the following credentials:

	Admin URL:  https://$servername:$port" > $tmpfile
if [ "$host_ip" != "$ip" ]; then
	echo "	Backup URL: https://$ip:$port" >> $tmpfile
fi
echo -e -n " 	Username:   admin
	Password:   $displaypass

Thank you for choosing Hestia Control Panel to power your full stack web server,
we hope that you enjoy using it as much as we do!

Please feel free to contact us at any time if you have any questions,
or if you encounter any bugs or problems:

Documentation:  https://docs.hestiacp.com/
Forum:          https://forum.hestiacp.com/
GitHub:         https://www.github.com/hestiacp/hestiacp

Note: Automatic updates are enabled by default. If you would like to disable them,
please log in and navigate to Server > Updates to turn them off.

Help support the Hestia Control Panel project by donating via PayPal:
https://www.hestiacp.com/donate

--
Sincerely yours,
The Hestia Control Panel development team

Made with love & pride by the open-source community around the world.
" >> $tmpfile

send_mail="$HESTIA/web/inc/mail-wrapper.php"
cat $tmpfile | $send_mail -s "Hestia Control Panel" $email

# Congrats
echo
cat $tmpfile
rm -f $tmpfile

# Add welcome message to notification panel
$HESTIA/bin/v-add-user-notification admin 'Welcome to Hestia Control Panel!' '<p>You are now ready to begin adding <a href="/add/user/">user accounts</a> and <a href="/add/web/">domains</a>. For help and assistance, <a href="https://hestiacp.com/docs/" target="_blank">view the documentation</a> or <a href="https://forum.hestiacp.com/" target="_blank">visit our forum</a>.</p><p>Please <a href="https://github.com/hestiacp/hestiacp/issues" target="_blank">report any issues via GitHub</a>.</p><p class="u-text-bold">Have a wonderful day!</p><p><i class="fas fa-heart icon-red"></i> The Hestia Control Panel development team</p>'

# Clean-up
# Sort final configuration file
sort_config_file

if [ "$interactive" = 'yes' ]; then
	echo "[ ! ] IMPORTANT: The system will now reboot to complete the installation process."
	read -n 1 -s -r -p "Press any key to continue"
	reboot
else
	echo "[ ! ] IMPORTANT: You must restart the system before continuing!"
fi
# EOF
