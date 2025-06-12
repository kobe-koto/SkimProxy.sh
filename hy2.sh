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

undefined

[ v3_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = www.gov.hk
EOF
openssl req -x509 -new -nodes -days 3650 -keyout /opt/skim-hy2/$port/server.key -out /opt/skim-hy2/$port/server.crt -config /opt/skim-hy2/$port/openssl.conf

# Print the config
echo -e "${GREEN_BG}Using address${NORMAL}: $ip:$port"
echo -e "${GREEN_BG}Generated password${NORMAL}: $password"
echo -e "${GREEN_BG}Server CA SHA256${NORMAL}: $(openssl x509 -noout -fingerprint -sha256 -in /opt/skim-hy2/$port/server.crt)"

# Create hy2 config
  cat <<EOF > /opt/skim-hy2/$port/config.yaml
listen: :${port}
tls:
  cert: /opt/skim-hy2/${port}/server.crt
  key: /opt/skim-hy2/${port}/server.key
auth:
  type: password
  password: $password
EOF

# Create system service based on init system
echo -e "${GREEN_BG}Installing system service...${NORMAL}"
init_system=$(cat /proc/1/comm)
if [[ "$init_system" == "systemd" ]]; then
  cat <<EOF > /etc/systemd/system/hy2-${port}.service
[Unit]
Description=Hysteria 2 Server on :${port}
After=network.target

[Service]
Environment="HYSTERIA_LOG_LEVEL=error"
ExecStart=/opt/skim-hy2/hy2 server -c /opt/skim-hy2/$port/config.yaml
Restart=on-failure
StandardOutput=append:/var/log/hy2-$port.log
StandardError=append:/var/log/hy2-$port.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable hy2-${port}
  systemctl start hy2-${port}
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} systemctl disable --now hy2-${port} && rm /etc/systemd/system/hy2-${port}.service && rm -rf /opt/skim-hy2/$port"

elif [[ "$init_system" == "init" || "$init_system" == "openrc" ]]; then
  cat <<EOF > /etc/init.d/hy2-$port
#!/sbin/openrc-run

name="Hysteria 2 Server on :$port"
description="Hysteria 2 server on :$port"
command="/opt/skim-hy2/hy2"
command_args=" server -c /opt/skim-hy2/$port/config.yaml"
pidfile="/var/run/hy2-$port.pid"
logfile="/var/log/hy2-$port.log"

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

  chmod +x /etc/init.d/hy2-${port}
  rc-update add hy2-${port} default
  rc-service hy2-${port} start
  echo -e "${WHITE_BG}TO REMOVE THIS SERVICE:${NORMAL} rc-update del hy2-${port} default && rc-service hy2-${port} stop && rm /etc/init.d/hy2-${port} && rm -rf /opt/skim-hy2/$port"

else
  echo -e "${RED_BG}Unsupported init system: $init_system.${NORMAL}"
  exit 1
fi

# Generate hy2:// URL
hy2_url="hy2://$(urlencode $password)@$ip:$port/?insecure=1&sni=www.gov.hk#$(urlencode "SkimProxy.sh Hysteria2 $ip:$port")"
# Generate JSON configuration
json_config=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "hysteria2-server",
  "server": "$ip",
  "server_port": $port,
  "password": "$password"
}
EOF
)
echo -e "${GREEN_BG}Hysteria 2 URL:${NORMAL} $hy2_url"
echo -e "${GREEN_BG}JSON configuration:${NORMAL} $json_config"

echo -e "${GREEN_BG}Hysteria 2 installed.${NORMAL}"
echo -e "${GREEN_BG}Service hy2-${port} has been started.${NORMAL}"

