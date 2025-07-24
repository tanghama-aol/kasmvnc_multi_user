#!/bin/bash
# KasmVNC全体用户启动脚本
# 作者: Xander Xu
# 用法: ./start_allkasmvnc.sh [用户名列表文件]

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

# 检查用户VNC服务状态
check_user_status() {
    local username=$1
    local running_displays=$(pgrep -f "kasmvncserver.*$username" | wc -l)
    echo "$running_displays"
}

# 启动单个用户的所有VNC服务
start_user_vnc() {
    local username=$1
    
    log_info "启动用户 $username 的VNC服务..."
    
    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        log_error "用户 $username 不存在，跳过"
        return 1
    fi
    
    # 检查是否已经在运行
    local running_count=$(check_user_status "$username")
    if [[ $running_count -gt 0 ]]; then
        log_warning "用户 $username 已有 $running_count 个VNC服务在运行"
        return 0
    fi
    
    # 调用单用户启动脚本
    if "$SCRIPT_DIR/startkasmvnc.sh" "$username"; then
        log_success "用户 $username 的VNC服务启动成功"
        return 0
    else
        log_error "用户 $username 的VNC服务启动失败"
        return 1
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

# 并行启动多个用户
parallel_start() {
    local users=("$@")
    local total_count=${#users[@]}
    local success_count=0
    local failed_users=()
    
    log_info "并行启动 $total_count 个用户的VNC服务..."
    
    # 创建临时目录存储结果
    local temp_dir=$(mktemp -d)
    
    # 并行启动
    local pids=()
    for i in "${!users[@]}"; do
        local username="${users[$i]}"
        if [[ -n "$username" ]]; then
            (
                if start_user_vnc "$username"; then
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
    log_info "启动完成: $success_count/$total_count 个用户启动成功"
    
    if [[ ${#failed_users[@]} -gt 0 ]]; then
        log_warning "启动失败的用户: ${failed_users[*]}"
    fi
    
    return $((total_count - success_count))
}

# 顺序启动（适用于系统资源有限的情况）
sequential_start() {
    local users=("$@")
    local total_count=${#users[@]}
    local success_count=0
    local failed_users=()
    
    log_info "顺序启动 $total_count 个用户的VNC服务..."
    
    for i in "${!users[@]}"; do
        local username="${users[$i]}"
        if [[ -n "$username" ]]; then
            log_info "进度: $((i + 1))/$total_count - 启动用户 $username"
            
            if start_user_vnc "$username"; then
                success_count=$((success_count + 1))
                # 启动成功后稍等片刻，避免系统负载过高
                sleep 2
            else
                failed_users+=("$username")
            fi
        fi
    done
    
    log_info "启动完成: $success_count/$total_count 个用户启动成功"
    
    if [[ ${#failed_users[@]} -gt 0 ]]; then
        log_warning "启动失败的用户: ${failed_users[*]}"
    fi
    
    return $((total_count - success_count))
}

# 主函数
main() {
    log_info "开始启动所有用户的KasmVNC服务..."
    
    # 检查单用户启动脚本是否存在
    if [[ ! -x "$SCRIPT_DIR/startkasmvnc.sh" ]]; then
        log_error "找不到单用户启动脚本: $SCRIPT_DIR/startkasmvnc.sh"
        exit 1
    fi
    
    # 获取用户列表
    local users=($(get_all_users))
    
    if [[ ${#users[@]} -eq 0 ]]; then
        log_error "未找到任何用户"
        log_info "请确保用户信息文件存在: $USER_LIST_FILE"
        log_info "或者用户目录存在: $BASE_USER_HOME"
        exit 1
    fi
    
    log_info "找到 ${#users[@]} 个用户: ${users[*]}"
    
    # 显示当前状态
    show_all_status
    
    # 询问启动方式（如果用户数量较多）
    local start_mode="parallel"
    if [[ ${#users[@]} -gt 10 ]]; then
        echo ""
        echo "检测到用户数量较多(${#users[@]}个)，请选择启动方式:"
        echo "1) 并行启动 (更快，但资源消耗大)"
        echo "2) 顺序启动 (较慢，但更稳定)"
        read -p "请输入选择 [1]: " choice
        
        case $choice in
            2)
                start_mode="sequential"
                ;;
            *)
                start_mode="parallel"
                ;;
        esac
    fi
    
    echo ""
    log_info "使用 $start_mode 模式启动..."
    
    # 执行启动
    if [[ "$start_mode" == "parallel" ]]; then
        parallel_start "${users[@]}"
    else
        sequential_start "${users[@]}"
    fi
    
    local exit_code=$?
    
    echo ""
    echo "========================================"
    
    # 显示最终状态
    show_all_status
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "所有用户的VNC服务启动完成！"
    else
        log_warning "部分用户的VNC服务启动失败"
    fi
    
    log_info "可以使用以下命令查看详细状态:"
    log_info "  - 查看特定用户: ./startkasmvnc.sh <用户名>"
    log_info "  - 查看系统进程: ps aux | grep kasmvnc"
    log_info "  - 查看日志: ls -la $LOG_DIR/"
    
    exit $exit_code
}

# 参数处理
case "${1:-}" in
    -h|--help)
        echo "用法: $0 [用户信息文件]"
        echo ""
        echo "参数说明:"
        echo "  用户信息文件: 可选，包含用户信息的文件路径"
        echo "                默认: $USER_LIST_FILE"
        echo ""
        echo "功能:"
        echo "  - 自动发现并启动所有KasmVNC用户的VNC服务"
        echo "  - 支持并行和顺序两种启动模式"
        echo "  - 显示启动前后的服务状态"
        echo ""
        echo "示例:"
        echo "  $0                    # 使用默认用户信息文件"
        echo "  $0 /path/to/users.txt # 使用指定的用户信息文件"
        exit 0
        ;;
    -s|--status)
        show_all_status
        exit 0
        ;;
esac

# 执行主函数
main "$@"