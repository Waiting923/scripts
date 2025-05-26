#!/bin/bash

###############################################################################
#                                                                             #
#                         YOVOLE TECHNOLOGIES                                 #
#                                                                             #
#           TensorRT-LLM 集群部署工具 - 由有孚网络(YOVOLE)提供技术支持              #
#                                                                             #
#                      版权所有 (C) 2024 有孚网络科技                            #
#                          https://www.yovole.com                             #
#                                                                             #
###############################################################################

# 集群环境检查脚本
# 该脚本用于检查TensorRT-LLM集群节点的环境配置是否正常

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
    echo -e "#                      版权所有 (C) 2024 有孚网络科技👍👏❗                     #"
    echo -e "#                          https://www.yovole.com                             #"
    echo -e "#                                                                             #"
    echo -e "###############################################################################${NC}"
    echo ""
}

# 先打印版权信息
print_copyright

# 加载环境变量（如果存在）
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    # 使用点命令替代source命令，更兼容
    . "$ENV_FILE"
else
    echo -e "${RED}[ERROR]${NC} 未找到.env文件，将使用默认值"
fi

# 设置默认值（如果未在.env中定义）
DOCKER_IMAGE=${DOCKER_IMAGE:-"baseten/tensorrt_llm-release:0.19.0rc0"}
SSH_PORT=${SSH_PORT:-2233}
IS_MASTER=${IS_MASTER:-false}
SSHKEY_DIR=${SSHKEY_DIR:-"$(dirname "$0")/sshkey"}
MODEL_REPO_DIR=${MODEL_REPO_DIR:-"/mnt/share/deepseek-ai"}
MASTER_ADDR=${MASTER_ADDR:-"10.83.0.101"}
MASTER_PORT=${MASTER_PORT:-29500}
GLOO_SOCKET_IFNAME=${GLOO_SOCKET_IFNAME:-"bond0"}
NCCL_SOCKET_IFNAME=${NCCL_SOCKET_IFNAME:-"bond0"}
NCCL_IB_HCA=${NCCL_IB_HCA:-"mlx5_0,mlx5_1,mlx5_4,mlx5_5"}

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

# 函数：输出检查结果
log_check() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}[PASS]${NC} $2"
    else
        echo -e "${RED}[FAIL]${NC} $2"
    fi
}

# 函数：打印环境变量
print_env_vars() {
    log_info "当前环境变量配置如下："
    echo -e "  🛠️ ${YELLOW}DOCKER_IMAGE${NC}    = ${DOCKER_IMAGE}"
    echo -e "  🛠️ ${YELLOW}SSH_PORT${NC}        = ${SSH_PORT}"
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

# 函数：检查容器是否存在并运行
check_container_running() {
    log_info "检查dsnode容器是否存在并运行..."
    
    # 检查容器是否存在
    if ! $DOCKER_CMD ps -a --format '{{.Names}}' | grep -q "^dsnode$"; then
        log_error "dsnode容器不存在，请先运行1-start-cluster-env.sh脚本创建容器"
        return 1
    fi
    
    # 检查容器是否运行中
    if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^dsnode$"; then
        log_error "dsnode容器存在但未运行，请手动启动容器: $DOCKER_CMD start dsnode"
        return 1
    fi
    
    log_check 0 "dsnode容器正在运行"
    return 0
}

# 函数：检查SSH服务
check_ssh_service() {
    log_info "检查SSH服务是否正常..."
    
    # 直接通过SSH连接测试来验证SSH服务是否可用
    if $DOCKER_CMD exec dsnode bash -c "ssh -i /root/.ssh/id_rsa -p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost echo 'SSH_TEST_OK'" &>/dev/null; then
        log_check 0 "SSH服务正常，监听端口 ${SSH_PORT}"
        return 0
    else
        # 检查容器中SSH服务是否运行
        if ! $DOCKER_CMD exec dsnode ps aux | grep -v grep | grep -q "sshd"; then
            # 更宽松的检查，查找任何与sshd相关的进程
            if ! $DOCKER_CMD exec dsnode ps aux | grep -v grep | grep -q "ssh"; then
                log_error "容器中SSH服务未运行，请手动启动: $DOCKER_CMD exec dsnode /usr/sbin/sshd"
                return 1
            fi
        fi
        
        # 检查SSH端口是否监听
        if ! $DOCKER_CMD exec dsnode bash -c "netstat -tuln 2>/dev/null | grep -q ':${SSH_PORT}' || ss -tuln 2>/dev/null | grep -q ':${SSH_PORT}' || lsof -i :${SSH_PORT} 2>/dev/null | grep -q LISTEN"; then
            # 尝试启动SSH服务
            log_warn "未检测到SSH服务在端口 ${SSH_PORT} 上监听，尝试启动服务..."
            $DOCKER_CMD exec dsnode bash -c "nohup /usr/sbin/sshd -D > /dev/null 2>&1 &" || true
            sleep 2
        fi
        
        # 再次通过SSH连接测试来验证SSH服务是否可用
        if $DOCKER_CMD exec dsnode bash -c "ssh -i /root/.ssh/id_rsa -p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost echo 'SSH_TEST_OK'" &>/dev/null; then
            log_check 0 "SSH服务正常，已验证可以正常连接"
            return 0
        else
            log_error "SSH服务未在端口 ${SSH_PORT} 上监听，请检查SSH配置"
            return 1
        fi
    fi
}

# 函数：测试SSH连接
test_ssh_connection() {
    log_info "测试SSH免密连接..."
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${BLUE}│${NC} %-66s ${BLUE}│${NC}\n" "检查本地SSH密钥..."
    
    # 检查SSH密钥是否存在
    if [ ! -f "${SSHKEY_DIR}/id_rsa" ]; then
        printf "${BLUE}│${NC} ${RED}%-66s${NC} ${BLUE}│${NC}\n" "[FAIL] SSH私钥不存在: ${SSHKEY_DIR}/id_rsa"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        log_error "请确保SSH密钥已生成"
        return 1
    fi
    printf "${BLUE}│${NC} ${GREEN}%-66s${NC} ${BLUE}│${NC}\n" "[PASS] SSH私钥存在: ${SSHKEY_DIR}/id_rsa"

    printf "${BLUE}│${NC} %-66s ${BLUE}│${NC}\n" "尝试连接到本地容器 (root@localhost:$SSH_PORT)..."
    
    # 测试SSH连接到本地容器
    local ssh_output
    local ssh_status
    ssh_output=$($DOCKER_CMD exec dsnode bash -c "ssh -i /root/.ssh/id_rsa -p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost echo 'SSH连接测试成功' 2>&1")
    ssh_status=$?

    if [ $ssh_status -eq 0 ]; then
        printf "${BLUE}│${NC} ${GREEN}%-66s${NC} ${BLUE}│${NC}\n" "[PASS] SSH连接测试成功"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        return 0
    fi
    
    # 如果第一次测试失败，等待几秒钟再试一次
    printf "${BLUE}│${NC} ${YELLOW}%-66s${NC} ${BLUE}│${NC}\n" "[WARN] SSH连接测试失败，等待3秒后重试..."
    sleep 3
    
    # 再次测试
    ssh_output=$($DOCKER_CMD exec dsnode bash -c "ssh -i /root/.ssh/id_rsa -p ${SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost echo 'SSH连接测试成功' 2>&1")
    ssh_status=$?
    
    if [ $ssh_status -eq 0 ]; then
        printf "${BLUE}│${NC} ${GREEN}%-66s${NC} ${BLUE}│${NC}\n" "[PASS] SSH连接测试成功 (重试后)"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        return 0
    else
        printf "${BLUE}│${NC} ${RED}%-66s${NC} ${BLUE}│${NC}\n" "[FAIL] SSH连接测试失败 (重试后)"
        printf "${BLUE}│${NC}   错误信息: %-58s ${BLUE}│${NC}\n" "$ssh_output"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        log_error "请检查SSH配置和密钥"
        return 1
    fi
}

# 函数：检查GPU可用性
check_gpu_available() {
    log_info "检查GPU是否可用..."
    
    # 直接通过运行nvidia-smi来检查GPU是否可用
    if $DOCKER_CMD exec dsnode bash -c "nvidia-smi &>/dev/null"; then
        log_check 0 "GPU可用，已验证nvidia-smi可以正常运行"
        return 0
    fi
    
    # 如果直接运行失败，尝试找到命令位置
    nvidia_smi_path=$($DOCKER_CMD exec dsnode bash -c "command -v nvidia-smi || find /usr/bin /usr/local/bin -name nvidia-smi 2>/dev/null | head -1")
    
    if [ -z "$nvidia_smi_path" ]; then
        log_warn "容器中未找到nvidia-smi命令，可能没有启用GPU支持"
        return 1
    fi
    
    # 使用完整路径尝试运行
    if $DOCKER_CMD exec dsnode bash -c "$nvidia_smi_path &>/dev/null"; then
        log_check 0 "GPU可用，已通过路径 $nvidia_smi_path 验证"
        return 0
    else
        log_error "无法访问GPU，请检查GPU驱动和nvidia-docker配置"
        return 1
    fi
}

# 函数：检查MPICH（仅主节点）
check_mpich() {
    if [ "$IS_MASTER" = true ]; then
        log_info "检查MPICH是否已安装（主节点）..."
        
        # 检查mpirun命令是否存在（扩展搜索路径）
        if ! $DOCKER_CMD exec dsnode bash -c "command -v mpirun || find /usr/bin /usr/local/bin /usr/local/mpi/bin -name mpirun 2>/dev/null"; then
            log_error "MPICH未安装或未正确配置，请检查"
            return 1
        fi
        
        log_check 0 "MPICH已正确安装"
    else
        log_info "非主节点，跳过MPICH检查"
    fi
    return 0
}

# 函数：检查工作目录挂载
check_workspace_mount() {
    log_info "检查模型仓库目录挂载..."
    
    # 检查/workspace目录是否存在且有内容
    if $DOCKER_CMD exec dsnode bash -c "ls -la /workspace &>/dev/null && [ \$(ls -A /workspace 2>/dev/null | wc -l) -gt 0 ]"; then
        log_check 0 "模型仓库目录已正确挂载: /workspace"
        
        # 获取并打印子目录列表 (美化输出)
        echo -e "${BLUE}[INFO]${NC} /workspace 目录内容:"
        echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────┐${NC}"

        local dir_list=$($DOCKER_CMD exec dsnode bash -c "find /workspace -maxdepth 1 -type d -not -path '/workspace' -printf '%f\\n' | sort")

        if [ -z "$dir_list" ]; then
            printf "${BLUE}│${NC} %-66s ${BLUE}│${NC}\n" "(/workspace 目录为空或只有隐藏文件)"
        else
            echo "$dir_list" | while IFS= read -r dir_name; do
                printf "${BLUE}│${NC} %-66s ${BLUE}│${NC}\n" "- $dir_name"
            done
        fi

        echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        return 0
    else
        log_error "工作目录未正确挂载或为空: /workspace，请检查挂载配置"
        return 1
    fi
}

# 函数：检查CUDA版本和驱动兼容性
check_cuda_compatibility() {
    log_info "检查CUDA版本和驱动兼容性..."
    
    # 获取容器内CUDA版本
    local cuda_version=$($DOCKER_CMD exec dsnode nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | cut -d',' -f1)
    if [ -z "$cuda_version" ]; then
        log_warn "无法获取容器内CUDA版本，可能CUDA工具包未正确安装"
        return 1
    fi
    
    # 获取主机NVIDIA驱动版本
    local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1)
    if [ -z "$driver_version" ]; then
        log_warn "无法获取主机NVIDIA驱动版本"
        return 1
    fi
    
    # 获取容器需要的最低驱动版本（从nvidia-smi输出中解析）
    local required_driver=$($DOCKER_CMD exec dsnode nvidia-smi 2>&1 | grep "NVIDIA Driver Release" | grep -oP "(?<=Release )[0-9.]+" | head -n 1)
    if [ -n "$required_driver" ] && [ "$(printf '%s\n' "$required_driver" "$driver_version" | sort -V | head -n 1)" != "$required_driver" ]; then
        log_error "驱动不兼容: 容器需要NVIDIA驱动 $required_driver 或更高版本，但当前版本为 $driver_version"
        log_error "请升级NVIDIA驱动或使用与当前驱动兼容的容器镜像"
        return 1
    fi
    
    log_check 0 "CUDA版本: $cuda_version, 驱动版本: $driver_version, 兼容性检查通过"
    return 0
}

# 函数：获取容器IP地址
get_container_ip() {
    log_info "获取$CONTAINER_NAME容器IP地址..."
    
    local container_ip=$($DOCKER_CMD inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
    
    if [ -z "$container_ip" ]; then
        log_warn "无法获取$CONTAINER_NAME容器的IP地址，尝试使用宿主机IP"
        container_ip=$(hostname -I | awk '{print $1}')
        if [ -z "$container_ip" ]; then
            log_error "无法获取IP地址，网络配置可能有问题"
            return 1
        fi
    fi
    
    log_info "容器IP地址: $container_ip"
    # 获取宿主机IP地址（作为参考）
    local host_ip=$(hostname -I | awk '{print $1}')
    log_info "宿主机IP地址: $host_ip"
    
    echo "$container_ip"
    return 0
}

# 主函数
main() {
    log_info "开始检查TensorRT-LLM集群环境..."
    print_env_vars
    
    # 定义检查项目状态变量
    local errors=0
    local warnings=0
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法继续执行后续检查"
        log_error "请先确保dsnode容器正常运行"
        echo ""
        log_error "环境检查中断：${RED}容器未正常运行${NC}"
        exit 1
    fi
    
    # 执行其他检查
    check_ssh_service
    errors=$((errors + $?))
    
    test_ssh_connection
    errors=$((errors + $?))
    
    check_gpu_available
    warnings=$?
    
    check_cuda_compatibility
    local cuda_status=$?
    if [ $cuda_status -ne 0 ]; then
        errors=$((errors + $cuda_status))
    fi
    
    check_mpich
    errors=$((errors + $?))
    
    check_workspace_mount
    errors=$((errors + $?))
    
    # 显示总结报告
    echo ""
    if [ $errors -eq 0 ]; then
        # 获取容器IP地址
        container_ip=$(get_container_ip)
        if [ $? -ne 0 ]; then
            log_error "获取IP地址失败"
            exit 1
        fi
        
        # 获取宿主机IP地址
        host_ip=$(hostname -I | awk '{print $1}')
        
        log_info "══════════════════════════════════════════════════════════════════"
        log_info "✅ 环境检查完成：${GREEN}所有检查通过${NC}"
        log_info "  容器名称: ${BOLD}dsnode${NC}"
        log_info "  宿主机IP地址: ${BOLD}$host_ip${NC}"
        log_info "  SSH端口: ${BOLD}$SSH_PORT${NC}"
        log_info "══════════════════════════════════════════════════════════════════"
        
        if [ $warnings -ne 0 ]; then
            log_warn "有不影响使用的警告，请注意查看上面的日志"
        fi
    else
        log_error "环境检查完成：${RED}发现 $errors 个问题${NC}"
        log_error "请根据上面的错误信息排查问题"
    fi
}

# 执行主函数
main 