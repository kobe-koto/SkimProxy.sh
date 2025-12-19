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

PORT_RANGE=$2
DEST_SERVER_PORT=$1

# run empty check
if [[ -z "$DEST_SERVER_PORT" || -z "$PORT_RANGE" ]]; then
  echo -e "${RED_BG}[ERROR] Missing arguments.${NORMAL} Usage: bash porthop.sh <DEST_SERVER_PORT> <PORT_RANGE>"
  exit 1
fi

# Function to detect the package manager and install missing packages
install_packages() {
  if command -v apk &> /dev/null; then
    apk update && apk add nftables
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y nftables
  elif command -v pacman &> /dev/null; then
    pacman -Syu --noconfirm nftables
  elif command -v dnf &> /dev/null; then
    dnf install -y nftables
  elif command -v zypper &> /dev/null; then
    zypper install -y nftables
  elif command -v yum &> /dev/null; then
    yum install -y nftables
  else
    echo -e "${RED_BG}[ERROR] Unsupported package manager.${NORMAL} Please install nftables manually."
    exit 1
  fi
}

if ! command -v nft &> /dev/null; then
  echo -e "${GREEN_BG}[Requirements] Installing nftables...${NORMAL}"
  install_packages
fi

# enable the nft
init_system=$(cat /proc/1/comm)
if [[ "$init_system" == "systemd" ]]; then
  systemctl enable nftables
  systemctl start nftables
elif [[ "$init_system" == "init" || "$init_system" == "openrc" ]]; then
  rc-update add nftables default
  rc-service nftables start
else
  echo -e "${RED_BG}Unsupported init system: $init_system.${NORMAL}"
  exit 1
fi

# generate porthop nftables rules
mkdir -p /etc/skim-porthop/nft/
cat <<EOF > /etc/skim-porthop/nft/${DEST_SERVER_PORT}.nft
table inet skim-porthop_${DEST_SERVER_PORT} {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    udp dport $PORT_RANGE counter redirect to :$DEST_SERVER_PORT
  }
}
EOF

# detect if the "include "/etc/skim-porthop/nft/*.nft" exists in /etc/nftables.conf, if not add it
if ! grep -q 'include "/etc/skim-porthop/nft/\*.nft"' /etc/nftables.conf; then
  echo 'include "/etc/skim-porthop/nft/*.nft"' >> /etc/nftables.conf
fi

# load the new nftables rules
nft -f /etc/skim-porthop/nft/${DEST_SERVER_PORT}.nft
echo -e "${GREEN_BG}[Success] Port hopping rules added for destination port ${DEST_SERVER_PORT} in range ${PORT_RANGE}.${NORMAL}"
