#!/bin/bash
#
# test_simulate.sh - 沙盒模拟测试脚本
# 用于在非Termux环境下测试monitor.sh的核心逻辑
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试结果统计
TESTS_PASSED=0
TESTS_FAILED=0

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# 创建临时测试目录（兼容 Termux）
if [ -d "$HOME/tmp" ]; then
    TMP_BASE="$HOME/tmp"
else
    mkdir -p "$HOME/tmp"
    TMP_BASE="$HOME/tmp"
fi
TEST_DIR=$(mktemp -d -p "$TMP_BASE" 2>/dev/null || mktemp -d)
cd "$TEST_DIR"
echo "测试目录: $TEST_DIR"
echo ""

# 清理函数
cleanup() {
    print_info "清理测试环境..."
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 复制必要文件到测试目录
copy_files() {
    print_info "复制项目文件到测试目录..."
    
    # 获取脚本所在目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 复制必要文件
    cp "$SCRIPT_DIR/bench.c" .
    cp "$SCRIPT_DIR/Makefile" .
    cp "$SCRIPT_DIR/monitor.sh" .
    
    print_pass "文件复制完成"
    echo ""
}

# 模拟termux命令
setup_mock_commands() {
    print_info "设置模拟命令..."
    
    mkdir -p bin
    
    # 模拟 termux-notification
    cat > bin/termux-notification << 'INNEREOF'
#!/bin/bash
echo "[MOCK] termux-notification called with: $@"
INNEREOF
    
    # 模拟 termux-wake-lock
    cat > bin/termux-wake-lock << 'INNEREOF'
#!/bin/bash
echo "[MOCK] termux-wake-lock acquired"
INNEREOF
    
    # 模拟 termux-wake-unlock
    cat > bin/termux-wake-unlock << 'INNEREOF'
#!/bin/bash
echo "[MOCK] termux-wake-unlock released"
INNEREOF
    
    chmod +x bin/*
    export PATH="$TEST_DIR/bin:$PATH"
    
    print_pass "模拟命令设置完成"
    echo ""
}

# 编译bench程序或创建模拟版本
setup_bench() {
    print_test "编译bench程序..."
    
    if command -v clang &> /dev/null || command -v gcc &> /dev/null; then
        make
        print_pass "bench编译成功"
    else
        print_info "未找到编译器,创建模拟bench程序"
        
        # 创建模拟bench程序
        cat > bench << 'INNEREOF'
#!/bin/bash
# 模拟bench程序,返回SIM_BENCH_TIME或默认值
if [ -n "$SIM_BENCH_TIME" ]; then
    echo "$SIM_BENCH_TIME"
else
    echo "120.50"
fi
INNEREOF
        chmod +x bench
        print_pass "模拟bench创建成功"
    fi
    
    echo ""
}

# 测试1: 校准模式
test_calibrate() {
    print_test "测试1: 校准模式"
    
    # 自动输入y来完成校准
    echo "y" | bash monitor.sh calibrate > /dev/null 2>&1
    
    # 检查配置文件是否生成
    if [ -f "config" ]; then
        print_pass "配置文件已生成"
        
        # 检查配置内容
        source config
        
        if [ -n "$BASELINE_US" ] && [ -n "$THRESHOLD_US" ]; then
            print_pass "配置项完整"
            
            # 验证阈值计算
            expected_threshold=$(echo "scale=0; $BASELINE_US * 1.5" | bc)
            if [ "$THRESHOLD_US" == "$expected_threshold" ]; then
                print_pass "阈值计算正确: ${BASELINE_US} * 1.5 = ${THRESHOLD_US}"
            else
                print_fail "阈值计算错误: 期望 $expected_threshold, 实际 $THRESHOLD_US"
            fi
        else
            print_fail "配置项不完整"
        fi
    else
        print_fail "配置文件未生成"
    fi
    
    echo ""
}

# 测试2: 正常负载(不触发报警)
test_normal_load() {
    print_test "测试2: 正常负载(不触发报警)"
    
    # 确保有配置文件
    if [ ! -f "config" ]; then
        echo "y" | bash monitor.sh calibrate > /dev/null 2>&1
    fi
    
    source config
    
    # 设置低于阈值的模拟耗时
    export SIM_BENCH_TIME=$(echo "scale=2; $THRESHOLD_US * 0.8" | bc)
    
    print_info "设置模拟耗时: $SIM_BENCH_TIME μs (阈值: $THRESHOLD_US μs)"
    
    # 启动监控(修改CHECK_INTERVAL为快速测试)
    sed -i 's/CHECK_INTERVAL=60/CHECK_INTERVAL=2/' config
    
    # 后台启动监控
    bash monitor.sh start > /dev/null 2>&1
    
    # 等待几次检查
    sleep 8
    
    # 检查是否触发通知
    if grep -q "\[MOCK\] termux-notification.*CPU 调度延迟过高" monitor.log 2>/dev/null; then
        print_fail "不应触发报警,但检测到通知"
    else
        print_pass "正常负载未触发报警"
    fi
    
    # 停止监控
    bash monitor.sh stop > /dev/null 2>&1
    
    unset SIM_BENCH_TIME
    echo ""
}

# 测试3: 超限负载(触发报警)
test_overload() {
    print_test "测试3: 超限负载(触发报警)"
    
    # 确保有配置文件
    if [ ! -f "config" ]; then
        echo "y" | bash monitor.sh calibrate > /dev/null 2>&1
    fi
    
    source config
    
    # 设置高于阈值的模拟耗时
    export SIM_BENCH_TIME=$(echo "scale=2; $THRESHOLD_US * 2.0" | bc)
    
    print_info "设置模拟耗时: $SIM_BENCH_TIME μs (阈值: $THRESHOLD_US μs)"
    
    # 确保CHECK_INTERVAL较短
    sed -i 's/CHECK_INTERVAL=[0-9]*/CHECK_INTERVAL=2/' config
    
    # 清空日志
    > monitor.log
    
    # 后台启动监控
    bash monitor.sh start > /dev/null 2>&1
    
    # 等待足够时间触发报警(CONSECUTIVE_LIMIT=3, CHECK_INTERVAL=2)
    sleep 8
    
    # 检查日志
    if grep -q "超阈值" monitor.log; then
        print_pass "检测到超阈值记录"
        
        # 检查是否触发报警
        if grep -q "触发报警" monitor.log; then
            print_pass "成功触发报警"
        else
            print_fail "未触发报警"
        fi
    else
        print_fail "未检测到超阈值记录"
    fi
    
    # 停止监控
    bash monitor.sh stop > /dev/null 2>&1
    
    unset SIM_BENCH_TIME
    echo ""
}

# 测试4: 启动/停止功能
test_start_stop() {
    print_test "测试4: 启动/停止功能"
    
    # 确保有配置文件
    if [ ! -f "config" ]; then
        echo "y" | bash monitor.sh calibrate > /dev/null 2>&1
    fi
    
    # 启动监控
    bash monitor.sh start > /dev/null 2>&1
    
    # 检查PID文件
    if [ -f "monitor.pid" ]; then
        pid=$(cat monitor.pid)
        
        if ps -p $pid > /dev/null 2>&1; then
            print_pass "监控进程正在运行 (PID: $pid)"
        else
            print_fail "PID文件存在但进程未运行"
        fi
    else
        print_fail "PID文件未创建"
    fi
    
    # 停止监控
    bash monitor.sh stop > /dev/null 2>&1
    
    # 检查是否停止
    if [ ! -f "monitor.pid" ]; then
        print_pass "监控已正常停止"
    else
        print_fail "PID文件未删除"
    fi
    
    echo ""
}

# 测试5: 重复启动保护
test_duplicate_start() {
    print_test "测试5: 重复启动保护"
    
    # 确保有配置文件
    if [ ! -f "config" ]; then
        echo "y" | bash monitor.sh calibrate > /dev/null 2>&1
    fi
    
    # 启动监控
    bash monitor.sh start > /dev/null 2>&1
    
    # 尝试再次启动
    if bash monitor.sh start 2>&1 | grep -q "监控已在运行"; then
        print_pass "重复启动保护生效"
    else
        print_fail "未检测到重复启动保护"
    fi
    
    # 清理
    bash monitor.sh stop > /dev/null 2>&1
    
    echo ""
}

# 主测试流程
main() {
    echo "=========================================="
    echo "  CPU监控器 - 沙盒模拟测试"
    echo "=========================================="
    echo ""
    
    # 准备测试环境
    copy_files
    setup_mock_commands
    setup_bench
    
    # 运行测试
    test_calibrate
    test_start_stop
    test_duplicate_start
    test_normal_load
    test_overload
    
    # 输出测试结果
    echo "=========================================="
    echo "  测试完成"
    echo "=========================================="
    echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
    echo -e "${RED}失败: $TESTS_FAILED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ 所有测试通过!${NC}"
        exit 0
    else
        echo -e "${RED}✗ 部分测试失败${NC}"
        exit 1
    fi
}

main
