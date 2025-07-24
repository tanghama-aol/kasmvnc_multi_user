#!/bin/bash
# KasmVNC多用户创建脚本
# 作者: Xander Xu
# 用法: ./create_user_with_vnc.sh <用户数量> [--https]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_DIR="$PROJECT_DIR/certs"
LOG_DIR="$PROJECT_DIR/logs"

# 配置参数
USER_COUNT=${1:-1}
BASE_USER_HOME="/home/share/user"
BASE_DISPLAY=1010
BASE_PORT=15901
BASE_WEBSOCKET_PORT=4000
ENABLE_HTTPS=false
VNC_THREADS=4

# 检查是否启用HTTPS
if [[ "$2" == "--https" ]]; then
    ENABLE_HTTPS=true
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    local deps=("kasmvncserver" "kasmvncpasswd" "openssl" "pulseaudio")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "缺少依赖: $dep"
            exit 1
        fi
    done
    log_success "依赖检查通过"
}

# 创建证书目录
setup_cert_dir() {
    mkdir -p "$CERT_DIR"
    chmod 700 "$CERT_DIR"
    log_info "证书目录已创建: $CERT_DIR"
}

# 为用户生成HTTPS证书
generate_user_cert() {
    local username=$1
    local cert_file="$CERT_DIR/${username}.crt"
    local key_file="$CERT_DIR/${username}.key"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        log_info "为用户 $username 生成HTTPS证书..."
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/C=CN/ST=Beijing/L=Beijing/O=KasmVNC/OU=IT/CN=$username.kasmvnc.local" \
            2>/dev/null
        
        chmod 600 "$cert_file" "$key_file"
        chown "$username:$username" "$cert_file" "$key_file"
        log_success "证书已生成: $cert_file, $key_file"
    else
        log_info "用户 $username 的证书已存在"
    fi
    
    echo "$cert_file:$key_file"
}

# 创建用户
create_user() {
    local user_num=$1
    local username="user$user_num"
    local password="zxt${user_num}000"
    local user_home="$BASE_USER_HOME/$username"
    
    log_info "创建用户: $username"
    
    # 创建用户主目录
    mkdir -p "$user_home"
    
    # 创建用户（如果不存在）
    if ! id "$username" &>/dev/null; then
        useradd -m -d "$user_home" -s /bin/bash "$username"
        echo "$username:$password" | chpasswd
        log_success "用户 $username 创建成功，密码: $password"
    else
        log_warning "用户 $username 已存在"
    fi
    
    # 设置用户目录权限
    chown -R "$username:$username" "$user_home"
    chmod 755 "$user_home"
    
    # 创建VNC目录
    local vnc_dir="$user_home/.vnc"
    mkdir -p "$vnc_dir"
    chown "$username:$username" "$vnc_dir"
    chmod 700 "$vnc_dir"
    
    return 0
}

# 配置用户的VNC环境
setup_vnc_for_user() {
    local user_num=$1
    local username="user$user_num"
    local password="zxt${user_num}000"
    local user_home="$BASE_USER_HOME/$username"
    local display1=$((BASE_DISPLAY + (user_num - 1) * 10))
    local display2=$((display1 + 10))
    local port=$((BASE_PORT + user_num - 1))
    local websocket_port1=$((BASE_WEBSOCKET_PORT + (user_num - 1) * 2))
    local websocket_port2=$((websocket_port1 + 1))
    
    log_info "为用户 $username 配置VNC环境..."
    log_info "显示器: :$display1, :$display2"
    log_info "端口: $port, WebSocket: $websocket_port1, $websocket_port2"
    
    # 生成证书（如果需要）
    local cert_info=""
    if [[ "$ENABLE_HTTPS" == "true" ]]; then
        cert_info=$(generate_user_cert "$username")
        local cert_file="${cert_info%:*}"
        local key_file="${cert_info#*:}"
        
        # 设置环境变量
        echo "export HTTPS_CERT=\"$cert_file\"" >> "$user_home/.bashrc"
        echo "export HTTPS_CERT_KEY=\"$key_file\"" >> "$user_home/.bashrc"
    fi
    
    # 创建VNC密码文件
    local vnc_dir="$user_home/.vnc"
    if [[ ! -f "$vnc_dir/passwd" ]]; then
        su - "$username" -c "echo -e \"$password\\n$password\\n\" | kasmvncpasswd -u $username -o -w -r"
        log_success "VNC密码已设置"
    fi
    
    # 创建启动脚本
    create_start_script "$username" "$display1" "$websocket_port1" "$cert_info"
    create_start_script "$username" "$display2" "$websocket_port2" "$cert_info"
    
    # 创建Xstartup脚本
    create_xstartup_script "$username"
    
    log_success "用户 $username 的VNC环境配置完成"
}

# 创建VNC启动脚本
create_start_script() {
    local username=$1
    local display=$2
    local websocket_port=$3
    local cert_info=$4
    local user_home="$BASE_USER_HOME/$username"
    local script_file="$user_home/.vnc/start_display_${display}.sh"
    
    cat > "$script_file" << EOF
#!/bin/bash
# KasmVNC启动脚本 - 用户: $username, 显示器: :$display
# 自动生成于: $(date)

USER=$username
DISPLAY_NUM=$display
WEBSOCKET_PORT=$websocket_port
PASSWORD=\$(echo -n "zxt${username#user}000")
VNC_THREADS=$VNC_THREADS

# 清理旧的显示器锁文件
rm -rf /tmp/.X\${DISPLAY_NUM}-lock /tmp/.X11-unix/X\${DISPLAY_NUM}

# 设置证书变量
EOF

    if [[ -n "$cert_info" && "$cert_info" != ":" ]]; then
        local cert_file="${cert_info%:*}"
        local key_file="${cert_info#*:}"
        cat >> "$script_file" << EOF
export HTTPS_CERT="$cert_file"
export HTTPS_CERT_KEY="$key_file"
CERT_OPTS="-cert \$HTTPS_CERT -key \$HTTPS_CERT_KEY"
EOF
    else
        echo 'CERT_OPTS=""' >> "$script_file"
    fi

    cat >> "$script_file" << EOF

# 启动KasmVNC服务器
kasmvncserver :\${DISPLAY_NUM} \\
    -select-de xfce \\
    -interface 0.0.0.0 \\
    -websocketPort \${WEBSOCKET_PORT} \\
    -geometry 1920x1080 \\
    -RectThreads \${VNC_THREADS} \\
    \${CERT_OPTS}

# 启动音频服务
pulseaudio --start --daemonize

# 显示日志
tail -f ~/.vnc/*:\${DISPLAY_NUM}.log
EOF

    chmod +x "$script_file"
    chown "$username:$username" "$script_file"
}

# 创建Xstartup脚本
create_xstartup_script() {
    local username=$1
    local user_home="$BASE_USER_HOME/$username"
    local xstartup_file="$user_home/.vnc/xstartup"
    
    cat > "$xstartup_file" << 'EOF'
#!/bin/bash
# KasmVNC Xstartup脚本

# 设置环境变量
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export DESKTOP_SESSION=xfce

# 启动XFCE桌面环境
if [ -x /usr/bin/startxfce4 ]; then
    exec startxfce4
elif [ -x /usr/bin/xfce4-session ]; then
    exec xfce4-session
else
    # 备用桌面环境
    exec /usr/bin/x-window-manager
fi
EOF

    chmod +x "$xstartup_file"
    chown "$username:$username" "$xstartup_file"
}

# 主函数
main() {
    log_info "开始创建 $USER_COUNT 个KasmVNC用户..."
    log_info "HTTPS模式: $([ "$ENABLE_HTTPS" = true ] && echo "启用" || echo "禁用")"
    
    check_root
    check_dependencies
    
    if [[ "$ENABLE_HTTPS" == "true" ]]; then
        setup_cert_dir
    fi
    
    # 创建用户主目录
    mkdir -p "$BASE_USER_HOME"
    
    # 批量创建用户
    for ((i=1; i<=USER_COUNT; i++)); do
        log_info "处理用户 $i/$USER_COUNT..."
        create_user "$i"
        setup_vnc_for_user "$i"
        log_success "用户 user$i 创建完成"
        echo "----------------------------------------"
    done
    
    # 生成用户信息总结
    generate_user_summary
    
    log_success "所有用户创建完成！"
    log_info "请查看用户信息: $PROJECT_DIR/user_info.txt"
}

# 生成用户信息总结
generate_user_summary() {
    local summary_file="$PROJECT_DIR/user_info.txt"
    
    cat > "$summary_file" << EOF
KasmVNC多用户系统 - 用户信息总结
生成时间: $(date)
用户总数: $USER_COUNT
HTTPS模式: $([ "$ENABLE_HTTPS" = true ] && echo "启用" || echo "禁用")

用户详细信息:
=====================================
EOF

    for ((i=1; i<=USER_COUNT; i++)); do
        local username="user$i"
        local password="zxt${i}000"
        local display1=$((BASE_DISPLAY + (i - 1) * 10))
        local display2=$((display1 + 10))
        local port=$((BASE_PORT + i - 1))
        local websocket_port1=$((BASE_WEBSOCKET_PORT + (i - 1) * 2))
        local websocket_port2=$((websocket_port1 + 1))
        
        cat >> "$summary_file" << EOF

用户名: $username
密码: $password
主目录: $BASE_USER_HOME/$username
显示器: :$display1, :$display2
端口: $port
WebSocket端口: $websocket_port1, $websocket_port2
VNC地址: 
  - Display 1: vnc://localhost:$display1 (WebSocket: $websocket_port1)
  - Display 2: vnc://localhost:$display2 (WebSocket: $websocket_port2)
EOF

        if [[ "$ENABLE_HTTPS" == "true" ]]; then
            cat >> "$summary_file" << EOF
HTTPS证书: $CERT_DIR/${username}.crt
HTTPS密钥: $CERT_DIR/${username}.key
EOF
        fi
        
        cat >> "$summary_file" << EOF
启动脚本: 
  - $BASE_USER_HOME/$username/.vnc/start_display_${display1}.sh
  - $BASE_USER_HOME/$username/.vnc/start_display_${display2}.sh
=====================================
EOF
    done
    
    chmod 644 "$summary_file"
    log_success "用户信息已保存到: $summary_file"
}

# 参数验证
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "用法: $0 <用户数量> [--https]"
    echo "示例: $0 5          # 创建5个用户，不启用HTTPS"
    echo "示例: $0 3 --https  # 创建3个用户，启用HTTPS"
    exit 1
fi

if ! [[ "$1" =~ ^[0-9]+$ ]] || [[ $1 -le 0 ]]; then
    log_error "用户数量必须是正整数"
    exit 1
fi

# 执行主函数
main "$@"