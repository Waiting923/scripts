#!/bin/bash
# 集群环境配置脚本
# 该脚本用于配置TensorRT-LLM集群的所有节点

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
    echo -e "#                                                                             #"
    echo -e "#           TensorRT-LLM 集群部署工具                                            #"
    echo -e "#                                                                             #"
    echo -e "#                                                                              #"
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

# 函数：打印环境变量
print_env_vars() {
    log_info "当前环境变量配置如下："
    echo -e "  🛠️ ${YELLOW}DOCKER_IMAGE${NC}    = ${DOCKER_IMAGE}"
    echo -e "  🛠️ ${YELLOW}SSH_PORT${NC}        = ${SSH_PORT}"
    echo -e "  🛠️ ${YELLOW}SERVER_PORT${NC}     = ${SERVER_PORT}"
    echo -e "  🛠️ ${YELLOW}SSHKEY_DIR${NC}      = ${SSHKEY_DIR}"
    echo -e "  🛠️ ${YELLOW}MODEL_REPO_DIR${NC}  = ${MODEL_REPO_DIR}"
    echo -e "  🛠️ ${YELLOW}IS_MASTER${NC}       = ${IS_MASTER}"
    echo -e "  🛠️ ${YELLOW}MASTER_ADDR${NC}     = ${MASTER_ADDR}"
    echo -e "  🛠️ ${YELLOW}MASTER_PORT${NC}     = ${MASTER_PORT}"
    echo -e "  🛠️ ${YELLOW}GLOO_SOCKET_IFNAME${NC}= ${GLOO_SOCKET_IFNAME}"
    echo -e "  🛠️ ${YELLOW}NCCL_SOCKET_IFNAME${NC}= ${NCCL_SOCKET_IFNAME}"
    echo -e "  🛠️ ${YELLOW}NCCL_IB_HCA${NC}      = ${NCCL_IB_HCA}"
    echo ""
}

# 环境变量加载及处理
load_env_vars() {
    # 加载环境变量（如果存在）
    ENV_FILE="$(dirname "$0")/.env"
    if [ -f "$ENV_FILE" ]; then
        # 使用点命令替代source命令，更兼容
        . "$ENV_FILE"
        log_info "已从$ENV_FILE加载环境变量"
    else
        log_warn "未找到.env文件，将使用默认值"
    fi

    # 设置默认值（如果未在.env中定义）
    DOCKER_IMAGE=${DOCKER_IMAGE:-"baseten/tensorrt_llm-release:0.19.0rc0"}
    CONTAINER_NAME=${CONTAINER_NAME:-"dsnode"}
    SSH_PORT=${SSH_PORT:-2233}
    SERVER_PORT=${SERVER_PORT:-8000}
    IS_MASTER=${IS_MASTER:-false}
    SSHKEY_DIR=${SSHKEY_DIR:-"$(dirname "$0")/sshkey"}
    MODEL_REPO_DIR=${MODEL_REPO_DIR:-"/mnt/share/deepseek-ai"}
    MASTER_ADDR=${MASTER_ADDR:-"10.83.0.101"}
    MASTER_PORT=${MASTER_PORT:-29500}
    GLOO_SOCKET_IFNAME=${GLOO_SOCKET_IFNAME:-"bond0"}
    NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME:-"bond0"}
    NCCL_IB_HCA=${NCCL_IB_HCA:-"mlx5_0,mlx5_1,mlx5_4,mlx5_5"}

    # 创建SSH密钥目录（如果不存在）
    mkdir -p "$SSHKEY_DIR"
}

# 函数：检查镜像是否存在
check_image() {
    local image_name="$1"
    log_info "检查镜像 $image_name 是否存在..."
    
    # 使用docker image ls -q命令进行精确匹配（包括标签）
    if [ -z "$($DOCKER_CMD image ls -q $image_name 2>/dev/null)" ]; then
        log_warn "镜像 $image_name 不存在，即将拉取(请去共享存储目录里面导入会比较快)..."
        if $DOCKER_CMD pull "$image_name"; then
            log_info "成功拉取镜像 $image_name"
        else
            log_error "无法拉取镜像 $image_name，请检查网络连接和镜像名称是否正确"
            return 1
        fi
    else
        log_info "镜像 $image_name 已存在"
    fi
    
    return 0
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

# 函数：清理旧容器
cleanup_old_container() {
    local container_name="$1"
    log_info "检查是否存在旧的 $container_name 容器..."
    
    if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
        log_warn "发现旧的 $container_name 容器"
        
        # 询问用户是否要停止和移除容器
        if ! confirm "是否停止并移除旧的容器?" "n"; then
            log_info "用户选择保留旧容器，退出脚本"
            exit 0
        fi
        
        log_info "正在停止和移除旧的 $container_name 容器..."
        
        # 停止容器并确认
        $DOCKER_CMD stop "$container_name" &>/dev/null
        if $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^$container_name$"; then
            log_warn "容器 $container_name 停止失败，尝试强制停止..."
            $DOCKER_CMD kill "$container_name" &>/dev/null
        fi
        
        # 等待容器完全停止
        local count=0
        while $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^$container_name$" && [ $count -lt 10 ]; do
            log_info "等待容器 $container_name 停止..."
            sleep 1
            count=$((count+1))
        done
        
        # 移除容器并确认
        $DOCKER_CMD rm "$container_name" &>/dev/null
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            log_warn "容器 $container_name 移除失败，尝试强制移除..."
            $DOCKER_CMD rm -f "$container_name" &>/dev/null
        fi
        
        # 等待容器完全移除
        count=0
        while $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$container_name$" && [ $count -lt 10 ]; do
            log_info "等待容器 $container_name 移除..."
            sleep 1
            count=$((count+1))
        done
        
        # 最终确认
        if $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
            log_error "无法移除容器 $container_name，请手动检查"
            return 1
        fi
        
        log_info "旧的 $container_name 容器已移除"
        
        # 等待系统释放资源
        log_info "等待系统释放资源..."
        sleep 3
    else
        log_info "未发现旧的 $container_name 容器"
    fi
    
    return 0
}

# 函数：生成SSH密钥对
generate_ssh_key() {
    log_info "检查SSH密钥对..."
    
    if [ ! -f "$SSHKEY_DIR/id_rsa" ]; then
        log_info "SSH密钥对不存在，正在生成..."
        ssh-keygen -t rsa -b 4096 -f "$SSHKEY_DIR/id_rsa" -N "" -C "deepseek-ai-ssh-key"
        
        if [ $? -ne 0 ]; then
            log_error "生成SSH密钥对失败"
            return 1
        fi
        
        log_info "SSH密钥对已生成到 $SSHKEY_DIR/id_rsa"
    else
        log_info "SSH密钥对已存在 $SSHKEY_DIR/id_rsa"
    fi
    
    # 将密钥权限设为600
    chmod 600 "$SSHKEY_DIR/id_rsa"
    chmod 644 "$SSHKEY_DIR/id_rsa.pub"
    
    return 0
}

# 函数：启动Docker容器
start_container() {
    log_info "正在启动容器 $CONTAINER_NAME..."
    
    # 启动Docker容器，映射SSH端口、工作目录和挂载GPU
    $DOCKER_CMD run -d --name "$CONTAINER_NAME" \
        --gpus all \
        -v "$SSHKEY_DIR:/root/.ssh" \
        -v "$MODEL_REPO_DIR:/workspace" \
        --restart unless-stopped \
        --privileged --device=/dev/infiniband:/dev/infiniband \
        -e GLOO_SOCKET_IFNAME=$GLOO_SOCKET_IFNAME \
        -e NCCL_SOCKET_IFNAME=$NCCL_SOCKET_IFNAME \
        -e NCCL_IB_HCA=$NCCL_IB_HCA \
        -e MASTER_ADDR=$MASTER_ADDR \
        -e MASTER_PORT=$MASTER_PORT \
        --ipc=host \
        --network host \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        "$DOCKER_IMAGE" \
        sleep infinity
    
    if [ $? -ne 0 ]; then
        log_error "启动容器失败，请检查错误信息"
        return 1
    fi
    
    # 等待容器完全启动
    sleep 3
    
    log_info "容器 $CONTAINER_NAME 启动成功"
    return 0
}

# 函数：配置SSH服务
configure_ssh() {
    log_info "配置SSH服务..."
    
    # 检查并安装SSH服务
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "if ! command -v sshd > /dev/null; then apt-get update && apt-get install -y openssh-server; fi"
    $DOCKER_CMD exec "$CONTAINER_NAME" mkdir -p /run/sshd
    
    # 拷贝公钥到容器中的authorized_keys文件
    $DOCKER_CMD exec "$CONTAINER_NAME" mkdir -p /root/.ssh
    cat "$SSHKEY_DIR/id_rsa.pub" | $DOCKER_CMD exec -i "$CONTAINER_NAME" tee /root/.ssh/authorized_keys >/dev/null
    $DOCKER_CMD exec "$CONTAINER_NAME" chmod 600 /root/.ssh/authorized_keys
    
    # 配置SSH服务，监听自定义端口
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "echo 'Port $SSH_PORT' >> /etc/ssh/sshd_config"
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "echo 'StrictModes no' >> /etc/ssh/sshd_config"
    
    # 启动SSH服务
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "nohup /usr/sbin/sshd -D > /dev/null 2>&1 &"
    
    # 给SSH服务一些启动时间
    sleep 2
    
    log_info "SSH服务配置完成，监听端口：$SSH_PORT"
    return 0
}

# 函数：测试SSH连接
test_ssh_connection() {
    log_info "测试SSH免密连接..."
    
    # 等待SSH服务启动
    sleep 2
    
    # 测试SSH连接
    $DOCKER_CMD exec "$CONTAINER_NAME" ssh -i /root/.ssh/id_rsa -p $SSH_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost echo "SSH连接测试成功" &>/dev/null
    
    if [ $? -ne 0 ]; then
        log_error "SSH连接测试失败，请检查SSH配置"
        return 1
    fi
    
    log_info "SSH连接测试成功"
    return 0
}

# 函数：安装额外依赖（仅主节点）
install_extras() {
    if [ "$IS_MASTER" = true ]; then
        log_info "安装主节点额外依赖..."
        
        # 安装MPICH
        $DOCKER_CMD exec "$CONTAINER_NAME" apt-get update
        $DOCKER_CMD exec "$CONTAINER_NAME" apt-get install -y mpich
        
        log_info "主节点额外依赖安装完成"
    else
        log_info "非主节点，跳过额外依赖安装"
    fi
    
    return 0
}

# 主函数
main() {
    log_info "开始配置TensorRT-LLM集群环境..."
    
    # 清理旧容器
    cleanup_old_container "$CONTAINER_NAME"

    # 加载环境变量
    load_env_vars

    # 打印环境变量
    print_env_vars

    # 检查镜像是否存在
    check_image "$DOCKER_IMAGE"
    if [ $? -ne 0 ]; then
        log_error "镜像检查失败，无法继续"
        return 1
    fi
    
    # 生成SSH密钥对
    generate_ssh_key
    if [ $? -ne 0 ]; then
        log_error "SSH密钥生成失败，无法继续"
        return 1
    fi
    
    # 启动新容器
    if ! start_container; then
        exit 1
    fi

    # 配置SSH服务
    configure_ssh
    if [ $? -ne 0 ]; then
        log_error "SSH服务配置失败，无法继续"
        return 1
    fi
    
    # 测试SSH连接
    test_ssh_connection
    if [ $? -ne 0 ]; then
        log_error "SSH连接测试失败，无法继续"
        return 1
    fi
    
    # 安装额外依赖
    install_extras
    
    # 获取容器IP地址
    container_ip=$($DOCKER_CMD inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
    
    # 获取宿主机IP地址
    host_ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    log_info "══════════════════════════════════════════════════════════════════"
    log_info "✅ TensorRT-LLM集群环境配置完全成功 ✅"
    log_info "  容器名称: ${BOLD}$CONTAINER_NAME${NC}"
    log_info "  宿主机IP地址: ${BOLD}$host_ip${NC}"
    log_info "  SSH端口: ${BOLD}$SSH_PORT${NC}"
    log_info "  服务端口: ${BOLD}$SERVER_PORT${NC}"
    log_info "  镜像: ${BOLD}$DOCKER_IMAGE${NC}"
    log_info "  挂载的模型仓库: ${BOLD}$MODEL_REPO_DIR${NC}"
    log_info "══════════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "请使用脚本 2-check-cluster-env.sh 检查环境是否正确配置"
    
    # 提示后续步骤
    echo ""
    if [ "$IS_MASTER" = true ]; then
        log_info "该节点配置为主节点，后续步骤："
        log_info "1. 在所有工作节点上运行此脚本"
        log_info "2. 运行 2-check-cluster-env.sh 确认环境正确配置, 并把宿主机IP复制到主节点的configuration/hostfile中"
        log_info "3. 修改configuration中的文件，然后执行3-setup-node-config.sh上传配置。"
        log_info "4. 执行4-start-trt-server.sh启动推理服务，可以sh 4-start-trt-server.sh --help查看帮助"
    else
        log_info "该节点配置为工作节点，后续步骤："
        log_info "1. 运行 2-check-cluster-env.sh 确认环境正确配置, 并把宿主机IP复制到主节点的configuration/hostfile中"
        log_info "2. 修改configuration中的文件，然后执行3-setup-node-config.sh上传配置。"
        log_info "3. 等待主节点启动推理服务"
    fi
    
    return 0
}

# 执行主函数
main 