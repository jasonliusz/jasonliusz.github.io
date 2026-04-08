#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或通过 sudo 执行此脚本。${NC}"
    exit 1
fi

# 检查必要命令
for cmd in curl systemctl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}未找到命令: $cmd，请先安装。${NC}"
        exit 1
    fi
done

echo -e "${GREEN}开始优化 TCP 设置...${NC}"

# 备份原有 sysctl 配置
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

# 追加优化参数（如果不存在则添加）
SYSCTL_CONF="/etc/sysctl.d/99-xray.conf"
cat > $SYSCTL_CONF <<EOF
# Xray TCP 优化参数
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

# 应用 sysctl 配置
sysctl -p $SYSCTL_CONF
echo -e "${GREEN}TCP 优化已完成并生效。${NC}"

echo -e "${GREEN}开始安装 Xray...${NC}"
# 官方安装脚本
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "${GREEN}Xray 安装完成，配置服务自启动...${NC}"
systemctl enable xray
systemctl daemon-reload

# 备份原有配置
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
if [ -f "$CONFIG_FILE" ]; then
    mv "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}已备份原有 config.json${NC}"
fi

# 写入新配置
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

# 修正配置文件权限（xray 服务通常以 xray 用户运行）
chown -R xray:xray "$CONFIG_DIR"
chmod 644 "$CONFIG_FILE"

echo -e "${GREEN}配置文件已写入: $CONFIG_FILE${NC}"

# 检查端口 443 是否被占用
if ss -tlnp | grep -q ':443 '; then
    echo -e "${YELLOW}警告: 端口 443 已被占用，Xray 可能无法启动。请检查并释放端口。${NC}"
fi

# 重启 Xray 服务以应用配置
systemctl restart xray
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray 服务已成功启动。${NC}"
else
    echo -e "${RED}Xray 服务启动失败，请检查日志: journalctl -u xray -f${NC}"
    exit 1
fi

echo -e "${GREEN}全部完成！Xray 已安装并运行，配置已生效。${NC}"
