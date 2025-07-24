#!/bin/bash
# KasmVNC全体用户停止脚本
# 作者: Xander Xu
# 用法: ./stop_allkasmvnc.sh [用户名列表文件]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"

USER_LIST_FILE=${1:-"$PROJECT_DIR/user_info.txt"}
BASE_USER_HOME="/home/share/user"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取所有用户列表
get_all_users() {
    if [[ -f "$USER_LIST_FILE" ]]; then
        # 从用户信息文件中提取用户名
        grep "^用户名:" "$USER_LIST_FILE" | sed 's/用户名: //' | sort
    else
        # 从系统中查找用户目录
        if [[ -d "$BASE_USER_HOME" ]]; then
            find "$BASE_USER_HOME" -maxdepth 1 -type d -name "user*" -exec basename {} \; | sort
        fi
    fi
}

# 获取所有正在运行的KasmVNC用户
get_running_users() {
    # 查找所有kasmvncserver进程，提取用户名
    pgrep -f kasmvncserver | while read pid; do
        ps -p "$pid" -o user --no-headers 2>/dev/null | grep "^user" || true
    done | sort -u
}

# 检查用户VNC服务状态
check_user_status() {
    local username=$1
    local running_displays=$(pgrep -f "kasmvncserver.*$username" 2>/dev/null | wc -l)
    echo "$running_displays"
}

# 停止单个用户的所有VNC服务
stop_user_vnc() {
    local username=$1
    
    log_info "停止用户 $username 的VNC服务..."
    
    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        log_error "用户 $username 不存在，跳过"
        return 1
    fi
    
    # 检查是否在运行
    local running_count=$(check_user_status "$username")
    if [[ $running_count -eq 0 ]]; then
        log_info "用户 $username 没有运行中的VNC服务"
        return 0
    fi
    
    # 调用单用户停止脚本
    if "$SCRIPT_DIR/stopkasmvnc.sh" "$username"; then
        log_success "用户 $username 的VNC服务停止成功"
        return 0
    else
        log_error "用户 $username 的VNC服务停止失败"
        return 1
    fi
}

# 强制停止所有KasmVNC进程
force_stop_all() {
    log_warning "执行强制停止所有KasmVNC进程..."
    
    # 查找所有kasmvncserver进程
    local pids=$(pgrep -f kasmvncserver || true)
    
    if [[ -z "$pids" ]]; then
        log_info "没有发现运行中的KasmVNC进程"
        return 0
    fi
    
    log_info "发现运行中的KasmVNC进程: $(echo $pids | tr '\n' ' ')"
    
    # 尝试优雅停止
    for pid in $pids; do
        log_info "停止进程 $pid..."
        kill "$pid" 2>/dev/null || true
    done
    
    # 等待进程停止
    sleep 5
    
    # 检查仍在运行的进程
    local remaining_pids=$(pgrep -f kasmvncserver || true)
    
    if [[ -n "$remaining_pids" ]]; then
        log_warning "强制终止剩余进程: $(echo $remaining_pids | tr '\n' ' ')"
        for pid in $remaining_pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 2
    fi
    
    # 清理锁文件和套接字
    log_info "清理临时文件..."
    rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
    
    # 最终检查
    if pgrep -f kasmvncserver >/dev/null; then
        log_error "仍有KasmVNC进程未能停止"
        return 1
    else
        log_success "所有KasmVNC进程已停止"
        return 0
    fi
}

# 停止所有用户的音频服务
stop_all_audio() {
    log_info "停止所有用户的音频服务..."
    
    local users=($(get_all_users))
    local stopped_count=0
    
    for username in "${users[@]}"; do
        if [[ -n "$username" ]]; then
            local audio_pids=$(pgrep -u "$username" pulseaudio 2>/dev/null || true)
            if [[ -n "$audio_pids" ]]; then
                log_info "停止用户 $username 的音频服务..."
                for pid in $audio_pids; do
                    kill "$pid" 2>/dev/null || true
                done
                stopped_count=$((stopped_count + 1))
            fi
        fi
    done
    
    if [[ $stopped_count -gt 0 ]]; then
        sleep 2
        log_success "已停止 $stopped_count 个用户的音频服务"
    else
        log_info "没有发现运行中的用户音频服务"
    fi
}

# 显示所有用户状态
show_all_status() {
    log_info "当前所有用户VNC服务状态:"
    echo "========================================"
    
    local users=($(get_all_users))
    local total_users=0
    local running_users=0
    local total_displays=0
    
    for username in "${users[@]}"; do
        if [[ -n "$username" ]]; then
            total_users=$((total_users + 1))
            local running_count=$(check_user_status "$username")
            total_displays=$((total_displays + running_count))
            
            if [[ $running_count -gt 0 ]]; then
                running_users=$((running_users + 1))
                echo -e "${GREEN}$username${NC}: $running_count 个显示器运行中"
            else
                echo -e "${RED}$username${NC}: 未运行"
            fi
        fi
    done
    
    echo "========================================"
    log_info "总结: $running_users/$total_users 个用户运行中，共 $total_displays 个显示器"
}

# 并行停止多个用户
parallel_stop() {
    local users=("$@")
    local total_count=${#users[@]}
    local success_count=0
    local failed_users=()
    
    log_info "并行停止 $total_count 个用户的VNC服务..."
    
    # 创建临时目录存储结果
    local temp_dir=$(mktemp -d)
    
    # 并行停止
    local pids=()
    for i in "${!users[@]}"; do
        local username="${users[$i]}"
        if [[ -n "$username" ]]; then
            (
                if stop_user_vnc "$username"; then
                    echo "SUCCESS" > "$temp_dir/$username.result"
                else
                    echo "FAILED" > "$temp_dir/$username.result"
                fi
            ) &
            pids+=($!)
        fi
    done
    
    # 等待所有后台进程完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # 统计结果
    for username in "${users[@]}"; do
        if [[ -n "$username" && -f "$temp_dir/$username.result" ]]; then
            local result=$(cat "$temp_dir/$username.result")
            if [[ "$result" == "SUCCESS" ]]; then
                success_count=$((success_count + 1))
            else
                failed_users+=("$username")
            fi
        fi
    done
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 显示结果
    log_info "停止完成: $success_count/$total_count 个用户停止成功"
    
    if [[ ${#failed_users[@]} -gt 0 ]]; then
        log_warning "停止失败的用户: ${failed_users[*]}"
    fi
    
    return $((total_count - success_count))
}

# 顺序停止
sequential_stop() {
    local users=("$@")
    local total_count=${#users[@]}
    local success_count=0
    local failed_users=()
    
    log_info "顺序停止 $total_count 个用户的VNC服务..."
    
    for i in "${!users[@]}"; do
        local username="${users[$i]}"
        if [[ -n "$username" ]]; then
            log_info "进度: $((i + 1))/$total_count - 停止用户 $username"
            
            if stop_user_vnc "$username"; then
                success_count=$((success_count + 1))
            else
                failed_users+=("$username")
            fi
            
            # 稍等片刻让系统处理
            sleep 1
        fi
    done
    
    log_info "停止完成: $success_count/$total_count 个用户停止成功"
    
    if [[ ${#failed_users[@]} -gt 0 ]]; then
        log_warning "停止失败的用户: ${failed_users[*]}"
    fi
    
    return $((total_count - success_count))
}

# 主函数
main() {
    log_info "开始停止所有用户的KasmVNC服务..."
    
    # 检查单用户停止脚本是否存在
    if [[ ! -x "$SCRIPT_DIR/stopkasmvnc.sh" ]]; then
        log_error "找不到单用户停止脚本: $SCRIPT_DIR/stopkasmvnc.sh"
        exit 1
    fi
    
    # 显示当前状态
    show_all_status
    
    # 获取正在运行的用户列表
    local running_users=($(get_running_users))
    
    if [[ ${#running_users[@]} -eq 0 ]]; then
        log_info "没有发现运行中的KasmVNC服务"
        exit 0
    fi
    
    log_info "发现 ${#running_users[@]} 个用户有运行中的VNC服务: ${running_users[*]}"
    
    # 询问停止方式
    local stop_mode="parallel"
    local force_mode=false
    
    echo ""
    echo "请选择停止方式:"
    echo "1) 并行停止 (更快)"
    echo "2) 顺序停止 (更稳定)"
    echo "3) 强制停止所有 (立即终止所有进程)"
    read -p "请输入选择 [1]: " choice
    
    case $choice in
        2)
            stop_mode="sequential"
            ;;
        3)
            force_mode=true
            ;;
        *)
            stop_mode="parallel"
            ;;
    esac
    
    echo ""
    
    if [[ "$force_mode" == "true" ]]; then
        log_warning "使用强制停止模式..."
        force_stop_all
        stop_all_audio
        local exit_code=$?
    else
        log_info "使用 $stop_mode 模式停止..."
        
        # 执行停止
        if [[ "$stop_mode" == "parallel" ]]; then
            parallel_stop "${running_users[@]}"
        else
            sequential_stop "${running_users[@]}"
        fi
        
        local exit_code=$?
        
        # 停止音频服务
        stop_all_audio
        
        # 如果有停止失败的，询问是否强制停止
        if [[ $exit_code -ne 0 ]]; then
            echo ""
            read -p "部分服务停止失败，是否强制停止剩余进程? [y/N]: " force_choice
            if [[ "$force_choice" =~ ^[Yy]$ ]]; then
                force_stop_all
            fi
        fi
    fi
    
    echo ""
    echo "========================================"
    
    # 显示最终状态
    show_all_status
    
    # 检查是否还有运行中的进程
    local remaining_processes=$(pgrep -f kasmvncserver | wc -l)
    
    if [[ $remaining_processes -eq 0 ]]; then
        log_success "所有用户的VNC服务已停止！"
        exit_code=0
    else
        log_warning "仍有 $remaining_processes 个KasmVNC进程在运行"
        log_info "可以使用 '$0 --force' 强制停止所有进程"
        exit_code=1
    fi
    
    log_info "可以使用以下命令查看状态:"
    log_info "  - 查看进程: ps aux | grep kasmvnc"
    log_info "  - 查看用户状态: ./stop_allkasmvnc.sh --status"
    
    exit $exit_code
}

# 参数处理
case "${1:-}" in
    -h|--help)
        echo "用法: $0 [选项] [用户信息文件]"
        echo ""
        echo "选项:"
        echo "  -h, --help     显示此帮助信息"
        echo "  -s, --status   仅显示当前状态"
        echo "  -f, --force    强制停止所有进程"
        echo ""
        echo "参数说明:"
        echo "  用户信息文件: 可选，包含用户信息的文件路径"
        echo "                默认: $USER_LIST_FILE"
        echo ""
        echo "功能:"
        echo "  - 自动发现并停止所有KasmVNC用户的VNC服务"
        echo "  - 支持并行、顺序和强制三种停止模式"
        echo "  - 显示停止前后的服务状态"
        echo ""
        echo "示例:"
        echo "  $0                    # 交互式停止"
        echo "  $0 --force            # 强制停止所有"
        echo "  $0 --status           # 仅查看状态"
        exit 0
        ;;
    -s|--status)
        show_all_status
        exit 0
        ;;
    -f|--force)
        force_stop_all
        stop_all_audio
        show_all_status
        exit $?
        ;;
esac

# 执行主函数
main "$@"