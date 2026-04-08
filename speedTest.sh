#!/bin/bash

# ============================================
# 代理速度比较脚本（基于 wget 输出的网速）
# 功能：测试两个代理的下载速度（各3次），取平均网速（MB/s），比较快慢
# 依赖：wget（自动安装）
# 用法：bash <(curl -fsSL https://raw.githubusercontent.com/jasonliusz/jasonliusz.github.io/master/speedTest.sh)
# ============================================

# ---------- 配置 ----------
PROXY1="http://127.0.0.1:7890"
PROXY2="http://127.0.0.1:11087"
TEST_URL="https://storage.googleapis.com/gcp-public-data-landsat/LC08/01/001/002/LC08_L1GT_001002_20160817_20170322_01_T2/LC08_L1GT_001002_20160817_20170322_01_T2_B1.TIF"
TEST_TIMES=3
# ------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# 安装 wget（如果需要）
if ! command -v wget &> /dev/null; then
    echo -e "${YELLOW}⚠️  wget 未安装，正在通过 Homebrew 安装...${NC}" >&2
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}❌ 请先安装 Homebrew：${NC}" >&2
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
        exit 1
    fi
    brew install wget
    echo -e "${GREEN}✅ wget 安装完成${NC}" >&2
else
    echo -e "${GREEN}✅ wget 已安装${NC}" >&2
fi

# 从 wget 输出中提取平均速度（MB/s）
extract_speed() {
    local output="$1"
    # 匹配类似 "12.3 MB/s" 或 "5.2 KB/s" 的行，取最后一个（最终平均速度）
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

# 测试单个代理，返回平均速度（MB/s）
test_proxy() {
    local proxy_url=$1
    local proxy_label=$2
    local total_speed=0
    local success_count=0

    echo -e "${YELLOW}🔍 测试代理 $proxy_label ($proxy_url) ，共 ${TEST_TIMES} 次...${NC}" >&2

    for i in $(seq 1 $TEST_TIMES); do
        echo -n "   第 $i 次测试：" >&2
        # 临时文件保存 wget 输出
        tmp_out=$(mktemp)
        if wget -O /dev/null \
            -e use_proxy=yes \
            -e https_proxy="$proxy_url" \
            --timeout=30 \
            --tries=1 \
            "$TEST_URL" > "$tmp_out" 2>&1; then
            cat "$tmp_out" >&2   # 显示 wget 输出
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

# 主流程
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
