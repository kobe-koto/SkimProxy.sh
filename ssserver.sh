#!/bin/bash

GREEN_BG='\033[42;30m'   # Underlined, green background, black text
RED_BG='\033[41;97m'     # Red background (41), white text (97)
WHITE_BG='\033[47;30m'   # White background (47), black text (30)
NORMAL='\033[0m'         # Reset formatting

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED_BG}This script requires root privileges.${NORMAL} Please run as root or use sudo."
  exit 1
fi

# Detect CPU architecture
cpu_arch=$(uname -m)
case "$cpu_arch" in
  x86_64) arch="x86_64" ;;
  aarch64) arch="aarch64" ;;
  *) echo -e "${RED_BG}Unsupported architecture: $cpu_arch${NORMAL}"; exit 1 ;;
esac

# Install GNU grep if BusyBox ver grep found
is_busybox_grep() {
  grep --version 2>&1 | grep -q BusyBox
}
if is_busybox_grep; then
  echo -e "${GREEN_BG}[Requirements] BusyBox grep detected. Installing GNU grep.${NORMAL}"

  if command -v apk >/dev/null; then
    apk add grep
  elif command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y grep
  elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm grep
  else
    echo -e "${RED_BG}[ERROR] Unsupported package manager.${NORMAL} Please install GNU grep manually."
    exit 1
  fi
fi

urlencode() {
    local LANG=C
    local input
    if [ -t 0 ]; then
        input="$1"  # if no pipe, use argument
    else
        input=$(cat)  # if piped, read from stdin
    fi
    local length="${#input}"
    for (( i = 0; i < length; i++ )); do
        c="${input:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            $'\n') printf "%%0A" ;;  # Handle newlines
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    echo
}

# Function to detect the package manager and install missing packages
install_packages() {
  if command -v apk &> /dev/null; then
    apk update && apk add curl jq tar openssl xz
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y curl jq tar openssl xz-utils
  elif command -v pacman &> /dev/null; then
    pacman -Syu --noconfirm curl jq tar openssl xz
  elif command -v dnf &> /dev/null; then
    dnf install -y curl jq tar openssl xz
  elif command -v zypper &> /dev/null; then
    zypper install -y curl jq tar openssl xz
  elif command -v yum &> /dev/null; then
    yum install -y curl jq tar openssl xz
  else
    echo -e "${RED_BG}[ERROR] Unsupported package manager.${NORMAL} Please install curl, jq, tar, and openssl manually."
    exit 1
  fi
}

# Install required tools if missing
for tool in curl jq tar openssl xz; do
  if ! command -v "$tool" &> /dev/null; then
    echo -e "${GREEN_BG}[Requirements] Installing missing dependencies...${NORMAL}"
    install_packages
    break
  fi
done

# Get the latest release version from GitHub API
get_latest_version() {
  latest_version=$(curl -s "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest" | jq -r .tag_name)
  if [[ "$latest_version" == "null" ]]; then
    echo -e "${RED_BG}Unable to fetch latest version from GitHub.${NORMAL}"
    echo "v1.22.0"
  else
    echo "$latest_version"
  fi
}
# Download ss-rust ssserver
download_ss_rust() {
  ### Install ss-rust ssserver
  # - Create target directory
  mkdir -p /opt/skim-ss/
  # - Construct the download URL
  url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/shadowsocks-${version}.${arch}-unknown-linux-musl.tar.xz"
  # - Download and extract
  echo -e "${GREEN_BG}Downloading ${url}...${NORMAL}"
  curl -s -L -o shadowsocks.tar.xz "$url"
  tar -xvf shadowsocks.tar.xz -C /opt/skim-ss/ ssserver > /dev/null
  rm -rf shadowsocks.tar.xz
  echo -e "${GREEN_BG}ss-rust ssserver installed to /opt/skim-ss/${NORMAL}"
}

# Set version argument or fallback to latest
if [ -z "$3" ] || [ "$3" = "auto" ]; then
  version=$(get_latest_version)
else
  version="$3"
fi

# Check existing version
if [[ -x "/opt/skim-ss/ssserver" ]]; then
    installed_version=$("/opt/skim-ss/ssserver" --version | awk '{print $2}')
    if [[ "v$installed_version" == "$version" ]]; then
        echo -e "${GREEN_BG}[Requirements] ss-rust ssserver core ${version} is already installed. Skipping download.${NORMAL}"
    else
        echo -e "${GREEN_BG}[Requirements] Installed version ($installed_version) differs from requested ($version). Updating...${NORMAL}"
        download_ss_rust
    fi
else
    echo -e "${GREEN_BG}[Requirements] ss-rust ssserver core not found. Proceeding with installation...${NORMAL}"
  download_ss_rust
fi

### Generate config
# Accept port argument or generate a random port
if [ -z "$1" ] || [ "$1" = "auto" ]; then
  port=$((RANDOM % 50000 + 10000))
else
  port=$1
fi
# Accept IP argument or fetch the IP from Cloudflare CDN trace
if [ -z "$4" ] || [ "$4" = "auto" ]; then
  ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -4 | grep -oP '(?<=ip=).*')
  if [ -z "$ip" ]; then
    ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -6 | grep -oP '(?<=ip=).*')
  fi
  if echo "$ip" | grep -q ':'; then
    ip="[$ip]"
  fi
else 
  ip=$4
fi
# Accept the cipher arg
if [ -z "$2" ] || [ "$2" = "auto" ]; then
  cipher="2022-blake3-aes-128-gcm"
else
  cipher=$2
fi
# Generate password using openssl
if [ "$cipher" = "2022-blake3-aes-256-gcm" ]; then
  password=$(openssl rand -base64 32)
else
  password=$(openssl rand -base64 16)
fi

# Print the config
echo -e "${GREEN_BG}Using address${NORMAL}: $ip:$port"
echo -e "${GREEN_BG}Using cipher${NORMAL}: $cipher"
echo -e "${GREEN_BG}Generated password${NORMAL}: $password"

# Create system service based on init system
echo -e "${GREEN_BG}Installing system service...${NORMAL}"
init_system=$(cat /proc/1/comm)
if [[ "$init_system" == "systemd" ]]; then
  cat <<EOF > /etc/systemd/system/ssserver-${port}.service
[Unit]
Description=Shadowsocks Rust Server on :${port}
After=network.target

[Service]
ExecStart=/opt/skim-ss/ssserver -U --server-addr [::]:$port --encrypt-method $cipher --password $password
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ssserver-${port}
  systemctl start ssserver-${port}
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} systemctl disable --now ssserver-${port} && rm /etc/systemd/system/ssserver-${port}.service"

elif [[ "$init_system" == "init" || "$init_system" == "openrc" ]]; then
  cat <<EOF > /etc/init.d/ssserver-${port}
#!/sbin/openrc-run

name="Shadowsocks Server on :${port}"
description="Shadowsocks Rust server on :${port}"
command="/opt/skim-ss/ssserver"
command_args=" -U --server-addr [::]:$port --encrypt-method $cipher --password $password"
pidfile="/var/run/ssserver-${port}.pid"

depend() {
    need net
    after firewall
}

start() {
    ebegin "Starting $SERVICE_NAME"
    start-stop-daemon --start --background --make-pidfile --pidfile \$pidfile --exec \$command -- \$command_args
    eend \$?
}

stop() {
    ebegin "Stopping $SERVICE_NAME"
    start-stop-daemon --stop --pidfile \$pidfile
    eend \$?
}

restart() {
    stop
    start
}
EOF

  chmod +x /etc/init.d/ssserver-${port}
  rc-update add ssserver-${port} default
  rc-service ssserver-${port} start
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} rc-update del ssserver-${port} default && rc-service ssserver-${port} stop && rm /etc/init.d/ssserver-${port}"

else
  echo -e "${RED_BG}Unsupported init system: $init_system.${NORMAL}"
  exit 1
fi

# Generate ss:// URL
ss_url="ss://$(echo -n "${cipher}:${password}" | base64 | urlencode)@$ip:$port#$(urlencode "SkimProxy.sh Shadowsocks $cipher $ip:$port")"
# Generate JSON configuration
json_config=$(cat <<EOF
{
  "type": "shadowsocks",
  "tag": "shadowsocks-server",
  "server": "$ip",
  "server_port": $port,
  "method": "$cipher",
  "password": "$password"
}
EOF
)
echo -e "${GREEN_BG}Shadowsocks URL:${NORMAL} $ss_url"
echo -e "${GREEN_BG}JSON configuration:${NORMAL} $json_config"

echo -e "${GREEN_BG}Shadowsocks Rust installed.${NORMAL}"
echo -e "${GREEN_BG}Service ssserver-${port} has been started.${NORMAL}"

