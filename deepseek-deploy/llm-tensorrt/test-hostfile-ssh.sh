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

# TensorRT-LLM Hostfile SSH连接测试脚本
# 该脚本用于测试TensorRT-LLM集群中hostfile所列节点的SSH连接

# 颜色定义，用于输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 设置带样式的日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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

# 加载环境变量（如果存在）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    # 使用点命令替代source命令，更兼容
    . "$ENV_FILE"
    log_info "已从$ENV_FILE加载环境变量"
else
    log_warn "未找到.env文件，将使用默认值"
fi

# 设置默认参数（如果未在.env中定义）
CONTAINER_NAME=${CONTAINER_NAME:-"dsnode"}
SSH_PORT=${SSH_PORT:-2233}
HOSTFILE=${HOSTFILE:-"/hostfile"}
HOST_TEST=${HOST_TEST:-false}  # 默认只测试容器内连接，不测试宿主机连接

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

# 函数：检查容器是否存在并运行
check_container_running() {
    log_info "检查$CONTAINER_NAME容器是否存在并运行..."
    
    # 检查容器是否存在
    if ! $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_error "$CONTAINER_NAME容器不存在，请先运行1-start-cluster-env.sh脚本创建容器"
        return 1
    fi
    
    # 检查容器是否运行中
    if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_error "$CONTAINER_NAME容器存在但未运行，请手动启动容器: $DOCKER_CMD start $CONTAINER_NAME"
        return 1
    fi
    
    log_info "$CONTAINER_NAME容器正在运行"
    return 0
}

# 函数：检查hostfile是否存在
check_hostfile() {
    log_info "检查hostfile文件是否存在: $HOSTFILE"
    
    if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -f "$HOSTFILE"; then
        log_error "容器内未找到hostfile文件: $HOSTFILE"
        return 1
    fi
    
    log_info "hostfile文件存在: $HOSTFILE"
    return 0
}

# 函数：检查hostfile中的SSH连通性
test_ssh_connectivity() {
    log_info "开始检查hostfile中的SSH连通性..."
    
    # 读取hostfile内容
    local hostfile_content=$($DOCKER_CMD exec "$CONTAINER_NAME" cat "$HOSTFILE")
    if [ -z "$hostfile_content" ]; then
        log_error "hostfile文件为空"
        return 1
    fi
    
    # 使用临时文件存储节点信息，避免使用数组
    local tmp_valid_ips="/tmp/valid_ips.$$"
    local tmp_node_infos="/tmp/node_infos.$$"
    local tmp_container_failed="/tmp/container_failed.$$"
    local tmp_host_failed="/tmp/host_failed.$$"
    
    cat /dev/null > "$tmp_valid_ips"
    cat /dev/null > "$tmp_node_infos"
    cat /dev/null > "$tmp_container_failed"
    cat /dev/null > "$tmp_host_failed"
    
    local node_count=0
    
    log_info "解析hostfile中的节点列表..."
    
    echo "$hostfile_content" | while IFS= read -r line; do
        # 跳过空行和注释行
        if [ -z "$line" ] || echo "$line" | grep -q "^[[:space:]]*#"; then
            continue
        fi
        
        # 提取IP地址（第一列）
        local ip=$(echo "$line" | awk '{print $1}')
        if [ -z "$ip" ]; then
            continue
        fi
        
        # 提取slots信息（如果有）
        local slots=$(echo "$line" | grep -o "slots=[0-9]*" | cut -d= -f2)
        if [ -z "$slots" ]; then
            slots="未指定"
        fi
        
        # 计数并保存信息到临时文件
        node_count=$((node_count+1))
        echo "$ip" >> "$tmp_valid_ips"
        echo "Node-$node_count: $ip (Slots: $slots)" >> "$tmp_node_infos"
    done
    
    # 获取节点数量
    node_count=$(cat "$tmp_valid_ips" | wc -l)
    
    # 显示所有节点信息
    echo ""
    log_info "集群节点信息 (共$node_count个节点):"
    cat "$tmp_node_infos" | while IFS= read -r node_info; do
        echo -e "  ${BLUE}$node_info${NC}"
    done
    echo ""
    
    # 如果没有有效IP，报错并退出
    if [ $node_count -eq 0 ]; then
        log_error "hostfile中未找到有效的IP地址"
        rm -f "$tmp_valid_ips" "$tmp_node_infos" "$tmp_container_failed" "$tmp_host_failed"
        return 1
    fi
    
    # 开始测试SSH连接
    log_info "开始测试SSH连接到每个节点 (使用端口: $SSH_PORT)..."
    echo ""
    
    # 逐个测试SSH连接（容器内）
    log_info "从容器内测试连接:"
    local i=0
    cat "$tmp_valid_ips" | while IFS= read -r ip; do
        i=$((i+1))
        local node_info=$(sed -n "${i}p" "$tmp_node_infos")
        
        echo -n -e "  测试容器内连接 ${YELLOW}$node_info${NC} ... "
        
        # 尝试SSH连接，显示更详细的错误信息
        local ssh_output
        ssh_output=$($DOCKER_CMD exec "$CONTAINER_NAME" ssh -i /root/.ssh/id_rsa -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" "echo 连接测试成功" 2>&1)
        local ssh_status=$?
        
        if [ $ssh_status -eq 0 ]; then
            echo -e "${GREEN}成功${NC}"
        else
            echo -e "${RED}失败 - $ssh_output${NC}"
            echo "$ip" >> "$tmp_container_failed"
        fi
    done
    
    # 如果用户要求宿主机测试，则从宿主机测试连接
    if [ "$HOST_TEST" = "true" ]; then
        echo ""
        log_info "从宿主机测试连接:"
        
        # 先检查宿主机是否有ssh命令
        if ! command -v ssh >/dev/null 2>&1; then
            log_warn "宿主机未安装SSH客户端，跳过宿主机连接测试"
        else
            # 复制SSH密钥到临时位置
            local tmp_key="/tmp/trtllm_id_rsa.$$"
            $DOCKER_CMD cp "$CONTAINER_NAME:/root/.ssh/id_rsa" "$tmp_key"
            chmod 600 "$tmp_key"
            
            # 逐个测试SSH连接（宿主机）
            cat "$tmp_valid_ips" | while IFS= read -r ip; do
                local node_info=$(grep "$ip" "$tmp_node_infos")
                if [ -z "$node_info" ]; then
                    node_info="$ip"
                fi
                
                echo -n -e "  测试宿主机连接 ${YELLOW}$node_info${NC} ... "
                
                # 尝试SSH连接，显示详细错误
                local ssh_output
                ssh_output=$(ssh -i "$tmp_key" -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" "echo 连接测试成功" 2>&1)
                local ssh_status=$?
                
                if [ $ssh_status -eq 0 ]; then
                    echo -e "${GREEN}成功${NC}"
                else
                    echo -e "${RED}失败 - $ssh_output${NC}"
                    echo "$ip" >> "$tmp_host_failed"
                fi
            done
            
            # 删除临时密钥
            rm -f "$tmp_key"
        fi
    fi
    
    # 重新计算结果
    local container_success_count=$(($node_count - $(cat "$tmp_container_failed" | wc -l)))
    local container_failure_count=$(cat "$tmp_container_failed" | wc -l)
    
    # 显示测试总结
    echo ""
    log_info "容器内连接测试结果: 成功 $container_success_count/$node_count"
    
    if [ "$HOST_TEST" = "true" ] && [ -f "$tmp_host_failed" ]; then
        local host_success_count=$(($node_count - $(cat "$tmp_host_failed" | wc -l)))
        local host_failure_count=$(cat "$tmp_host_failed" | wc -l)
        log_info "宿主机连接测试结果: 成功 $host_success_count/$node_count"
    fi
    
    # 汇总结果，如果任一测试有问题，就报错
    local has_failure=0
    if [ $container_failure_count -gt 0 ]; then
        has_failure=1
        log_error "容器内连接测试失败。失败的节点:"
        cat "$tmp_container_failed" | while IFS= read -r failed_ip; do
            echo -e "  ${RED}$failed_ip${NC}"
        done
    fi
    
    if [ "$HOST_TEST" = "true" ] && [ -f "$tmp_host_failed" ] && [ $(cat "$tmp_host_failed" | wc -l) -gt 0 ]; then
        has_failure=1
        log_error "宿主机连接测试失败。失败的节点:"
        cat "$tmp_host_failed" | while IFS= read -r failed_ip; do
            echo -e "  ${RED}$failed_ip${NC}"
        done
    fi
    
    if [ $has_failure -eq 1 ]; then
        # 提供一些建议
        echo ""
        echo -e "${YELLOW}请检查以下可能的原因:${NC}"
        echo -e "  ${YELLOW}1. 确保所有节点的容器都已正确启动${NC}"
        echo -e "  ${YELLOW}2. 确保所有节点的SSH服务在指定端口($SSH_PORT)上正确运行${NC}"
        echo -e "  ${YELLOW}3. 确保所有节点都已正确配置SSH密钥${NC}"
        echo -e "  ${YELLOW}4. 确保网络连接正常，没有防火墙阻止${NC}"
        echo -e "  ${YELLOW}5. 检查容器网络和宿主机网络是否可以互通${NC}"
        echo -e "  ${YELLOW}6. 可以使用以下命令进行调试:${NC}"
        
        if [ $container_failure_count -gt 0 ]; then
            cat "$tmp_container_failed" | while IFS= read -r failed_ip; do
                echo -e "     ${YELLOW}docker exec $CONTAINER_NAME ssh -v -i /root/.ssh/id_rsa -p $SSH_PORT root@$failed_ip${NC}"
            done
        fi
        
        if [ "$HOST_TEST" = "true" ] && [ -f "$tmp_host_failed" ] && [ $(cat "$tmp_host_failed" | wc -l) -gt 0 ]; then
            cat "$tmp_host_failed" | while IFS= read -r failed_ip; do
                echo -e "     ${YELLOW}ssh -v -i id_rsa -p $SSH_PORT root@$failed_ip${NC}"
            done
        fi
        
        # 清理临时文件
        rm -f "$tmp_valid_ips" "$tmp_node_infos" "$tmp_container_failed" "$tmp_host_failed"
        
        # 询问是否继续
        echo ""
        if confirm "是否忽略SSH连接问题并继续?" "n"; then
            log_warn "用户选择忽略SSH连接问题并继续"
            return 0
        else
            log_error "用户选择停止，退出执行"
            return 1
        fi
    else
        log_info "${GREEN}所有SSH连接测试成功通过${NC}"
        # 清理临时文件
        rm -f "$tmp_valid_ips" "$tmp_node_infos" "$tmp_container_failed" "$tmp_host_failed"
        return 0
    fi
}

# 函数：显示帮助信息
show_help() {
    echo -e "${BOLD}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${BOLD}选项:${NC}"
    echo -e "  ${YELLOW}-h, --help${NC}                显示此帮助信息"
    echo -e "  ${YELLOW}-c, --container NAME${NC}      指定容器名称 (默认: $CONTAINER_NAME)"
    echo -e "  ${YELLOW}-p, --port PORT${NC}           指定SSH端口 (默认: $SSH_PORT)"
    echo -e "  ${YELLOW}-f, --hostfile PATH${NC}       指定hostfile路径 (默认: $HOSTFILE)"
    echo -e "  ${YELLOW}--host-test${NC}               同时从宿主机测试连接"
    echo -e "  ${YELLOW}--no-host-test${NC}            只测试容器内连接，不测试宿主机连接 (默认)"
    echo ""
    echo -e "${BOLD}示例:${NC}"
    echo -e "  ${YELLOW}$0${NC}                        使用默认设置测试容器内SSH连接"
    echo -e "  ${YELLOW}$0 -p 22${NC}                  使用端口22测试SSH连接"
    echo -e "  ${YELLOW}$0 -f /custom/hostfile${NC}    测试自定义hostfile中的节点"
    echo -e "  ${YELLOW}$0 --host-test${NC}            同时测试容器内和宿主机连接"
    echo ""
}

# 主函数
main() {
    log_info "开始测试hostfile中的SSH连接..."
    
    # 打印当前设置
    log_info "当前设置:"
    echo -e "  ${YELLOW}容器名称:${NC} $CONTAINER_NAME"
    echo -e "  ${YELLOW}SSH端口:${NC} $SSH_PORT"
    echo -e "  ${YELLOW}Hostfile路径:${NC} $HOSTFILE"
    echo ""
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法继续"
        exit 1
    fi
    
    # 检查hostfile文件
    check_hostfile
    if [ $? -ne 0 ]; then
        log_error "hostfile文件检查失败，无法继续"
        exit 1
    fi
    
    # 测试SSH连接
    test_ssh_connectivity
    if [ $? -ne 0 ]; then
        log_error "SSH连接测试发现问题"
        exit 1
    else
        log_info "SSH连接测试全部通过"
        exit 0
    fi
}

# 解析命令行参数
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -f|--hostfile)
            HOSTFILE="$2"
            shift 2
            ;;
        --host-test)
            HOST_TEST=true
            shift
            ;;
        --no-host-test)
            HOST_TEST=false
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 执行主函数
main 