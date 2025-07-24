#!/bin/bash
# KasmVNC单用户启动脚本
# 作者: Xander Xu
# 用法: ./startkasmvnc.sh <用户名> [display_number]

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

# 获取用户的显示器列表
get_user_displays() {
    local user_home="$BASE_USER_HOME/$USERNAME"
    local vnc_dir="$user_home/.vnc"
    
    if [[ ! -d "$vnc_dir" ]]; then
        log_error "用户 $USERNAME 的VNC目录不存在: $vnc_dir"
        exit 1
    fi
    
    # 查找所有启动脚本
    find "$vnc_dir" -name "start_display_*.sh" -type f | sort
}

# 启动指定显示器
start_display() {
    local display_script=$1
    local display_num=$(basename "$display_script" | sed -n 's/start_display_\([0-9]*\)\.sh/\1/p')
    
    log_info "启动用户 $USERNAME 的显示器 :$display_num..."
    
    # 检查显示器是否已经在运行
    if pgrep -f "kasmvncserver :$display_num" > /dev/null; then
        log_warning "显示器 :$display_num 已在运行"
        return 0
    fi
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    local log_file="$LOG_DIR/${USERNAME}_display_${display_num}.log"
    
    # 以用户身份启动VNC服务
    log_info "执行启动脚本: $display_script"
    su - "$USERNAME" -c "nohup bash '$display_script' > '$log_file' 2>&1 &"
    
    # 等待几秒钟检查启动状态
    sleep 3
    
    if pgrep -f "kasmvncserver :$display_num" > /dev/null; then
        log_success "显示器 :$display_num 启动成功"
        log_info "日志文件: $log_file"
        return 0
    else
        log_error "显示器 :$display_num 启动失败"
        log_info "查看日志: $log_file"
        return 1
    fi
}

# 主函数
main() {
    if [[ -z "$USERNAME" ]]; then
        echo "用法: $0 <用户名> [display_number]"
        echo ""
        echo "参数说明:"
        echo "  用户名: 要启动VNC服务的用户名"
        echo "  display_number: 可选，指定显示器编号，不指定则启动所有显示器"
        echo ""
        echo "示例:"
        echo "  $0 user1           # 启动user1的所有显示器"
        echo "  $0 user1 1010      # 启动user1的1010显示器"
        exit 1
    fi
    
    check_user_exists
    
    log_info "正在启动用户 $USERNAME 的KasmVNC服务..."
    
    local display_scripts=($(get_user_displays))
    
    if [[ ${#display_scripts[@]} -eq 0 ]]; then
        log_error "未找到用户 $USERNAME 的VNC启动脚本"
        exit 1
    fi
    
    local success_count=0
    local total_count=0
    
    for script in "${display_scripts[@]}"; do
        local display_num=$(basename "$script" | sed -n 's/start_display_\([0-9]*\)\.sh/\1/p')
        
        # 如果指定了特定显示器，只启动该显示器
        if [[ "$DISPLAY_NUM" != "all" && "$display_num" != "$DISPLAY_NUM" ]]; then
            continue
        fi
        
        total_count=$((total_count + 1))
        if start_display "$script"; then
            success_count=$((success_count + 1))
        fi
    done
    
    if [[ $total_count -eq 0 ]]; then
        log_error "未找到匹配的显示器"
        exit 1
    fi
    
    log_info "启动完成: $success_count/$total_count 个显示器启动成功"
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "所有显示器启动成功"
        exit 0
    else
        log_warning "部分显示器启动失败"
        exit 1
    fi
}

main "$@"