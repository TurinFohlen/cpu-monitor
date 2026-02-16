#!/data/data/com.termux/files/usr/bin/bash
#
# monitor.sh - CPU调度延迟监控器主控脚本
# 功能: 校准、启动、停止、查看监控状态
#

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置文件
CONFIG_FILE="$SCRIPT_DIR/config"
PID_FILE="$SCRIPT_DIR/monitor.pid"
BENCH_PROG="$SCRIPT_DIR/bench"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查bench程序是否存在
check_bench() {
    if [ ! -f "$BENCH_PROG" ]; then
        print_error "找不到 bench 程序,请先运行 make 编译"
        exit 1
    fi
    
    if [ ! -x "$BENCH_PROG" ]; then
        print_error "bench 程序没有执行权限"
        chmod +x "$BENCH_PROG"
        print_success "已添加执行权限"
    fi
}

# 校准模式
calibrate() {
    print_info "开始校准模式..."
    check_bench
    
    while true; do
        print_info "将连续运行基准测试 10 次,请稍候..."
        echo ""
        
        local sum=0
        local count=10
        declare -a results
        
        for i in $(seq 1 $count); do
            local result=$($BENCH_PROG)
            results+=("$result")
            
            # 计算每秒可执行次数: 1000000 / 耗时(微秒)
            local freq=$(echo "scale=2; 1000000 / $result" | bc)
            
            printf "第 %2d 次: %s μs (≈%.2f 次/秒)\n" "$i" "$result" "$freq"
            
            # 累加用于计算平均值
            sum=$(echo "$sum + $result" | bc)
        done
        
        echo ""
        
        # 计算平均耗时(取整数)
        local avg_time=$(echo "scale=0; $sum / $count" | bc)
        local avg_freq=$(echo "scale=2; 1000000 / $avg_time" | bc)
        
        print_success "平均耗时: ${avg_time} μs,每秒可执行: ${avg_freq} 次"
        echo ""
        
        # 询问用户
        read -p "是否将其作为基准耗时? (y/n): " answer
        
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            # 计算阈值(150% = 1.5倍)
            local threshold=$(echo "scale=0; $avg_time * 1.5" | bc)
            
            # 保存配置
            cat > "$CONFIG_FILE" << EOF
# CPU监控器配置文件
# 基准平均耗时(微秒)
BASELINE_US=$avg_time

# 阈值倍数
THRESHOLD_MULTIPLIER=1.5

# 计算出的阈值(微秒)
THRESHOLD_US=$threshold

# 检查间隔(秒)
CHECK_INTERVAL=60

# 连续超限次数触发报警
CONSECUTIVE_LIMIT=3
EOF
            
            print_success "配置已保存到 $CONFIG_FILE"
            print_info "基准耗时: ${avg_time} μs"
            print_info "报警阈值: ${threshold} μs (${THRESHOLD_MULTIPLIER}倍)"
            print_info "检查间隔: 60 秒"
            print_info "连续超限: 3 次触发报警"
            echo ""
            print_success "校准完成!现在可以运行 monitor.sh start 启动监控"
            break
            
        else
            read -p "重新校准(r) 或 退出(e)? " choice
            if [[ "$choice" =~ ^[Ee]$ ]]; then
                print_info "已退出校准"
                exit 0
            elif [[ ! "$choice" =~ ^[Rr]$ ]]; then
                print_error "无效输入,退出"
                exit 1
            fi
            # 如果输入r,继续循环重新校准
            echo ""
        fi
    done
}

# 加载配置
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "配置文件不存在,请先运行校准: monitor.sh calibrate"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    # 验证必要的配置项
    if [ -z "$BASELINE_US" ] || [ -z "$THRESHOLD_US" ] || [ -z "$CHECK_INTERVAL" ] || [ -z "$CONSECUTIVE_LIMIT" ]; then
        print_error "配置文件不完整,请重新校准"
        exit 1
    fi
}

# 发送通知
send_notification() {
    local title="$1"
    local content="$2"
    
    # 检查termux-notification是否可用
    if command -v termux-notification &> /dev/null; then
        termux-notification \
            --vibrate "${VIBRATE_PATTERN}"\
            --title "$title" \
            --content "$content" \
            --priority high \
            --button1 "停止监控" \
            --button1-action "$SCRIPT_DIR/monitor.sh stop" \
            --sound
    else
        print_warning "termux-notification 不可用,无法发送通知"
        echo "$title: $content"
    fi
}

# 监控循环
monitor_loop() {
    load_config
    
    print_info "监控配置:"
    print_info "  基准耗时: ${BASELINE_US} μs"
    print_info "  报警阈值: ${THRESHOLD_US} μs"
    print_info "  检查间隔: ${CHECK_INTERVAL} 秒"
    print_info "  连续超限: ${CONSECUTIVE_LIMIT} 次触发报警"
    echo ""
    
    # 尝试获取唤醒锁
    if command -v termux-wake-lock &> /dev/null; then
        termux-wake-lock
        print_success "已获取唤醒锁"
    else
        print_warning "termux-wake-lock 不可用,进程可能被系统挂起"
    fi
    
    local consecutive_count=0
    local check_number=0
    
    print_success "监控已启动 (PID: $$)"
    
    # 清理函数
    cleanup() {
        print_info "正在停止监控..."
        if command -v termux-wake-unlock &> /dev/null; then
            termux-wake-unlock
            print_info "已释放唤醒锁"
        fi
        rm -f "$PID_FILE"
        print_success "监控已停止"
        exit 0
    }
    
    # 捕获信号
    trap cleanup SIGTERM SIGINT
    
    while true; do
        check_number=$((check_number + 1))
        
        # 执行基准测试
        local current_time=$($BENCH_PROG)
        
        # 记录日志(可选)
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] 检查 #$check_number: ${current_time} μs (阈值: ${THRESHOLD_US} μs)" >> "$SCRIPT_DIR/monitor.log"
        
        # 比较耗时与阈值(使用bc进行浮点数比较)
        if (( $(echo "$current_time > $THRESHOLD_US" | bc -l) )); then
            consecutive_count=$((consecutive_count + 1))
            print_warning "检查 #$check_number: 超阈值 ${current_time} μs > ${THRESHOLD_US} μs (连续: ${consecutive_count}/${CONSECUTIVE_LIMIT})"
            
            # 达到连续超限次数
            if [ $consecutive_count -ge $CONSECUTIVE_LIMIT ]; then
                print_error "触发报警!连续 ${consecutive_count} 次超阈值"
                
                send_notification \
                    "⚠️ CPU 调度延迟过高" \
                    "连续 ${consecutive_count} 次超阈值,最近一次耗时 ${current_time} μs (阈值 ${THRESHOLD_US} μs)"
                
                # 重置计数器,避免重复通知
                consecutive_count=0
            fi
        else
            if [ $consecutive_count -gt 0 ]; then
                print_success "检查 #$check_number: 恢复正常 ${current_time} μs ≤ ${THRESHOLD_US} μs"
            fi
            consecutive_count=0
        fi
        
        # 休眠
        sleep $CHECK_INTERVAL
    done
}

# 启动监控
start() {
    # 检查是否已在运行
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p $old_pid > /dev/null 2>&1; then
            print_error "监控已在运行 (PID: $old_pid)"
            print_info "如需重启,请先运行: monitor.sh stop"
            exit 1
        else
            print_warning "发现残留的PID文件,已清理"
            rm -f "$PID_FILE"
        fi
    fi
    
    check_bench
    
    # 后台运行监控循环
    monitor_loop &
    local pid=$!
    echo $pid > "$PID_FILE"
    
    print_success "监控已启动 (PID: $pid)"
    print_info "日志文件: $SCRIPT_DIR/monitor.log"
    print_info "停止监控: monitor.sh stop"
    print_info "查看状态: monitor.sh status"
}

# 停止监控
stop() {
    if [ ! -f "$PID_FILE" ]; then
        print_warning "监控未运行"
        exit 0
    fi
    
    local pid=$(cat "$PID_FILE")
    
    if ps -p $pid > /dev/null 2>&1; then
        print_info "正在停止监控 (PID: $pid)..."
        kill $pid
        
        # 等待进程结束
        local count=0
        while ps -p $pid > /dev/null 2>&1 && [ $count -lt 10 ]; do
            sleep 0.5
            count=$((count + 1))
        done
        
        if ps -p $pid > /dev/null 2>&1; then
            print_warning "进程未响应,强制结束"
            kill -9 $pid
        fi
        
        rm -f "$PID_FILE"
        print_success "监控已停止"
    else
        print_warning "进程不存在,清理PID文件"
        rm -f "$PID_FILE"
    fi
}

# 查看状态
status() {
    if [ ! -f "$PID_FILE" ]; then
        print_info "监控状态: 未运行"
        return
    fi
    
    local pid=$(cat "$PID_FILE")
    
    if ps -p $pid > /dev/null 2>&1; then
        print_success "监控状态: 运行中 (PID: $pid)"
        
        if [ -f "$CONFIG_FILE" ]; then
            load_config
            print_info "当前配置:"
            print_info "  基准耗时: ${BASELINE_US} μs"
            print_info "  报警阈值: ${THRESHOLD_US} μs"
            print_info "  检查间隔: ${CHECK_INTERVAL} 秒"
        fi
        
        if [ -f "$SCRIPT_DIR/monitor.log" ]; then
            echo ""
            print_info "最近5条日志:"
            tail -n 5 "$SCRIPT_DIR/monitor.log"
        fi
    else
        print_warning "监控状态: 已停止 (残留PID文件)"
        rm -f "$PID_FILE"
    fi
}

# 显示帮助
show_help() {
    cat << EOF
CPU 调度延迟监控器

用法: $0 <命令>

命令:
  calibrate   进入校准模式,建立基准耗时和阈值
  start       启动后台监控
  stop        停止监控
  status      查看监控状态
  help        显示此帮助信息

示例:
  首次使用:
    $0 calibrate    # 校准并设置阈值
    $0 start        # 启动监控
  
  日常使用:
    $0 status       # 查看运行状态
    $0 stop         # 停止监控

注意:
  - 需要先安装: pkg install termux-api clang make
  - 需要编译: make
  - 建议授予Termux通知权限和忽略电池优化
EOF
}

# 主程序
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    case "$1" in
        calibrate)
            calibrate
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        status)
            status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"

