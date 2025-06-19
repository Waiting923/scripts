#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges to run"
        exit 1
    fi
}

# 检测包管理器类型
detect_package_manager() {
    if command -v rpm >/dev/null 2>&1 && command -v yum >/dev/null 2>&1; then
        echo "rpm"
    elif command -v dpkg >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then
        echo "dpkg"
    else
        log_error "Unsupported package manager. This script supports RPM (yum) and DPKG (apt) systems"
        exit 1
    fi
}

# 检查qemu-guest-agent是否已安装
check_qemu_guest_agent() {
    local pkg_manager=$(detect_package_manager)
    
    if [[ "$pkg_manager" == "rpm" ]]; then
        if ! rpm -q qemu-guest-agent >/dev/null 2>&1; then
            log_error "qemu-guest-agent is not installed, please install the package first"
            exit 1
        fi
    elif [[ "$pkg_manager" == "dpkg" ]]; then
        if ! dpkg -l | grep -q "qemu-guest-agent"; then
            log_error "qemu-guest-agent is not installed, please install the package first"
            exit 1
        fi
    fi
}

# 检查ycloud-ga文件是否存在
check_ycloud_ga_file() {
    if [[ ! -f "/root/ycloud-ga" ]]; then
        log_error "ycloud-ga file not found in /root/, please place the ycloud-ga binary in /root/"
        exit 1
    fi
}

# 获取qemu-guest-agent安装的文件列表
get_qemu_guest_agent_files() {
    local pkg_manager=$(detect_package_manager)
    
    if [[ "$pkg_manager" == "rpm" ]]; then
        rpm -ql qemu-guest-agent 2>/dev/null
    elif [[ "$pkg_manager" == "dpkg" ]]; then
        dpkg -L qemu-guest-agent 2>/dev/null
    fi
}

# 停止qemu-ga进程
stop_qemu_ga_processes() {
    log_info "Stopping qemu-ga processes..."
    
    # 查找并停止qemu-ga进程
    local pids=$(pgrep -f "qemu-ga" 2>/dev/null)
    
    if [[ -n "$pids" ]]; then
        log_info "Found qemu-ga processes: $pids"
        
        # 尝试优雅停止
        for pid in $pids; do
            if kill -TERM "$pid" 2>/dev/null; then
                log_info "Sent SIGTERM to qemu-ga process $pid"
            fi
        done
        
        # 等待进程结束
        log_info "Waiting 10 seconds for processes to terminate..."
        sleep 10
        
        # 检查是否还有进程在运行
        pids=$(pgrep -f "qemu-ga" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            log_warn "Some qemu-ga processes are still running after 10 seconds, force killing..."
            
            # 强制杀死进程
            for pid in $pids; do
                if kill -KILL "$pid" 2>/dev/null; then
                    log_info "Force killed qemu-ga process $pid"
                fi
            done
            
            # 再次等待
            log_info "Waiting additional 5 seconds after force kill..."
            sleep 5
        fi
        
        # 最终检查
        pids=$(pgrep -f "qemu-ga" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            log_error "Failed to stop qemu-ga processes: $pids"
            log_error "Please manually stop these processes before continuing"
            exit 1
        else
            log_info "Successfully stopped all qemu-ga processes"
        fi
    else
        log_info "No qemu-ga processes found running"
    fi
}

# 备份原始文件
backup_files() {
    local backup_dir="/tmp/qemu-guest-agent-backup-$(date +%Y%m%d_%H%M%S)"
    log_info "Creating backup directory: $backup_dir"
    mkdir -p "$backup_dir"
    
    # 获取qemu-guest-agent安装的所有文件
    local files=$(get_qemu_guest_agent_files)
    
    if [[ -z "$files" ]]; then
        log_error "Unable to get file list from qemu-guest-agent package"
        exit 1
    fi
    
    # 备份相关文件
    for file in $files; do
        if [[ -f "$file" ]]; then
            local dir=$(dirname "$file")
            mkdir -p "$backup_dir$dir"
            cp -p "$file" "$backup_dir$file" 2>/dev/null && log_info "Backed up: $file"
        fi
    done
    
    echo "$backup_dir"
}

# 重命名文件和目录
rename_files_and_dirs() {
    local backup_dir="$1"
    
    # 获取qemu-guest-agent安装的所有文件
    local files=$(get_qemu_guest_agent_files)
    
    # 首先处理目录重命名（从最深层开始）
    local dirs_to_rename=()
    
    for file in $files; do
        if [[ -f "$file" ]]; then
            local dir=$(dirname "$file")
            # 检查路径中是否包含qemu-ga或qemu-guest-agent
            if echo "$dir" | grep -q "qemu-ga\|qemu-guest-agent"; then
                dirs_to_rename+=("$dir")
            fi
        fi
    done
    
    # 去重并排序（确保深层目录先处理）
    IFS=$'\n' dirs_to_rename=($(sort -u <<<"${dirs_to_rename[*]}" | sort -r))
    unset IFS
    
    # 重命名目录
    for dir in "${dirs_to_rename[@]}"; do
        if [[ -d "$dir" ]]; then
            local new_dir=$(echo "$dir" | sed 's|qemu-ga|ycloud-ga|g; s|qemu-guest-agent|ycloud-ga|g')
            if [[ "$dir" != "$new_dir" ]]; then
                log_info "Renaming directory: $dir -> $new_dir"
                
                # 备份原目录
                local backup_path="$backup_dir$dir"
                mkdir -p "$(dirname "$backup_path")"
                cp -r "$dir" "$backup_path" 2>/dev/null
                
                # 重命名目录
                mv "$dir" "$new_dir" 2>/dev/null
            fi
        fi
    done
    
    # 然后处理文件重命名
    for file in $files; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local dir=$(dirname "$file")
            
            # 检查文件名是否包含目标字符串
            if echo "$filename" | grep -q "qemu-ga\|qemu-guest-agent"; then
                local new_filename=$(echo "$filename" | sed 's/qemu-ga/ycloud-ga/g; s/qemu-guest-agent/ycloud-ga/g')
                local new_file="$dir/$new_filename"
                
                if [[ "$file" != "$new_file" ]]; then
                    log_info "Renaming file: $file -> $new_file"
                    
                    # 备份原文件
                    cp -p "$file" "$backup_dir$file" 2>/dev/null
                    
                    # 重命名文件
                    mv "$file" "$new_file" 2>/dev/null
                fi
            fi
        fi
    done
}

# 处理服务文件
process_service_files() {
    local backup_dir="$1"
    
    # 查找并处理服务文件
    find /etc/systemd/system /usr/lib/systemd/system -name "*qemu*ga*" -o -name "*qemu-guest-agent*" 2>/dev/null | while read -r service_file; do
        if [[ -f "$service_file" ]]; then
            log_info "Processing service file: $service_file"
            
            # 重命名服务文件
            local filename=$(basename "$service_file")
            local dir=$(dirname "$service_file")
            local new_filename=$(echo "$filename" | sed 's/qemu-ga/ycloud-ga/g; s/qemu-guest-agent/ycloud-ga/g')
            local new_service_file="$dir/$new_filename"
            
            if [[ "$service_file" != "$new_service_file" ]]; then
                mv "$service_file" "$new_service_file" 2>/dev/null
                log_info "Renamed service file: $service_file -> $new_service_file"
            fi
        fi
    done
}

# 更新ycloud-ga服务文件中的路径
update_ycloud_ga_service() {
    local service_file="/usr/lib/systemd/system/ycloud-ga.service"
    
    if [[ -f "$service_file" ]]; then
        log_info "Updating ycloud-ga service file: $service_file"
        
        # 创建临时文件
        local temp_file=$(mktemp)
        
        # 替换EnvironmentFile和ExecStart行中的qemu-ga为ycloud-ga
        sed 's|qemu-ga|ycloud-ga|g' "$service_file" > "$temp_file"
        
        # 检查是否有变化
        if diff "$service_file" "$temp_file" >/dev/null; then
            log_warn "No changes needed in service file $service_file"
        else
            # 备份原文件
            local backup_dir="/tmp/qemu-guest-agent-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir$(dirname "$service_file")"
            cp -p "$service_file" "$backup_dir$service_file" 2>/dev/null
            
            # 替换原文件
            mv "$temp_file" "$service_file"
            log_info "Updated service file: $service_file"
        fi
    else
        log_warn "Service file $service_file not found"
    fi
}

# 卸载qemu-guest-agent
remove_qemu_guest_agent() {
    local pkg_manager=$(detect_package_manager)
    
    log_info "Removing qemu-guest-agent package..."
    
    if [[ "$pkg_manager" == "rpm" ]]; then
        if yum -y remove qemu-guest-agent; then
            log_info "Successfully removed qemu-guest-agent package"
        else
            log_error "Failed to remove qemu-guest-agent package"
            exit 1
        fi
    elif [[ "$pkg_manager" == "dpkg" ]]; then
        if apt-get -y remove qemu-guest-agent; then
            log_info "Successfully removed qemu-guest-agent package"
        else
            log_error "Failed to remove qemu-guest-agent package"
            exit 1
        fi
    fi
}

# 安装ycloud-ga二进制文件
install_ycloud_ga_binary() {
    log_info "Installing ycloud-ga binary files..."
    
    # 复制到/usr/bin/
    if cp /root/ycloud-ga /usr/bin/ycloud-ga; then
        log_info "Copied ycloud-ga to /usr/bin/ycloud-ga"
    else
        log_error "Failed to copy ycloud-ga to /usr/bin/"
        exit 1
    fi
    
    # 复制到/usr/sbin/
    if cp /root/ycloud-ga /usr/sbin/ycloud-ga; then
        log_info "Copied ycloud-ga to /usr/sbin/ycloud-ga"
    else
        log_error "Failed to copy ycloud-ga to /usr/sbin/"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x /usr/bin/ycloud-ga /usr/sbin/ycloud-ga
    log_info "Set executable permissions for ycloud-ga"
}

# 启动ycloud-ga服务
start_ycloud_ga_service() {
    log_info "Starting ycloud-ga service..."
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    if systemctl enable ycloud-ga.service; then
        log_info "Enabled ycloud-ga service"
    else
        log_warn "Failed to enable ycloud-ga service"
    fi
    
    # 启动服务
    if systemctl start ycloud-ga.service; then
        log_info "Successfully started ycloud-ga service"
    else
        log_error "Failed to start ycloud-ga service"
        log_info "You can check the service status with: systemctl status ycloud-ga.service"
        exit 1
    fi
    
    # 显示服务状态
    log_info "ycloud-ga service status:"
    systemctl status ycloud-ga.service --no-pager -l
}

# 重新加载systemd
reload_systemd() {
    log_info "Reloading systemd configuration"
    systemctl daemon-reload
}

# 主函数
main() {
    log_info "Starting conversion from qemu-guest-agent to ycloud-ga"
    
    # 检查权限
    check_root
    
    # 检查软件包
    check_qemu_guest_agent
    
    # 检查ycloud-ga文件
    check_ycloud_ga_file
    
    # 创建备份
    local backup_dir=$(backup_files)
    log_info "Backup completed, backup directory: $backup_dir"
    
    # 重命名文件和目录
    log_info "Renaming files and directories..."
    rename_files_and_dirs "$backup_dir"
    
    # 处理服务文件
    log_info "Processing service files..."
    process_service_files "$backup_dir"
    
    # 更新ycloud-ga服务文件中的路径
    log_info "Updating ycloud-ga service file paths..."
    update_ycloud_ga_service
    
    # 重新加载systemd
    reload_systemd
    
    # 卸载qemu-guest-agent
    log_info "Removing original qemu-guest-agent package..."
    remove_qemu_guest_agent
    
    # 停止qemu-ga进程
    log_info "Stopping qemu-ga processes after package removal..."
    stop_qemu_ga_processes
    
    # 安装ycloud-ga二进制文件
    log_info "Installing ycloud-ga binary files..."
    install_ycloud_ga_binary
    
    # 启动ycloud-ga服务
    log_info "Starting ycloud-ga service..."
    start_ycloud_ga_service
    
    log_info "Conversion completed!"
    log_info "Backup location: $backup_dir"
    log_warn "Please check the conversion results, use backup files to restore if needed"
}

# 执行主函数
main "$@"