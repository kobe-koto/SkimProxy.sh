# SkimProxy.sh

SkimProxy.sh is a minimalistic Bash-based toolchain to deploy proxy servers with as little code as possible. No bloat, just results.

## ⚠️ Warning

- Only tested on **Debian 12** (Minimal), **Alpine Linux** Latest (Virtual).
- Assumes a standard Linux environment with `bash`, `wget`, and basic utilities available.
- Assumes a functional human brain or at least an 8b LLM.

## 📦 Usage

Each argument is optional. Use `"auto"` to let the script decide, or leave all blank to use full defaults as below:

- **Port**: random between `10000–60000`
- **Version**: latest release
- **Password**: `openssl rand -base64 16`

### ⚡ Shadowsocks-Rust

- **Cipher**: defaults to `2022-blake3-aes-128-gcm`
  when `Cipher` = `2022-blake3-aes-256-gcm`, `password` = `openssl rand -base64 32`
  see https://shadowsocks.org/doc/aead.html
  for SIP022 (aka. SS2022) see https://shadowsocks.org/doc/sip022.html

```bash
wget https://skimproxy.pages.dev/ssserver.sh -qO ssserver.sh && bash ssserver.sh <port> <cipher> <version> <hostname>
```

Minimal:

```bash
wget https://skimproxy.pages.dev/ssserver.sh -qO ssserver.sh && bash ssserver.sh
```

### ⚡ Hysteria 2

```bash
wget https://skimproxy.pages.dev/hy2.sh -qO hy2.sh && bash hy2.sh <port> <version> <hostname>
```

Minimal:

```bash
wget https://skimproxy.pages.dev/hy2.sh -qO hy2.sh && bash hy2.sh
```

### ⚡ 9seconds/mtg MTProxy Server written in Go

```bash
wget https://skimproxy.pages.dev/mtg.sh -qO mtg.sh && bash mtg.sh <port> <version> <hostname>
```

Minimal:

```bash
wget https://skimproxy.pages.dev/mtg.sh -qO mtg.sh && bash mtg.sh
```

### 🚀 Enable BBR + FQ_PIE
### Port Hopping with nftables

*umm, take care of port range overlapping yourself...*

```bash
wget https://skimproxy.pages.dev/porthop.sh -qO porthop.sh && bash porthop.sh <DEST_SERVER_PORT> <PORT_RANGE>
```


```bash
echo "net.core.default_qdisc=fq_pie" >> /etc/sysctl.conf && \
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf && \
sysctl -p
```
