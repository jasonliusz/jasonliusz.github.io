#!/bin/bash

# ============================================
# 代理速度比较脚本 for macOS 12（3次平均版）
# 功能：测试两个 HTTP 代理的下载速度（各3次），输出平均耗时并比较快慢
# 调试特性：打印每次执行的 wget 命令，验证变量，避免 bc 解析错误
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/jasonliusz/jasonliusz.github.io/master/speedTest.sh)
# ============================================

set -e  # 遇到错误立即退出（但子命令失败不会退出，因为已用 if 判断）

# ---------- 配置区 ----------
PROXY1="http://127.0.0.1:7890"   # 代理1（请按需修改）
PROXY2="http://127.0.0.1:11087"  # 代理2（请按需修改）
TEST_URL="https://storage.googleapis.com/gcp-public-data-landsat/LC08/01/001/002/LC08_L1GT_001002_20160817_20170322_01_T2/LC08_L1GT_001002_20160817_20170322_01_T2_B1.TIF"
TEST_TIMES=3                     # 每个代理测试次数
# ----------------------------

# 颜色输出（用于美观）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------- 函数：安装缺失软件（幂等） ----------
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

# ---------- 函数：测试单个代理多次，返回平均耗时 ----------
test_proxy_multi() {
    local proxy_url=$1
    local proxy_label=$2
    local total_time=0
    local success_count=0

    echo -e "${YELLOW}🔍 测试代理 $proxy_label ($proxy_url) ，共 ${TEST_TIMES} 次...${NC}"

    for i in $(seq 1 $TEST_TIMES); do
        echo -n "   第 $i 次测试："

        # 记录开始时间（使用 date 命令，精度到纳秒）
        local start_time=$(date +%s.%N 2>/dev/null || date +%s)  # 兼容不支持 %N 的系统
        # 如果 date 不支持 %N，则 fallback 到秒（macOS 支持 %N？实际上 macOS date 不支持 %N，需要改用 perl 或 python）
        # 更好的方法：使用 $(( $(date +%s) * 1000 )) 毫秒，但为了精度，这里用 python
        if [[ "$start_time" == *"N"* ]] || [[ -z "$start_time" ]]; then
            # macOS 的 date 不支持 %N，使用 python 获取纳秒
            start_time=$(python3 -c "import time; print(time.time())" 2>/dev/null || echo "")
            if [[ -z "$start_time" ]]; then
                # 最终 fallback 到秒
                start_time=$(date +%s)
            fi
        fi

        # 构建 wget 命令（用于调试输出）
        local wget_cmd="wget -O /dev/null -e use_proxy=yes -e https_proxy=\"$proxy_url\" --timeout=30 --tries=1 --quiet \"$TEST_URL\""
        echo -e "${YELLOW}\n       [调试] 执行命令: $wget_cmd${NC}"

        # 执行下载
        if wget -O /dev/null \
            -e use_proxy=yes \
            -e https_proxy="$proxy_url" \
            --timeout=30 \
            --tries=1 \
            --quiet \
            "$TEST_URL" 2>/dev/null; then

            # 记录结束时间
            local end_time=$(date +%s.%N 2>/dev/null || date +%s)
            if [[ "$end_time" == *"N"* ]] || [[ -z "$end_time" ]]; then
                end_time=$(python3 -c "import time; print(time.time())" 2>/dev/null || echo "")
                if [[ -z "$end_time" ]]; then
                    end_time=$(date +%s)
                fi
            fi

            # 计算耗时（使用 bc 或 awk）
            local duration=""
            if command -v bc &> /dev/null; then
                duration=$(echo "$end_time - $start_time" | bc)
            else
                # 如果没有 bc，使用 awk（macOS 通常有 bc，但以防万一）
                duration=$(awk "BEGIN {print $end_time - $start_time}")
            fi

            # 检查 duration 是否为有效数字
            if [[ ! "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo -e " ${RED}耗时计算失败（非数字: $duration）${NC}"
                continue
            fi

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

# ---------- 主流程 ----------
echo "🔧 检查依赖..."
install_if_missing wget

# 额外检查 bc（macOS 默认没有 bc？实际上 macOS 自带 bc，但旧版本可能没有）
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}⚠️  bc 未安装，尝试通过 Homebrew 安装...${NC}"
    install_if_missing bc
fi

# 检查 python3（用于高精度时间，可选）
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️  python3 未安装，将使用秒级精度（不影响比较结果）${NC}"
fi

echo ""

# 验证 TEST_URL 是否完整
if [[ -z "$TEST_URL" ]]; then
    echo -e "${RED}❌ 错误：TEST_URL 变量为空，请检查脚本配置。${NC}"
    exit 1
fi

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

echo -e "${YELLOW}📌 提示：如需修改代理端口或测试次数，请编辑 GitHub 上的 speedTest.sh 文件。${NC}"
