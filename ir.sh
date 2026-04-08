#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或通过 sudo 执行此脚本。${NC}"
    exit 1
fi

# 安装依赖
echo -e "${GREEN}更新软件源并安装必要依赖 (curl, unzip, wget)...${NC}"
apt-get update -qq
apt-get install -y curl unzip wget

# 检查命令
for cmd in curl systemctl wget; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}未找到命令: $cmd，请手动安装。${NC}"
        exit 1
    fi
done

echo -e "${GREEN}开始优化 TCP 设置...${NC}"
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

SYSCTL_CONF="/etc/sysctl.d/99-xray.conf"
cat > $SYSCTL_CONF <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl -p $SYSCTL_CONF
echo -e "${GREEN}TCP 优化已完成并生效。${NC}"

echo -e "${GREEN}开始安装 Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "${GREEN}Xray 安装完成，配置服务自启动...${NC}"
systemctl enable xray
systemctl daemon-reload

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
if [ -f "$CONFIG_FILE" ]; then
    mv "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}已备份原有 config.json${NC}"
fi

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      },
      "settings": {
        "clients": [
          {
            "id": "6a9ec557-582f-46f7-9ee3-eb554bcb9178",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.cloudflare.com:443",
          "serverNames": [
            "www.cloudflare.com"
          ],
          "privateKey": "IO_MLRYBtLXVDOtzi7TZYj_Kjk3svhxPBfmUu657NGU",
          "shortIds": [
            "a1b2c3d4"
          ]
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "timeout": 360
      },
      "port": "11087"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 600,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "bufferSize": 32768
      }
    }
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "https+local://8.8.8.8/dns-query"
    ],
    "queryStrategy": "UseIPv4"
  }
}
EOF

chown -R xray:xray "$CONFIG_DIR"
chmod 644 "$CONFIG_FILE"

echo -e "${GREEN}配置文件已写入: $CONFIG_FILE${NC}"

if ss -tlnp | grep -q ':443 '; then
    echo -e "${YELLOW}警告: 端口 443 已被占用。${NC}"
fi
if ss -tlnp | grep -q ':11087 '; then
    echo -e "${YELLOW}警告: 端口 11087 已被占用。${NC}"
fi

systemctl restart xray
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray 服务已成功启动。${NC}"
else
    echo -e "${RED}Xray 服务启动失败，请检查日志: journalctl -u xray -f${NC}"
    exit 1
fi

sleep 2

echo -e "${GREEN}测试 HTTP 代理 (127.0.0.1:11087) 是否生效...${NC}"
TEST_URL="https://storage.googleapis.com/gcp-public-data-landsat/LC08/01/001/002/LC08_L1GT_001002_20160817_20170322_01_T2/LC08_L1GT_001002_20160817_20170322_01_T2_B1.TIF"

if wget -O /dev/null -e use_proxy=yes -e https_proxy=127.0.0.1:11087 --timeout=10 --tries=1 "$TEST_URL" 2>&1 | grep -q "HTTP request sent"; then
    echo -e "${GREEN}代理测试成功：能够通过 HTTP 代理访问目标地址。${NC}"
else
    if wget -O /dev/null -e use_proxy=yes -e https_proxy=127.0.0.1:11087 --timeout=10 --tries=1 "$TEST_URL"; then
        echo -e "${GREEN}代理测试成功。${NC}"
    else
        echo -e "${RED}代理测试失败。请检查 Xray 日志。${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}全部完成！Xray 已安装并运行，HTTP 代理 (127.0.0.1:11087) 测试通过。${NC}"
