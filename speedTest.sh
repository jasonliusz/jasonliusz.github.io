#!/bin/bash

# ============================================
# 代理速度比较脚本 for macOS 12（3次平均版）
# 功能：测试两个 HTTP 代理的下载速度（各3次），输出平均耗时并比较快慢
# 调试特性：打印每次执行的 wget 命令，wget 输出直接显示在终端
# 关键修复：所有提示信息输出到 stderr，只将数值输出到 stdout，避免变量污染
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
        echo -e "${YELLOW}⚠️  $1 未安装，正在通过 Homebrew 安装...${NC}" >&2
        if ! command -v brew &> /dev/null; then
            echo -e "${RED}❌ Homebrew 未安装，请先安装 Homebrew：${NC}" >&2
            echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
            exit 1
        fi
        brew install "$1"
        echo -e "${GREEN}✅ $1 安装完成${NC}" >&2
    else
        echo -e "${GREEN}✅ $1 已安装，跳过${NC}" >&2
    fi
}

# ---------- 函数：获取高精度时间戳（兼容 macOS） ----------
get_timestamp() {
    if command -v python3 &> /dev/null; then
        python3 -c "import time; print(time.time())" 2>/dev/null
    else
        date +%s  # 回退到秒级精度
    fi
}

# ---------- 函数：测试单个代理多次，返回平均耗时 ----------
# 说明：所有提示信息输出到 stderr，只有最后平均耗时（纯数字）输出到 stdout
test_proxy_multi() {
    local proxy_url=$1
    local proxy_label=$2
    local total_time=0
    local success_count=0

    # 以下提示信息全部重定向到 stderr，避免被变量捕获
    echo -e "${YELLOW}🔍 测试代理 $proxy_label ($proxy_url) ，共 ${TEST_TIMES} 次...${NC}" >&2

    for i in $(seq 1 $TEST_TIMES); do
        echo -n "   第 $i 次测试：" >&2

        # 构建 wget 命令（用于调试输出）
        local wget_cmd="wget -O /dev/null -e use_proxy=yes -e https_proxy=\"$proxy_url\" --timeout=30 --tries=1 \"$TEST_URL\""
        echo -e "${YELLOW}\n       [调试] 执行命令: $wget_cmd${NC}" >&2

        local start_time=$(get_timestamp)
        
        # 执行 wget，将其所有输出（stdout + stderr）重定向到 stderr，避免被 $() 捕获
        if wget -O /dev/null \
            -e use_proxy=yes \
            -e https_proxy="$proxy_url" \
            --timeout=30 \
            --tries=1 \
            "$TEST_URL" 1>&2; then   # 注意：1>&2 将 wget 的标准输出也送到 stderr
            
            local end_time=$(get_timestamp)
            
            # 计算耗时（使用 bc 或 awk）
            local duration=""
            if command -v bc &> /dev/null; then
                duration=$(echo "$end_time - $start_time" | bc)
            else
                duration=$(awk "BEGIN {print $end_time - $start_time}")
            fi
            
            # 检查 duration 是否为有效数字
            if [[ ! "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo -e " ${RED}耗时计算失败（非数字: $duration）${NC}" >&2
                continue
            fi
            
            total_time=$(echo "$total_time + $duration" | bc)
            success_count=$((success_count + 1))
            echo -e " ${GREEN}成功，耗时 ${duration} 秒${NC}" >&2
        else
            echo -e " ${RED}失败${NC}" >&2
        fi
        echo "" >&2  # 空行分隔每次测试
    done

    if [ $success_count -eq 0 ]; then
        echo -e "${RED}❌ 代理 $proxy_label 所有测试均失败${NC}" >&2
        echo "inf"   # 输出到 stdout，供变量捕获
    else
        local avg_time=$(echo "scale=3; $total_time / $success_count" | bc)
        echo -e "${GREEN}✅ 代理 $proxy_label 平均耗时 ${avg_time} 秒（成功 ${success_count}/${TEST_TIMES} 次）${NC}" >&2
        echo "$avg_time"   # 输出到 stdout，供变量捕获
    fi
}

# ---------- 主流程 ----------
echo "🔧 检查依赖..." >&2
install_if_missing wget

# 检查 bc（macOS 通常自带）
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}⚠️  bc 未安装，尝试通过 Homebrew 安装...${NC}" >&2
    install_if_missing bc
fi

# 检查 python3（用于高精度时间，可选）
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}⚠️  python3 未安装，将使用秒级精度（不影响比较结果）${NC}" >&2
fi

echo "" >&2

# 验证 TEST_URL 是否完整
if [[ -z "$TEST_URL" ]]; then
    echo -e "${RED}❌ 错误：TEST_URL 变量为空，请检查脚本配置。${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}🚀 开始比较代理速度（测试 URL: $TEST_URL，每个代理测试 ${TEST_TIMES} 次）${NC}" >&2
echo "" >&2

# 调用函数，捕获纯数值（stdout）
time1=$(test_proxy_multi "$PROXY1" "PROXY1 (7890)")
time2=$(test_proxy_multi "$PROXY2" "PROXY2 (11087)")

echo "" >&2
echo "========== 结果 ==========" >&2

# 比较两个代理的速度（使用 bc 处理浮点数）
if [[ "$time1" == "inf" ]] && [[ "$time2" == "inf" ]]; then
    echo -e "${RED}❌ 两个代理均测试失败，请检查代理是否可用${NC}" >&2
elif [[ "$time1" == "inf" ]]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均耗时 ${time2} 秒（PROXY1 不可用）${NC}" >&2
elif [[ "$time2" == "inf" ]]; then
    echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均耗时 ${time1} 秒（PROXY2 不可用）${NC}" >&2
else
    # 使用 bc 比较，结果 1 表示 time1 < time2
    if [ $(echo "$time1 < $time2" | bc) -eq 1 ]; then
        echo -e "${GREEN}🏆 较快的代理是：PROXY1 (7890)，平均耗时 ${time1} 秒${NC}" >&2
        echo -e "   PROXY2 平均耗时 ${time2} 秒，慢了 $(echo "$time2 - $time1" | bc) 秒" >&2
    else
        echo -e "${GREEN}🏆 较快的代理是：PROXY2 (11087)，平均耗时 ${time2} 秒${NC}" >&2
        echo -e "   PROXY1 平均耗时 ${time1} 秒，慢了 $(echo "$time1 - $time2" | bc) 秒" >&2
    fi
fi

echo -e "${YELLOW}📌 提示：如需修改代理端口或测试次数，请编辑 GitHub 上的 speedTest.sh 文件。${NC}" >&2
