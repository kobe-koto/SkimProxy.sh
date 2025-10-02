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
  x86_64) arch="amd64" ;;
  aarch64) arch="arm64" ;;
  *) echo -e "${RED_BG}Unsupported architecture: $cpu_arch${NORMAL}"; exit 1 ;;
esac

# Accept IP argument or fetch the IP from Cloudflare CDN trace
if [ -z "$3" ] || [ "$3" = "auto" ]; then
  ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -4 | grep -oP '(?<=ip=).*')
  if [ -z "$ip" ]; then
    ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -6 | grep -oP '(?<=ip=).*')
  fi
  if echo "$ip" | grep -q ':'; then
    ip="[$ip]"
  fi
else 
  ip=$3
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
    apk update && apk add curl jq tar xz
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y curl jq tar xz-utils
  elif command -v pacman &> /dev/null; then
    pacman -Syu --noconfirm curl jq tar xz
  elif command -v dnf &> /dev/null; then
    dnf install -y curl jq tar xz
  elif command -v zypper &> /dev/null; then
    zypper install -y curl jq tar xz
  elif command -v yum &> /dev/null; then
    yum install -y curl jq tar xz
  else
    echo -e "${RED_BG}[ERROR] Unsupported package manager.${NORMAL} Please install curl, jq, tar, and manually."
    exit 1
  fi
}

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

# Install required tools if missing
for tool in curl jq tar xz; do
  if ! command -v "$tool" &> /dev/null; then
    echo -e "${GREEN_BG}[Requirements] Installing missing dependencies...${NORMAL}"
    install_packages
    break
  fi
done

# Get the latest release version from GitHub API
get_latest_version() {
  latest_version=$(curl -s "https://api.github.com/repos/9seconds/mtg/releases/latest" | jq -r .tag_name)
  if [[ "$latest_version" == "null" ]]; then
    echo -e "${RED_BG}Unable to fetch latest version from GitHub.${NORMAL}"
    echo "v2.1.7"
  else
    echo "$latest_version"
  fi
}
# Download MTG Core
download_mtg_core() {
  ### Install MTG core
  # - Create target directory
  mkdir -p /opt/skim-mtg/
  # - Purify version code
  pure_version=${version#v}
  # - Construct the download URL
  url="https://github.com/9seconds/mtg/releases/download/${version}/mtg-${pure_version}-linux-${arch}.tar.gz"
  # - Download and extract
  echo -e "${GREEN_BG}Downloading ${url}...${NORMAL}"
  curl -s -L -o mtg.tar.xz "$url"
  tar -xvf mtg.tar.xz -C /opt/skim-mtg/ mtg-$pure_version-linux-$arch/mtg --strip-components=1 > /dev/null
  rm -rf mtg.tar.xz
  echo -e "${GREEN_BG}mtg core installed to /opt/skim-mtg/${NORMAL}"
}

# Random Domain Generator, see slices/generate_random_domain.sh
generate_random_domain() {
  local min_len=${1:-6}
  local max_len=${2:-12}

  if (( min_len > max_len )); then
    local temp=$min_len
    min_len=$max_len
    max_len=$temp
  fi

  local tlds=( "com" "net" "org" "io" "dev" "ai" "co" "app" "xyz" "tech" "info" "me" )

  local length_range=$(( max_len - min_len + 1 ))
  local name_length=$(( RANDOM % length_range + min_len ))

  local domain_name
  domain_name=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "$name_length")

  local chosen_tld=${tlds[$(( RANDOM % ${#tlds[@]} ))]}

  echo "${domain_name}.${chosen_tld}"
}

# Set version argument or fallback to latest
if [ -z "$2" ] || [ "$2" = "auto" ]; then
  version=$(get_latest_version)
else
  version="$2"
fi

# Check existing version
if [[ -x "/opt/skim-mtg/mtg" ]]; then
    installed_version="v$("/opt/skim-mtg/mtg" --version | awk '{print $1}')"
    if [[ "$installed_version" == "$version" ]]; then
        echo -e "${GREEN_BG}[Requirements] 9seconds/MTG core ${version} is already installed. Skipping download.${NORMAL}"
    else
        echo -e "${GREEN_BG}[Requirements] Installed version ($installed_version) differs from requested ($version). Updating...${NORMAL}"
        download_mtg_core
    fi
else
    echo -e "${GREEN_BG}[Requirements] 9seconds/MTG core not found. Proceeding with installation...${NORMAL}"
  download_mtg_core
fi

### Generate config
# Accept port argument or generate a random port
if [ -z "$1" ] || [ "$1" = "auto" ]; then
  port=$((RANDOM % 50000 + 10000))
else
  port=$1
fi

# Make config folder for the spec port
mkdir -p /opt/skim-mtg/$port
# Generate password
password=$(/opt/skim-mtg/mtg generate-secret $(generate_random_domain 5 16))

# Print the config
echo -e "${GREEN_BG}Using address${NORMAL}: $ip:$port"
echo -e "${GREEN_BG}Generated password${NORMAL}: $password"

# Create mtg config
  cat <<EOF > /opt/skim-mtg/$port/config.toml
secret = "${password}"
bind-to = "0.0.0.0:${port}"
EOF

# Create system service based on init system
echo -e "${GREEN_BG}Installing system service...${NORMAL}"
init_system=$(cat /proc/1/comm)
if [[ "$init_system" == "systemd" ]]; then
  cat <<EOF > /etc/systemd/system/mtg-${port}.service
[Unit]
Description=9seconds/mtg - MTProto proxy server - on :$port
Documentation=https://github.com/9seconds/mtg
After=network.target

[Service]
ExecStart=/opt/skim-mtg/mtg run /opt/skim-mtg/$port/config.toml
Restart=always
RestartSec=3
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable mtg-${port}
  systemctl start mtg-${port}
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} systemctl disable --now mtg-${port} && rm /etc/systemd/system/mtg-${port}.service && rm -rf /opt/skim-mtg/$port"

elif [[ "$init_system" == "init" || "$init_system" == "openrc" ]]; then
  cat <<EOF > /etc/init.d/mtg-$port
#!/sbin/openrc-run

name="9seconds/mtg - MTProto proxy - on :$port"
description="9seconds/mtg - MTProto proxy - on :$port"
command="/opt/skim-mtg/mtg"
command_args=" run /opt/skim-mtg/$port/config.toml"
pidfile="/var/run/mtg-$port.pid"
logfile="/var/log/mtg-$port.log"

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

  chmod +x /etc/init.d/mtg-${port}
  rc-update add mtg-${port} default
  rc-service mtg-${port} start
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} rc-update del mtg-${port} default && rc-service mtg-${port} stop && rm /etc/init.d/mtg-${port} && rm -rf /opt/skim-mtg/$port"

else
  echo -e "${RED_BG}Unsupported init system: $init_system.${NORMAL}"
  exit 1
fi

# Generate https://t.me URL
mtg_url="https://t.me/proxy?server=$ip&port=$port&secret=$password"
echo -e "${GREEN_BG}9seconds/MTG t.me URL:${NORMAL} $mtg_url"

echo -e "${GREEN_BG}9seconds/MTG installed.${NORMAL}"
echo -e "${GREEN_BG}Service mtg-${port} has been started.${NORMAL}"

