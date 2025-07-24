#!/bin/bash
# KasmVNC桌面同步脚本
# 作者: Xander Xu
# 用法: ./sync_desktop.sh [源用户] [目标用户列表] [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs"

SOURCE_USER=${1:-"tang"}
TARGET_USERS=${2:-"all"}
DRY_RUN=false
BASE_USER_HOME="/home/share/user"

# 检查dry-run参数
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
        break
    fi
done

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

log_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
}

# 获取源用户桌面路径
get_source_desktop_path() {
    local source_user=$1
    local possible_paths=(
        "/home/$source_user/Desktop"
        "/home/$source_user/桌面"
        "/home/$source_user/.config/autostart"
        "/home/$source_user/.local/share/applications"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# 获取所有目标用户列表
get_target_users() {
    if [[ "$TARGET_USERS" == "all" ]]; then
        # 从用户目录中获取所有user*用户
        if [[ -d "$BASE_USER_HOME" ]]; then
            find "$BASE_USER_HOME" -maxdepth 1 -type d -name "user*" -exec basename {} \; | sort
        fi
    else
        # 分割用户列表
        echo "$TARGET_USERS" | tr ',' ' '
    fi
}

# 检查用户是否存在
check_user_exists() {
    local username=$1
    if ! id "$username" &>/dev/null; then
        log_error "用户 $username 不存在"
        return 1
    fi
    return 0
}

# 创建目标用户的桌面目录
setup_target_desktop() {
    local target_user=$1
    local target_home="$BASE_USER_HOME/$target_user"
    
    # 创建桌面相关目录
    local desktop_dirs=(
        "$target_home/Desktop"
        "$target_home/桌面"
        "$target_home/.config/autostart"
        "$target_home/.local/share/applications"
        "$target_home/.local/share/icons"
    )
    
    for dir in "${desktop_dirs[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "创建目录: $dir"
        else
            mkdir -p "$dir"
            chown "$target_user:$target_user" "${dir%/*}" "$dir" 2>/dev/null || true
            log_info "创建目录: $dir"
        fi
    done
}

# 同步桌面文件
sync_desktop_files() {
    local source_path=$1
    local target_user=$2
    local target_home="$BASE_USER_HOME/$target_user"
    
    if [[ ! -d "$source_path" ]]; then
        log_warning "源路径不存在: $source_path"
        return 1
    fi
    
    # 确定目标路径
    local target_path
    case "$(basename "$source_path")" in
        "Desktop")
            target_path="$target_home/Desktop"
            ;;
        "桌面")
            target_path="$target_home/桌面"
            ;;
        "autostart")
            target_path="$target_home/.config/autostart"
            ;;
        "applications")
            target_path="$target_home/.local/share/applications"
            ;;
        *)
            target_path="$target_home/Desktop"
            ;;
    esac
    
    log_info "同步 $source_path -> $target_path (用户: $target_user)"
    
    # 创建目标目录
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "创建目录: $target_path"
    else
        mkdir -p "$target_path"
    fi
    
    # 同步文件
    local sync_count=0
    local error_count=0
    
    find "$source_path" -type f \( \
        -name "*.desktop" -o \
        -name "*.sh" -o \
        -name "*.png" -o \
        -name "*.jpg" -o \
        -name "*.jpeg" -o \
        -name "*.svg" -o \
        -name "*.ico" -o \
        -name "*.txt" -o \
        -name "*.pdf" \
    \) | while read -r file; do
        local relative_path="${file#$source_path/}"
        local target_file="$target_path/$relative_path"
        local target_dir="$(dirname "$target_file")"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "同步文件: $file -> $target_file"
            continue
        fi
        
        # 创建目标目录
        mkdir -p "$target_dir"
        
        # 复制文件
        if cp "$file" "$target_file" 2>/dev/null; then
            # 修复.desktop文件中的路径
            if [[ "$file" == *.desktop ]]; then
                fix_desktop_file "$target_file" "$target_user"
            fi
            
            # 设置正确的所有者和权限
            chown "$target_user:$target_user" "$target_file"
            chmod 644 "$target_file"
            
            # 如果是可执行文件，设置执行权限
            if [[ "$file" == *.sh ]]; then
                chmod 755 "$target_file"
            fi
            
            sync_count=$((sync_count + 1))
            log_success "已同步: $(basename "$file")"
        else
            error_count=$((error_count + 1))
            log_error "同步失败: $file"
        fi
    done
    
    # 设置目录所有者
    if [[ "$DRY_RUN" == "false" ]]; then
        chown -R "$target_user:$target_user" "$target_path"
    fi
    
    return 0
}

# 修复desktop文件中的路径引用
fix_desktop_file() {
    local desktop_file=$1
    local target_user=$2
    local target_home="$BASE_USER_HOME/$target_user"
    
    if [[ ! -f "$desktop_file" ]]; then
        return 1
    fi
    
    log_info "修复desktop文件路径: $(basename "$desktop_file")"
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 替换路径中的用户名
    sed -e "s|/home/$SOURCE_USER|$target_home|g" \
        -e "s|Name=.*$SOURCE_USER.*|Name=$(basename "$desktop_file" .desktop)|g" \
        "$desktop_file" > "$temp_file"
    
    # 替换回原文件
    mv "$temp_file" "$desktop_file"
    chown "$target_user:$target_user" "$desktop_file"
}

# 同步应用程序图标
sync_application_icons() {
    local target_user=$1
    local target_home="$BASE_USER_HOME/$target_user"
    local source_icons_dir="/home/$SOURCE_USER/.local/share/icons"
    local target_icons_dir="$target_home/.local/share/icons"
    
    if [[ ! -d "$source_icons_dir" ]]; then
        log_info "源用户没有自定义图标目录"
        return 0
    fi
    
    log_info "同步应用程序图标到用户 $target_user..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "同步图标: $source_icons_dir -> $target_icons_dir"
        return 0
    fi
    
    mkdir -p "$target_icons_dir"
    
    # 同步图标文件
    if cp -r "$source_icons_dir"/* "$target_icons_dir/" 2>/dev/null; then
        chown -R "$target_user:$target_user" "$target_icons_dir"
        log_success "图标同步完成"
    else
        log_warning "图标同步失败或没有图标文件"
    fi
}

# 同步自启动应用
sync_autostart_apps() {
    local target_user=$1
    local target_home="$BASE_USER_HOME/$target_user"
    local source_autostart_dir="/home/$SOURCE_USER/.config/autostart"
    local target_autostart_dir="$target_home/.config/autostart"
    
    if [[ ! -d "$source_autostart_dir" ]]; then
        log_info "源用户没有自启动应用配置"
        return 0
    fi
    
    log_info "同步自启动应用到用户 $target_user..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "同步自启动: $source_autostart_dir -> $target_autostart_dir"
        return 0
    fi
    
    mkdir -p "$target_autostart_dir"
    
    # 同步自启动文件并修复路径
    find "$source_autostart_dir" -name "*.desktop" | while read -r file; do
        local target_file="$target_autostart_dir/$(basename "$file")"
        
        if cp "$file" "$target_file"; then
            fix_desktop_file "$target_file" "$target_user"
            log_success "已同步自启动: $(basename "$file")"
        else
            log_error "同步自启动失败: $(basename "$file")"
        fi
    done
    
    chown -R "$target_user:$target_user" "$target_autostart_dir"
}

# 创建同步报告
create_sync_report() {
    local report_file="$PROJECT_DIR/desktop_sync_report.txt"
    local target_users=("$@")
    
    cat > "$report_file" << EOF
KasmVNC桌面同步报告
==================
同步时间: $(date)
源用户: $SOURCE_USER
目标用户数量: ${#target_users[@]}
操作模式: $([ "$DRY_RUN" = true ] && echo "模拟运行" || echo "实际同步")

同步内容:
- 桌面文件 (.desktop, .sh, 图片等)
- 应用程序图标
- 自启动应用配置
- 路径自动修复

目标用户列表:
EOF

    for user in "${target_users[@]}"; do
        if [[ -n "$user" ]]; then
            echo "- $user" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

同步路径映射:
- 桌面文件: /home/$SOURCE_USER/Desktop -> $BASE_USER_HOME/[用户]/Desktop
- 应用图标: /home/$SOURCE_USER/.local/share/icons -> $BASE_USER_HOME/[用户]/.local/share/icons
- 自启动: /home/$SOURCE_USER/.config/autostart -> $BASE_USER_HOME/[用户]/.config/autostart

注意事项:
1. 所有文件路径已自动修复为目标用户路径
2. 文件所有者已设置为目标用户
3. 可执行文件权限已正确设置
4. .desktop文件中的路径引用已更新
EOF

    log_success "同步报告已生成: $report_file"
}

# 主函数
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "运行在模拟模式，不会实际修改文件"
    fi
    
    log_info "开始桌面同步操作..."
    log_info "源用户: $SOURCE_USER"
    log_info "目标用户: $([ "$TARGET_USERS" = "all" ] && echo "所有user*用户" || echo "$TARGET_USERS")"
    
    # 检查源用户是否存在
    if ! check_user_exists "$SOURCE_USER"; then
        exit 1
    fi
    
    # 获取源用户的桌面路径
    local source_desktop_paths=(
        "/home/$SOURCE_USER/Desktop"
        "/home/$SOURCE_USER/桌面"
    )
    
    # 获取目标用户列表
    local target_users=($(get_target_users))
    
    if [[ ${#target_users[@]} -eq 0 ]]; then
        log_error "未找到目标用户"
        exit 1
    fi
    
    log_info "找到 ${#target_users[@]} 个目标用户: ${target_users[*]}"
    
    # 为每个目标用户执行同步
    local success_count=0
    local total_count=${#target_users[@]}
    
    for target_user in "${target_users[@]}"; do
        if [[ -n "$target_user" ]]; then
            log_info "=========================================="
            log_info "处理用户: $target_user"
            
            # 检查目标用户是否存在
            if ! check_user_exists "$target_user"; then
                continue
            fi
            
            # 跳过源用户自己
            if [[ "$target_user" == "$SOURCE_USER" ]]; then
                log_info "跳过源用户: $target_user"
                continue
            fi
            
            # 设置目标用户的桌面环境
            setup_target_desktop "$target_user"
            
            # 同步桌面文件
            local user_success=true
            for source_path in "${source_desktop_paths[@]}"; do
                if [[ -d "$source_path" ]]; then
                    if ! sync_desktop_files "$source_path" "$target_user"; then
                        user_success=false
                    fi
                fi
            done
            
            # 同步应用程序图标
            if ! sync_application_icons "$target_user"; then
                user_success=false
            fi
            
            # 同步自启动应用
            if ! sync_autostart_apps "$target_user"; then
                user_success=false
            fi
            
            if [[ "$user_success" == "true" ]]; then
                success_count=$((success_count + 1))
                log_success "用户 $target_user 同步完成"
            else
                log_warning "用户 $target_user 同步部分失败"
            fi
        fi
    done
    
    echo ""
    echo "=========================================="
    log_info "桌面同步完成！"
    log_info "成功: $success_count/$total_count 个用户"
    
    # 生成同步报告
    create_sync_report "${target_users[@]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "这是模拟运行，没有实际修改文件"
        log_info "要执行实际同步，请移除 --dry-run 参数"
    fi
    
    # 提供后续操作建议
    echo ""
    log_info "后续操作建议:"
    log_info "1. 重启目标用户的VNC服务以加载新的桌面配置"
    log_info "2. 检查.desktop文件是否能正确启动应用程序"
    log_info "3. 验证自启动应用是否正常工作"
    
    if [[ $success_count -eq $total_count ]]; then
        exit 0
    else
        exit 1
    fi
}

# 参数处理和帮助信息
case "${1:-}" in
    -h|--help)
        echo "用法: $0 [源用户] [目标用户] [选项]"
        echo ""
        echo "参数说明:"
        echo "  源用户: 要复制桌面配置的源用户名 (默认: tang)"
        echo "  目标用户: 目标用户列表，用逗号分隔或'all' (默认: all)"
        echo ""
        echo "选项:"
        echo "  --dry-run    模拟运行，不实际修改文件"
        echo "  -h, --help   显示此帮助信息"
        echo ""
        echo "功能说明:"
        echo "  - 同步桌面文件和图标"
        echo "  - 同步应用程序启动器"
        echo "  - 同步自启动应用配置"
        echo "  - 自动修复文件路径引用"
        echo "  - 正确设置文件所有者和权限"
        echo ""
        echo "示例:"
        echo "  $0                           # 从tang同步到所有user*用户"
        echo "  $0 admin user1,user2,user3   # 从admin同步到指定用户"
        echo "  $0 tang all --dry-run        # 模拟运行，查看将要执行的操作"
        exit 0
        ;;
esac

# 执行主函数
main "$@"