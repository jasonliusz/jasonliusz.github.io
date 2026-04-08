#!/bin/bash

# ============================================
# 代理速度比较脚本（基于 wget 输出的网速）
# 功能：测试两个代理的下载速度（各3次），取平均网速（MB/s），比较快慢
# 特性：自动安装 Homebrew（使用清华源）和 wget
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/jasonliusz/jasonliusz.github.io/master/speedTest.sh)
# ============================================

# ---------- 配置 ----------
PROXY1="http://127.0.0.1:7890"
PROXY2="http://127.0.0.1:11087"
TEST_URL="https://storage.googleapis.com/gcp-public-data-landsat/LC08/01/001/002/LC08_L1GT_001002_20160817_20170322_01_T2/LC08_L1GT_001002_20160817_20170322_01_T2_B1.TIF"
TEST_TIMES=3
# ------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ---------- 函数：安装 Homebrew（清华镜像源） ----------
install_brew() {
    echo -e "${YELLOW}🔧 Homebrew 未安装，开始安装（使用清华镜像源加速）...${NC}" >&2
    # 设置清华镜像环境变量（用于安装脚本）
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
    # 执行官方安装脚本（非交互模式，避免卡住）
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
    # 配置环境变量（根据芯片架构）
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    # 再次设置已安装的 brew 的镜像源（确保后续操作也走清华）
    brew update --force --quiet
    cd "$(brew --repo)" && git remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git
    cd "$(brew --repo homebrew/core)" && git remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git
    export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles
    echo -e "${GREEN}✅ Homebrew 安装完成（已配置清华源）${NC}" >&2
}

# ---------- 检查并安装 wget（自动安装 Homebrew 如果缺失） ----------
echo "🔧 检查依赖..." >&2

if ! command -v wget &> /dev/null; then
    echo -e "${YELLOW}⚠️  wget 未安装，正在通过 Homebrew 安装...${NC}" >&2
    if ! command -v brew &> /dev/null; then
        install_brew
    fi
    brew install wget
    echo -e "${GREEN}✅ wget 安装完成${NC}" >&2
else
    echo -e "${GREEN}✅ wget 已安装${NC}" >&2
fi

# 确保 bc 存在（macOS 自带，但以防万一）
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}⚠️  bc 未安装，正在通过 Homebrew 安装...${NC}" >&2
    brew install bc
    echo -e "${GREEN}✅ bc 安装完成${NC}" >&2
else
    echo -e "${GREEN}✅ bc 已安装${NC}" >&2
fi

echo "" >&2

# ---------- 从 wget 输出中提取平均速度（MB/s） ----------
extract_speed() {
    local output="$1"
    local speed_line=$(echo "$output" | grep -Eo '[0-9.]+ (MB|KB)/s' | tail -1)
    if [ -z "$speed_line" ]; then
        echo "0"
        return
    fi
    local value=$(echo "$speed_line" | awk '{print $1}')
    local unit=$(echo "$speed_line" | awk '{print $2}')
    if [ "$unit" = "KB/s" ]; then
        value=$(echo "scale=2; $value / 1024" | bc)
    fi
    echo "$value"
}

# ---------- 测试单个代理，返回平均速度（MB/s） ----------
test_proxy() {
    local proxy_url=$1
    local proxy_label=$2
    local total_speed=0
    local success_count=0

    echo -e "${YELLOW}🔍 测试代理 $proxy_label ($proxy_url) ，共 ${TEST_TIMES} 次...${NC}" >&2

    for i in $(seq 1 $TEST_TIMES); do
        echo -n "   第 $i 次测试：" >&2
        tmp_out=$(mktemp)
        if wget -O /dev/null \
            -e use_proxy=yes \
            -e https_proxy="$proxy_url" \
            --timeout=30 \
            --tries=1 \
            "$TEST_URL" > "$tmp_out" 2>&1; then
            cat "$tmp_out" >&2
            speed=$(extract_speed "$(cat "$tmp_out")")
            if [ $(echo "$speed > 0" | bc) -eq 1 ]; then
                total_speed=$(echo "$total_speed + $speed" | bc)
                success_count=$((success_count + 1))
                echo -e " ${GREEN}速度 ${speed} MB/s${NC}" >&2
            else
                echo -e " ${RED}无法解析速度${NC}" >&2
            fi
        else
            cat "$tmp_out" >&2
            echo -e " ${RED}下载失败${NC}" >&2
        fi
        rm -f "$tmp_out"
        echo "" >&2
    done

    if [ $success_count -eq 0 ]; then
        echo -e "${RED}❌ 代理 $proxy_label 所有测试均失败${NC}" >&2
        echo "0"
    else
        avg_speed=$(echo "scale=2; $total_speed / $success_count" | bc)
        echo -e "${GREEN}✅ 代理 $proxy_label 平均速度 ${avg_speed} MB/s（成功 ${success_count}/${TEST_TIMES} 次）${NC}" >&2
        echo "$avg_speed"
    fi
}

# ---------- 主流程 ----------
echo -e "${YELLOW}🚀 开始比较代理速度（每个代理测试 ${TEST_TIMES} 次）${NC}" >&2
echo "" >&2

speed1=$(test_proxy "$PROXY1" "PROXY1 (7890)")
speed2=$(test_proxy "$PROXY2" "PROXY2 (11087)")

echo "" >&2
echo "========== 结果 ==========" >&2

if [ $(echo "$speed1 == 0" | bc) -eq 1 ] && [ $(echo "$speed2 == 0" | bc) -eq 1 ]; then
    echo -e "${RED}❌ 两个代理均测试失败${NC}" >&2
elif [ $(echo "$speed1 == 0" | bc) -eq 1 ]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均速度 ${speed2} MB/s（PROXY1 不可用）${NC}" >&2
elif [ $(echo "$speed2 == 0" | bc) -eq 1 ]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均速度 ${speed1} MB/s（PROXY2 不可用）${NC}" >&2
else
    if [ $(echo "$speed1 > $speed2" | bc) -eq 1 ]; then
        echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均速度 ${speed1} MB/s${NC}" >&2
        echo -e "   PROXY2 平均速度 ${speed2} MB/s，慢了 $(echo "$speed1 - $speed2" | bc) MB/s" >&2
    else
        echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均速度 ${speed2} MB/s${NC}" >&2
        echo -e "   PROXY1 平均速度 ${speed1} MB/s，慢了 $(echo "$speed2 - $speed1" | bc) MB/s" >&2
    fi
fi

echo -e "${YELLOW}📌 提示：可编辑 GitHub 上的 speedTest.sh 修改代理端口或测试次数。${NC}" >&2
