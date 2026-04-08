#!/bin/bash

# ============================================
# 代理速度比较脚本 for macOS 12（3次平均版）
# 功能：安装 wget（如缺失），通过两个代理分别下载同一文件 3 次，比较平均耗时
# 用法：./compare_proxy.sh
# ============================================

set -e  # 遇到错误立即退出

# ---------- 配置区（请根据实际代理修改）----------
PROXY1="http://127.0.0.1:7890"   # 第一个代理地址
PROXY2="http://127.0.0.1:11087"  # 第二个代理地址
# 测试文件 URL（已换回你指定的 Google Landsat 文件）
TEST_URL="https://storage.googleapis.com/gcp-public-data-landsat/LC08/01/001/002/LC08_L1GT_001002_20160817_20170322_01_T2/LC08_L1GT_001002_20160817_20170322_01_T2_B1.TIF"
# ---------------------------------------------

# 测试次数
TEST_TIMES=3

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------- 1. 检查并安装依赖（幂等性）----------
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}⚠️  $1 未安装，正在通过 Homebrew 安装...${NC}"
        if ! command -v brew &> /dev/null; then
            echo -e "${RED}❌ Homebrew 未安装，请先安装 Homebrew：${NC}"
            echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            exit 1
        fi
        brew install "$1"
        echo -e "${GREEN}✅ $1 安装完成${NC}"
    else
        echo -e "${GREEN}✅ $1 已安装，跳过${NC}"
    fi
}

echo "🔧 检查依赖..."
install_if_missing wget
echo ""

# ---------- 2. 测试单个代理多次，返回平均耗时 ----------
test_proxy_multi() {
    local proxy_url=$1
    local proxy_label=$2
    local total_time=0
    local success_count=0

    echo -e "${YELLOW}🔍 测试代理 $proxy_label ($proxy_url) ，共 ${TEST_TIMES} 次...${NC}"

    for i in $(seq 1 $TEST_TIMES); do
        echo -n "   第 $i 次测试："
        local start_time=$(date +%s.%N)
        # 执行下载，丢弃输出，超时 30 秒，只尝试 1 次
        if wget -O /dev/null \
            -e use_proxy=yes \
            -e https_proxy="$proxy_url" \
            --timeout=30 \
            --tries=1 \
            --quiet \
            "$TEST_URL" 2>/dev/null; then
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            success_count=$((success_count + 1))
            echo -e " ${GREEN}成功，耗时 ${duration} 秒${NC}"
        else
            echo -e " ${RED}失败${NC}"
        fi
    done

    if [ $success_count -eq 0 ]; then
        echo -e "${RED}❌ 代理 $proxy_label 所有测试均失败${NC}"
        echo "inf"
    else
        local avg_time=$(echo "scale=3; $total_time / $success_count" | bc)
        echo -e "${GREEN}✅ 代理 $proxy_label 平均耗时 ${avg_time} 秒（成功 ${success_count}/${TEST_TIMES} 次）${NC}"
        echo "$avg_time"
    fi
}

# ---------- 3. 比较两个代理 ----------
echo -e "${YELLOW}🚀 开始比较代理速度（测试 URL: $TEST_URL，每个代理测试 ${TEST_TIMES} 次）${NC}"
echo ""

time1=$(test_proxy_multi "$PROXY1" "PROXY1 (7890)")
time2=$(test_proxy_multi "$PROXY2" "PROXY2 (11087)")

echo ""
echo "========== 结果 =========="
if [[ "$time1" == "inf" ]] && [[ "$time2" == "inf" ]]; then
    echo -e "${RED}❌ 两个代理均测试失败，请检查代理是否可用${NC}"
elif [[ "$time1" == "inf" ]]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均耗时 ${time2} 秒（PROXY1 不可用）${NC}"
elif [[ "$time2" == "inf" ]]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均耗时 ${time1} 秒（PROXY2 不可用）${NC}"
else
    if (( $(echo "$time1 < $time2" | bc -l) )); then
        echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均耗时 ${time1} 秒${NC}"
        echo -e "   PROXY2 平均耗时 ${time2} 秒，慢了 $(echo "$time2 - $time1" | bc -l) 秒"
    else
        echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均耗时 ${time2} 秒${NC}"
        echo -e "   PROXY1 平均耗时 ${time1} 秒，慢了 $(echo "$time1 - $time2" | bc -l) 秒"
    fi
fi

echo -e "${YELLOW}📌 提示：如果你需要修改代理地址、测试 URL 或测试次数，请直接编辑脚本顶部的配置区。${NC}"
