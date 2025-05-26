#!/bin/bash

###############################################################################
#                                                                             #
#                         YOVOLE TECHNOLOGIES                                 #
#                                                                             #
#           TensorRT-LLM 集群部署工具 - 由有孚网络(YOVOLE)提供技术支持         #
#                                                                             #
#                      版权所有 (C) 2024 有孚网络科技                        #
#                          https://www.yovole.com                             #
#                                                                             #
###############################################################################

# 集群环境停止脚本
# 该脚本用于停止TensorRT-LLM集群节点的容器

# 颜色定义，用于输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 打印版权信息
print_copyright() {
    echo -e "${BLUE}${BOLD}"
    echo -e "###############################################################################"
    echo -e "#                                                                             #"
    echo -e "#                         YOVOLE TECHNOLOGIES                                 #"
    echo -e "#                                                                             #"
    echo -e "#           TensorRT-LLM 集群部署工具 - 由有孚网络(YOVOLE)提供技术支持         #"
    echo -e "#                                                                             #"
    echo -e "#                      版权所有 (C) 2024 有孚网络科技                        #"
    echo -e "#                          https://www.yovole.com                             #"
    echo -e "#                                                                             #"
    echo -e "###############################################################################${NC}"
    echo ""
}

# 先打印版权信息
print_copyright

# 设置Docker命令
DOCKER_CMD="docker"
CONTAINER_NAME="dsnode"

# 函数：输出信息
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 函数：输出警告
log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 函数：输出错误
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 函数：询问确认
confirm() {
    local question="$1"
    local default="$2"
    
    local prompt
    
    if [ "$default" = "y" ]; then
        prompt="$question [Y/n] "
    elif [ "$default" = "n" ]; then
        prompt="$question [y/N] "
    else
        prompt="$question [y/n] "
    fi
    
    # 直接读取用户输入
    echo -n -e "${YELLOW}${prompt}${NC}"
    read answer
    
    # 如果用户没有输入任何内容，使用默认值
    if [ -z "$answer" ]; then
        answer="$default"
    fi
    
    # 将输入转换为小写 (更兼容的方法)
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
    
    case "$answer" in
        y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 函数：检查容器是否存在
check_container_exists() {
    if ! $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_error "容器 $CONTAINER_NAME 不存在"
        return 1
    fi
    return 0
}

# 函数：检查容器运行状态
check_container_running() {
    # 多种方式检查容器状态
    local status=$($DOCKER_CMD ps -a --format '{{.Status}}' --filter "name=^${CONTAINER_NAME}$" 2>/dev/null | grep -v 'Exited' | wc -l | tr -d ' ')
    if [ "$status" -gt 0 ]; then
        return 0  # 容器运行中
    else
        return 1  # 容器未运行
    fi
}

# 函数：停止容器
stop_container() {
    log_info "正在停止容器 $CONTAINER_NAME..."
    
    # 尝试强制停止容器
    $DOCKER_CMD kill "$CONTAINER_NAME" &>/dev/null
    
    # 等待容器停止（最多5秒）
    local counter=0
    while check_container_running && [ $counter -lt 5 ]; do
        sleep 1
        counter=$((counter + 1))
    done
    
    # 检查是否成功停止
    if check_container_running; then
        log_error "强制停止容器失败，容器仍在运行"
        return 1
    else
        log_info "容器 $CONTAINER_NAME 已成功停止"
        return 0
    fi
}

# 函数：删除容器
remove_container() {
    log_info "正在删除容器 $CONTAINER_NAME..."
    
    # 删除容器
    if $DOCKER_CMD rm "$CONTAINER_NAME" &>/dev/null; then
        log_info "容器 $CONTAINER_NAME 已成功删除"
        return 0
    else
        log_error "删除容器失败"
        
        # 尝试强制删除
        if confirm "是否尝试强制删除容器 (docker rm -f)？" "y"; then
            if $DOCKER_CMD rm -f "$CONTAINER_NAME" &>/dev/null; then
                log_info "容器 $CONTAINER_NAME 已成功强制删除"
                return 0
            else
                log_error "强制删除容器失败"
                return 1
            fi
        else
            return 1
        fi
    fi
}

# 主函数
main() {
    log_info "TensorRT-LLM集群环境停止工具"
    
    # 检查容器是否存在
    if ! check_container_exists; then
        exit 1
    fi
    
    # 警告信息
    echo ""
    log_warn "注意: 停止并删除容器将中断所有正在运行的任务"
    log_warn "如果有正在进行的推理任务，它们将被终止，所有容器数据将被删除"
    echo ""
    
    # 询问确认
    if confirm "是否强制停止并彻底删除容器 $CONTAINER_NAME？" "n"; then
        echo ""
        
        # 首先停止容器
        if check_container_running; then
            stop_container
            if [ $? -ne 0 ]; then
                log_error "无法停止容器，操作中断"
                exit 1
            fi
        else
            log_info "容器已处于停止状态"
        fi
        
        # 然后删除容器
        remove_container
        if [ $? -eq 0 ]; then
            echo ""
            log_info "══════════════════════════════════════════════════════════════════"
            log_info "✅ 容器已成功停止并彻底删除"
            log_info "  如需重新创建容器，请运行 1-start-cluster-env.sh 脚本"
            log_info "══════════════════════════════════════════════════════════════════"
        else
            echo ""
            log_error "容器删除失败，可能需要手动干预："
            log_info "1. 使用系统管理员权限: sudo docker rm -f $CONTAINER_NAME"
            log_info "2. 重启Docker服务后再尝试删除"
        fi
    else
        echo ""
        log_info "操作已取消，容器将保持当前状态"
    fi
}

# 执行主函数
main 