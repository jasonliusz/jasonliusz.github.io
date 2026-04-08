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

# 安装依赖（幂等）
echo -e "${GREEN}更新软件源并安装必要依赖 (curl, unzip, wget)...${NC}"
apt-get update -qq
apt-get install -y curl unzip wget

# 检查必要命令
for cmd in curl systemctl wget; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}未找到命令: $cmd，请手动安装。${NC}"
        exit 1
    fi
done

# ==================== TCP 优化（幂等） ====================
echo -e "${GREEN}检查并优化 TCP 设置...${NC}"
SYSCTL_CONF="/etc/sysctl.d/99-xray.conf"
cat > /tmp/99-xray.conf.new <<EOF
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

# 比较文件内容
if [ ! -f "$SYSCTL_CONF" ] || ! cmp -s /tmp/99-xray.conf.new "$SYSCTL_CONF"; then
    cp /tmp/99-xray.conf.new "$SYSCTL_CONF"
    sysctl -p "$SYSCTL_CONF"
    echo -e "${GREEN}TCP 优化已更新并生效。${NC}"
else
    echo -e "${GREEN}TCP 优化配置未变化，跳过。${NC}"
fi
rm -f /tmp/99-xray.conf.new

# ==================== 安装 Xray（幂等） ====================
echo -e "${GREEN}开始安装/更新 Xray...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo -e "${GREEN}确保 Xray 服务自启动...${NC}"
systemctl enable xray &>/dev/null || true
systemctl daemon-reload

# 确保 xray 用户存在
if ! id -u xray &>/dev/null; then
    echo -e "${YELLOW}xray 用户不存在，正在创建...${NC}"
    useradd -r -s /usr/sbin/nologin xray
fi

# ==================== 配置文件（幂等） ====================
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="$CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"

# 生成新配置到临时文件
cat > /tmp/config.json.new <<'EOF'
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

# 比较配置文件
NEED_RESTART=false
if [ ! -f "$CONFIG_FILE" ] || ! cmp -s /tmp/config.json.new "$CONFIG_FILE"; then
    # 备份旧配置（如果存在）
    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo -e "${YELLOW}已备份原有配置到 $BACKUP_FILE${NC}"
    fi
    cp /tmp/config.json.new "$CONFIG_FILE"
    chown xray:xray "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}配置文件已更新。${NC}"
    NEED_RESTART=true
else
    echo -e "${GREEN}配置文件未变化，跳过。${NC}"
fi
rm -f /tmp/config.json.new

# 检查端口占用（仅警告）
if ss -tlnp | grep -q ':443 '; then
    echo -e "${YELLOW}警告: 端口 443 已被占用。${NC}"
fi
if ss -tlnp | grep -q ':11087 '; then
    echo -e "${YELLOW}警告: 端口 11087 已被占用。${NC}"
fi

# 重启服务（仅在配置变化时）
if [ "$NEED_RESTART" = true ]; then
    echo -e "${GREEN}重启 Xray 服务以应用新配置...${NC}"
    systemctl restart xray
else
    # 确保服务至少是运行状态
    if ! systemctl is-active --quiet xray; then
        echo -e "${YELLOW}Xray 服务未运行，尝试启动...${NC}"
        systemctl start xray
    else
        echo -e "${GREEN}Xray 服务已在运行，配置未变，无需重启。${NC}"
    fi
fi

# 最终检查服务状态
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}Xray 服务运行正常。${NC}"
else
    echo -e "${RED}Xray 服务启动失败，请检查日志: journalctl -u xray -f${NC}"
    exit 1
fi

sleep 2

# ==================== 代理测试 ====================
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

echo -e "${GREEN}全部完成！Xray 已就绪，HTTP 代理 (127.0.0.1:11087) 测试通过。${NC}"
