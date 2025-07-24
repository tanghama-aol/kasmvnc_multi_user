#!/bin/bash
# KasmVNC单用户停止脚本
# 作者: Xander Xu
# 用法: ./stopkasmvnc.sh <用户名> [display_number]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"

USERNAME=${1}
DISPLAY_NUM=${2:-"all"}
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

# 检查用户是否存在
check_user_exists() {
    if ! id "$USERNAME" &>/dev/null; then
        log_error "用户 $USERNAME 不存在"
        exit 1
    fi
}

# 获取用户的运行中的显示器
get_running_displays() {
    # 查找所有属于该用户的kasmvncserver进程
    pgrep -f "kasmvncserver.*$USERNAME" | while read pid; do
        if [[ -n "$pid" ]]; then
            ps -p "$pid" -o args --no-headers | grep -o ':[0-9]\+' | sed 's/://'
        fi
    done | sort -n
}

# 停止指定显示器
stop_display() {
    local display_num=$1
    
    log_info "停止用户 $USERNAME 的显示器 :$display_num..."
    
    # 查找并停止kasmvncserver进程
    local pids=$(pgrep -f "kasmvncserver :$display_num.*$USERNAME" || true)
    
    if [[ -z "$pids" ]]; then
        log_warning "显示器 :$display_num 未在运行"
        return 0
    fi
    
    # 尝试优雅停止
    for pid in $pids; do
        log_info "停止进程 $pid (显示器 :$display_num)..."
        if kill "$pid" 2>/dev/null; then
            log_info "发送停止信号给进程 $pid"
        fi
    done
    
    # 等待进程停止
    local wait_count=0
    while [[ $wait_count -lt 10 ]]; do
        if ! pgrep -f "kasmvncserver :$display_num.*$USERNAME" >/dev/null; then
            break
        fi
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    # 如果仍在运行，强制停止
    pids=$(pgrep -f "kasmvncserver :$display_num.*$USERNAME" || true)
    if [[ -n "$pids" ]]; then
        log_warning "优雅停止失败，强制停止进程..."
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 2
    fi
    
    # 清理锁文件和套接字
    rm -f "/tmp/.X${display_num}-lock" "/tmp/.X11-unix/X${display_num}" 2>/dev/null || true
    
    # 最终检查
    if pgrep -f "kasmvncserver :$display_num.*$USERNAME" >/dev/null; then
        log_error "显示器 :$display_num 停止失败"
        return 1
    else
        log_success "显示器 :$display_num 已停止"
        return 0
    fi
}

# 停止用户的音频服务
stop_audio_service() {
    log_info "停止用户 $USERNAME 的音频服务..."
    
    local audio_pids=$(pgrep -u "$USERNAME" pulseaudio || true)
    if [[ -n "$audio_pids" ]]; then
        for pid in $audio_pids; do
            log_info "停止音频进程 $pid..."
            kill "$pid" 2>/dev/null || true
        done
        
        # 等待音频服务停止
        sleep 2
        
        # 强制停止仍在运行的音频进程
        audio_pids=$(pgrep -u "$USERNAME" pulseaudio || true)
        if [[ -n "$audio_pids" ]]; then
            for pid in $audio_pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
        
        log_success "音频服务已停止"
    else
        log_info "用户 $USERNAME 的音频服务未在运行"
    fi
}

# 显示用户VNC状态
show_vnc_status() {
    log_info "检查用户 $USERNAME 的VNC状态..."
    
    local running_displays=($(get_running_displays))
    
    if [[ ${#running_displays[@]} -eq 0 ]]; then
        log_info "用户 $USERNAME 没有运行中的VNC显示器"
    else
        log_info "用户 $USERNAME 运行中的显示器:"
        for display in "${running_displays[@]}"; do
            local pid=$(pgrep -f "kasmvncserver :$display.*$USERNAME" | head -1)
            log_info "  显示器 :$display (PID: $pid)"
        done
    fi
}

# 主函数
main() {
    if [[ -z "$USERNAME" ]]; then
        echo "用法: $0 <用户名> [display_number]"
        echo ""
        echo "参数说明:"
        echo "  用户名: 要停止VNC服务的用户名"
        echo "  display_number: 可选，指定显示器编号，不指定则停止所有显示器"
        echo ""
        echo "示例:"
        echo "  $0 user1           # 停止user1的所有显示器"
        echo "  $0 user1 1010      # 停止user1的1010显示器"
        exit 1
    fi
    
    check_user_exists
    
    log_info "正在停止用户 $USERNAME 的KasmVNC服务..."
    
    # 显示当前状态
    show_vnc_status
    
    local running_displays=($(get_running_displays))
    
    if [[ ${#running_displays[@]} -eq 0 ]]; then
        log_info "用户 $USERNAME 没有运行中的VNC显示器"
        exit 0
    fi
    
    local success_count=0
    local total_count=0
    
    for display in "${running_displays[@]}"; do
        # 如果指定了特定显示器，只停止该显示器
        if [[ "$DISPLAY_NUM" != "all" && "$display" != "$DISPLAY_NUM" ]]; then
            continue
        fi
        
        total_count=$((total_count + 1))
        if stop_display "$display"; then
            success_count=$((success_count + 1))
        fi
    done
    
    if [[ $total_count -eq 0 ]]; then
        if [[ "$DISPLAY_NUM" != "all" ]]; then
            log_warning "显示器 :$DISPLAY_NUM 未在运行"
        else
            log_info "没有需要停止的显示器"
        fi
        exit 0
    fi
    
    # 如果停止了所有显示器，也停止音频服务
    if [[ "$DISPLAY_NUM" == "all" && $success_count -eq $total_count ]]; then
        stop_audio_service
    fi
    
    log_info "停止完成: $success_count/$total_count 个显示器停止成功"
    
    # 最终状态检查
    show_vnc_status
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "所有指定的显示器已停止"
        exit 0
    else
        log_warning "部分显示器停止失败"
        exit 1
    fi
}

main "$@"