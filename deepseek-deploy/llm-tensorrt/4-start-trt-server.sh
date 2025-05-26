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

# TensorRT-LLM 服务启动脚本
# 该脚本用于在TensorRT-LLM集群上启动大语言模型推理服务

# 颜色定义，用于输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "#                      版权所有 (C) 2024 有孚网络科技👍👏❗                     #"
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
MODEL_PATH=${MODEL_PATH:-"/workspace/DeepSeek-R1/"}
NUM_PROCESSES=${NUM_PROCESSES:-16}
TP_SIZE=${TP_SIZE:-16}
EP_SIZE=${EP_SIZE:-8}
PP_SIZE=${PP_SIZE:-1}
SSH_PORT=${SSH_PORT:-2233}
SERVER_PORT=${SERVER_PORT:-8000}
MASTER_ADDR=${MASTER_ADDR:-"10.83.0.101"}
MASTER_PORT=${MASTER_PORT:-29500}
TRT_BACKEND=${TRT_BACKEND:-"pytorch"}
MAX_BATCH_SIZE=${MAX_BATCH_SIZE:-128}
MAX_NUM_TOKENS=${MAX_NUM_TOKENS:-8192}
KV_CACHE_FRACTION=${KV_CACHE_FRACTION:-0.95}
EXTRA_CONFIG=${EXTRA_CONFIG:-"extra-llm-api-config.yml"}
IS_MASTER_NODE=${IS_MASTER:-false}
ENABLE_EXTRA_CONFIG=${ENABLE_EXTRA_CONFIG:-false}
RUN_IN_BACKGROUND=${RUN_IN_BACKGROUND:-false}
SHOW_LOGS=${SHOW_LOGS:-false}
LOG_FILE=${LOG_FILE:-"/var/log/trt-llm/server.log"}
HOST_TEST=${HOST_TEST:-false}  # 默认只测试容器内连接，不测试宿主机连接

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
    log_info "宿主机IP: $host_ip (运行集群时使用该IP填写hostfile)"
    
    echo "$container_ip"
    return 0
}

# 函数：检查hostfile是否存在
check_hostfile() {
    log_info "检查hostfile文件是否存在..."
    
    if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -f /hostfile; then
        log_error "容器内未找到hostfile文件，请先运行3-setup-node-config.sh上传配置文件"
        return 1
    fi
    
    log_info "hostfile文件存在"
    return 0
}

# 函数：检查SSH连通性
check_ssh_connectivity() {
    echo -e "${BLUE}[INFO]${NC} 检查SSH连通性..."
    local hostfile="/hostfile"

    # 确保hostfile存在于容器内
    if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -f "$hostfile"; then
        echo -e "${RED}[错误]${NC} 在容器 $CONTAINER_NAME 中未找到hostfile: $hostfile"
        return 1
    fi

    local temp_dir="$(mktemp -d /tmp/ssh-test.XXXXXX)"
    local container_pass_file="${temp_dir}/container_pass.txt"
    local container_fail_file="${temp_dir}/container_fail.txt"
    local host_pass_file="${temp_dir}/host_pass.txt"
    local host_fail_file="${temp_dir}/host_fail.txt"
    local has_failures=false
    local invalid_hostfile=false # 标记是否存在格式问题

    # 创建临时文件
    touch "${container_pass_file}" "${container_fail_file}"
    if [ "$HOST_TEST" = "true" ]; then
        touch "${host_pass_file}" "${host_fail_file}"
    fi

    # 读取hostfile内容到临时文件
    local valid_hostnames_file="${temp_dir}/valid_hostnames.txt"
    touch "$valid_hostnames_file"

    # 提取有效的主机名行
    $DOCKER_CMD exec "$CONTAINER_NAME" cat "$hostfile" | while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释行
        if [ -z "$line" ] || echo "$line" | grep -q "^[[:space:]]*#"; then
            continue
        fi

        # 提取主机名 (第一列)
        local hostname=$(echo "$line" | awk '{print $1}')
        if [ -z "$hostname" ]; then
            echo -e "${YELLOW}[警告]${NC} 无效的hostfile行 (缺少主机名): $line"
            invalid_hostfile=true
            continue
        fi

        # 可选：添加主机名格式验证 (例如，只允许字母、数字、连字符)
        # if ! echo "$hostname" | grep -q -E '^[a-zA-Z0-9-]+$'; then
        #     echo -e "${YELLOW}[警告]${NC} 无效的主机名格式: $hostname (来自行: $line)"
        #     invalid_hostfile=true
        #     continue
        # fi

        # 添加到有效主机名列表
        echo "$hostname" >> "$valid_hostnames_file"
    done

    # 检查是否有有效的主机名
    if [ ! -s "$valid_hostnames_file" ]; then
        echo -e "${RED}[错误]${NC} hostfile中没有找到有效的主机名"
        rm -rf "${temp_dir}"
        return 1
    fi

    # 打印将要测试的所有节点信息
    local total_nodes=$(wc -l < "$valid_hostnames_file" || echo 0)
    echo -e "\n${BLUE}[INFO]${NC} 将测试以下 ${YELLOW}${total_nodes}${NC} 个节点的SSH连通性:"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    local node_index=0
    while IFS= read -r hostname; do
        node_index=$((node_index + 1))
        # 获取节点在hostfile中的原始行，以显示额外信息（如slots）
        # 使用更健壮的 grep 模式，匹配以 hostname 开头并后跟空格或行尾
        local node_info=$($DOCKER_CMD exec "$CONTAINER_NAME" grep -E "^${hostname}[[:space:]]|^${hostname}$" "$hostfile" | head -n 1)
        if [ -z "$node_info" ]; then
            node_info="$hostname"
        fi
        echo -e "${BLUE}│${NC} ${YELLOW}节点 ${node_index}:${NC} ${node_info}"
    done < "$valid_hostnames_file"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # 测试节点间连通性
    while IFS= read -r hostname; do
        echo -e "${BLUE}[INFO]${NC} 测试到节点 ${YELLOW}${hostname}${NC} 的SSH连接..."

        # 容器内测试
        # 使用获取到的 hostname 进行 ssh 连接
        if $DOCKER_CMD exec "$CONTAINER_NAME" timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes "root@${hostname}" "echo 容器到 ${hostname} 的SSH连接成功" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} 容器到 ${hostname} 的SSH连接 ${GREEN}成功${NC}"
            echo "$hostname" >> "${container_pass_file}"
        else
            echo -e "  ${RED}✗${NC} 容器到 ${hostname} 的SSH连接 ${RED}失败${NC}"
            echo "$hostname" >> "${container_fail_file}"
            has_failures=true
        fi

        # 如果启用了主机测试，则从主机测试
        if [ "$HOST_TEST" = "true" ]; then
            if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes "root@${hostname}" "echo 主机到 ${hostname} 的SSH连接成功" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} 主机到 ${hostname} 的SSH连接 ${GREEN}成功${NC}"
                echo "$hostname" >> "${host_pass_file}"
            else
                echo -e "  ${RED}✗${NC} 主机到 ${hostname} 的SSH连接 ${RED}失败${NC}"
                echo "$hostname" >> "${host_fail_file}"
                has_failures=true
            fi
        fi
    done < "$valid_hostnames_file"

    # 总结测试结果
    echo -e "\n${BLUE}[INFO]${NC} SSH连接测试结果摘要:"
    local container_pass_count=$(wc -l < "${container_pass_file}" || echo 0)
    local container_fail_count=$(wc -l < "${container_fail_file}" || echo 0)
    local total_count=$(wc -l < "${valid_hostnames_file}" || echo 0)

    echo -e "  容器内测试: ${GREEN}${container_pass_count} 成功${NC}, ${RED}${container_fail_count} 失败${NC}, 共 ${total_count} 个节点"

    if [ "$HOST_TEST" = "true" ]; then
        local host_pass_count=$(wc -l < "${host_pass_file}" || echo 0)
        local host_fail_count=$(wc -l < "${host_fail_file}" || echo 0)
        echo -e "  主机测试: ${GREEN}${host_pass_count} 成功${NC}, ${RED}${host_fail_count} 失败${NC}, 共 ${total_count} 个节点"
    fi

    # 如果有失败的连接，显示提示信息
    if [ "$has_failures" = "true" ]; then
        echo -e "\n${RED}[错误]${NC} 检测到SSH连接问题，必须先解决连接问题才能继续:"
        echo -e "  1. 确保SSH密钥已正确设置 (SSH密钥对无密码登录)"
        echo -e "  2. 检查所有节点的防火墙是否允许SSH连接 (端口22)"
        echo -e "  3. 确保hostfile中的主机名正确且可以在网络中解析" # 修改提示
        echo -e "  4. 确保容器内的 /etc/hosts 文件或DNS配置允许解析这些主机名" # 新增提示
        echo -e "  5. 如果修改了SSH配置，请运行'ssh-keygen -R <hostname>'清除已知主机缓存" # 修改提示

        # 如果从容器测试成功但从主机测试失败，可能是SSH配置问题
        if [ "$HOST_TEST" = "true" ] && [ "$container_fail_count" = "0" ] && [ "$host_fail_count" -gt 0 ]; then
            echo -e "\n${YELLOW}[提示]${NC} 容器内测试成功但主机测试失败，可能原因:"
            echo -e "  - 主机SSH配置与容器不同"
            echo -e "  - 容器使用的SSH密钥未添加到主机"
            echo -e "  - 主机无法解析hostfile中的主机名" # 修改提示
            echo -e "  - 请确保主机已设置正确的SSH密钥和网络配置" # 修改提示
        fi

        echo -e "\n${RED}[停止]${NC} 请修复SSH连接问题后再运行此脚本"
        rm -rf "${temp_dir}"
        return 1
    fi

    # 清理临时文件
    rm -rf "${temp_dir}"

    if [ "$invalid_hostfile" = "true" ]; then
        echo -e "\n${YELLOW}[警告]${NC} hostfile中可能存在格式问题或无效行，建议检查修复" # 修改提示
        log_warn "检测到hostfile格式问题，但继续执行"
    fi

    echo -e "\n${GREEN}[成功]${NC} 所有SSH连接测试通过!"
    return 0
}

# 函数：检查模型目录是否存在
check_model_dir() {
    log_info "检查模型目录是否存在: $MODEL_PATH"
    
    if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -d "$MODEL_PATH"; then
        log_error "模型目录不存在: $MODEL_PATH"
        return 1
    fi
    
    log_info "模型目录存在: $MODEL_PATH"
    return 0
}

# 函数：检查配置文件是否存在
check_config_file() {
    log_info "检查配置文件是否存在: $EXTRA_CONFIG"
    
    if [ "$ENABLE_EXTRA_CONFIG" != "true" ]; then
        log_info "额外配置选项未启用 (ENABLE_EXTRA_CONFIG=$ENABLE_EXTRA_CONFIG)"
        config_exists=1  # 设置为1表示未启用配置文件
    elif ! $DOCKER_CMD exec "$CONTAINER_NAME" test -f "/$EXTRA_CONFIG"; then
        log_warn "容器内未找到配置文件: /$EXTRA_CONFIG"
        log_warn "将使用默认配置启动服务"
        config_exists=1  # 设置为1表示配置文件不存在
    else
        # 检查文件权限
        $DOCKER_CMD exec "$CONTAINER_NAME" chmod 644 "/$EXTRA_CONFIG"
        
        # 验证配置文件格式
        if $DOCKER_CMD exec "$CONTAINER_NAME" command -v python3 >/dev/null 2>&1; then
            log_info "验证配置文件格式..."
            local yaml_check=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "python3 -c 'import yaml; yaml.safe_load(open(\"/$EXTRA_CONFIG\"))' 2>&1")
            yaml_check_status=$?
            
            if [ $yaml_check_status -ne 0 ]; then
                log_error "配置文件格式有误: $yaml_check"
                log_error "请检查配置文件格式是否符合YAML规范"
                log_error "配置文件格式验证失败，无法继续"
                exit 1  # 直接退出，不再继续
            fi
            
            # 打印配置文件内容
            log_info "配置文件内容:"
            $DOCKER_CMD exec "$CONTAINER_NAME" cat "/$EXTRA_CONFIG" | while read line; do
                echo -e "  ${BLUE}$line${NC}"
            done
        else
            log_warn "未找到Python，跳过配置文件格式验证"
        fi
        
        log_info "配置文件存在: /$EXTRA_CONFIG 且已启用"
        config_exists=0  # 设置为0表示配置文件存在且有效
    fi
    
    echo "==== [DEBUG] 配置文件检查完成，状态: $config_exists ===="
    
    return 0
}

# 函数：检查mpirun是否正在运行
check_mpirun_running() {
    log_info "检查mpirun进程是否已经在运行..."
    
    # 检查并存储容器内是否有mpirun进程（排除僵尸进程和grep本身）
    local mpirun_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,state,cmd | grep -v 'Z' | grep -w 'mpirun' | grep -v grep")
    if [ -n "$mpirun_processes" ]; then
        log_error "发现mpirun进程已经在运行！避免重复启动服务。"
        log_error "正在运行的mpirun进程:"
        echo "$mpirun_processes" | while read line; do
            echo -e "  ${RED}$line${NC}"
        done
        log_info "如需重启服务，请先停止现有服务: $0 --stop"
        return 1
    fi
    
    # 检查并存储容器内是否有trtllm-serve进程（排除僵尸进程和grep本身）
    local trtllm_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,state,cmd | grep -v 'Z' | grep -w 'trtllm' | grep -v grep")
    if [ -n "$trtllm_processes" ]; then
        log_error "发现trtllm相关进程已经在运行！避免重复启动服务。"
        log_error "正在运行的trtllm相关进程:"
        echo "$trtllm_processes" | while read line; do
            echo -e "  ${RED}$line${NC}"
        done
        log_info "如需重启服务，请先停止现有服务: $0 --stop"
        return 1
    fi
    
    # 检查是否有僵尸进程
    local zombie_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep -E 'Z.*(trtllm|mpi)' | grep -v grep")
    if [ -n "$zombie_processes" ]; then
        log_warn "发现相关的僵尸进程，但不影响服务启动:"
        echo "$zombie_processes" | while read line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
        log_info "可以使用'$0 --clean-zombies'清理僵尸进程"
    fi
    
    log_info "未发现运行中的服务进程"
    return 0
}

# 函数：创建日志目录
ensure_log_directory() {
    local log_dir=$(dirname "$LOG_FILE")
    
    log_info "确保日志目录存在: $log_dir"
    
    # 检查日志目录是否存在，如果不存在则创建
    if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -d "$log_dir"; then
        log_info "日志目录不存在，正在创建: $log_dir"
        $DOCKER_CMD exec "$CONTAINER_NAME" mkdir -p "$log_dir"
        
        # 检查目录创建是否成功
        if ! $DOCKER_CMD exec "$CONTAINER_NAME" test -d "$log_dir"; then
            log_error "无法创建日志目录: $log_dir"
            return 1
        fi
    fi
    
    # 检查目录权限
    $DOCKER_CMD exec "$CONTAINER_NAME" chmod 755 "$log_dir"
    
    log_info "日志目录准备就绪: $log_dir"
    return 0
}

# 函数：显示日志
show_logs() {
    log_info "显示服务日志 ($LOG_FILE)..."
    echo -e "${YELLOW}按Ctrl+C可停止查看日志（服务将继续在后台运行）${NC}"
    echo ""
    
    # 给用户一些时间阅读上面的信息
    sleep 1
    
    # 显示日志内容
    $DOCKER_CMD exec -it "$CONTAINER_NAME" tail -f "$LOG_FILE"
}

# 函数：启动TensorRT-LLM服务
start_trt_service() {
    log_info "正在启动TensorRT-LLM服务..."
    
    # 构建服务启动命令
    local config_option=""
    if [ $config_exists -eq 0 ]; then
        config_option="--extra_llm_api_options /$EXTRA_CONFIG"
        log_info "使用额外配置文件: /$EXTRA_CONFIG"
    elif [ $config_exists -eq 2 ]; then
        log_error "配置文件验证失败，无法启动服务"
        return 1
    fi
    
    # 服务启动命令
    local cmd="mpirun -np $NUM_PROCESSES --hostfile /hostfile \
           -x MASTER_ADDR \
           -x MASTER_PORT \
           -x NCCL_SOCKET_IFNAME \
               -mca btl_tcp_if_include bond0 \
               -mca oob_tcp_if_include bond0 \
               -mca plm_rsh_args \"-p $SSH_PORT\" --allow-run-as-root \
trtllm-llmapi-launch trtllm-serve serve \
--host 0.0.0.0 \
--port $SERVER_PORT \
--backend $TRT_BACKEND \
--tp_size $TP_SIZE \
--pp_size $PP_SIZE \
--ep_size $EP_SIZE \
--kv_cache_free_gpu_memory_fraction $KV_CACHE_FRACTION \
--trust_remote_code \
--max_batch_size $MAX_BATCH_SIZE \
--max_num_tokens $MAX_NUM_TOKENS \
$config_option \
$MODEL_PATH"
    
    log_info "执行命令: $cmd"
    echo ""
    echo -e "${BLUE}${BOLD}开始启动TensorRT-LLM服务...${NC}"
    
    # 检查是否在后台运行
    if [ "$RUN_IN_BACKGROUND" = "true" ] || [ "$RUN_IN_BACKGROUND" = "TRUE" ] || [ "$RUN_IN_BACKGROUND" = "1" ] || [ "$RUN_IN_BACKGROUND" = "yes" ] || [ "$RUN_IN_BACKGROUND" = "YES" ]; then
        # 确保日志目录存在
        ensure_log_directory
        if [ $? -ne 0 ]; then
            log_error "日志目录创建失败，无法继续"
            return 1
        fi
        
        echo -e "${YELLOW}服务将在后台运行，日志输出到: $LOG_FILE${NC}"
        echo -e "${YELLOW}可使用以下命令查看日志: docker exec $CONTAINER_NAME tail -f $LOG_FILE${NC}"
        echo -e "${YELLOW}使用命令停止服务: $0 --stop${NC}"
        echo ""
        
        # 在容器内执行命令（后台模式）
        $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "nohup $cmd > $LOG_FILE 2>&1 &"
        
        # 等待几秒，确保进程启动
        sleep 5
        
        # 检查进程是否成功启动
        if $DOCKER_CMD exec "$CONTAINER_NAME" pgrep -f "mpirun" > /dev/null; then
            log_info "TensorRT-LLM服务已在后台成功启动"
            log_info "服务状态: $0 --status"
            
            # 如果SHOW_LOGS为true，则自动显示日志
            if [ "$SHOW_LOGS" = "true" ] || [ "$SHOW_LOGS" = "TRUE" ] || [ "$SHOW_LOGS" = "1" ] || [ "$SHOW_LOGS" = "yes" ] || [ "$SHOW_LOGS" = "YES" ]; then
                show_logs
            fi
            
            return 0
        else
            log_error "启动TensorRT-LLM服务失败，请检查日志: docker exec $CONTAINER_NAME cat $LOG_FILE"
            # 显示错误日志的最后20行
            echo -e "${RED}错误日志 (最后20行):${NC}"
            $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "tail -n 20 $LOG_FILE"
            return 1
        fi
    else
        echo -e "${YELLOW}（服务启动可能需要几分钟时间，请耐心等待）${NC}"
        echo -e "${YELLOW}注意: 按下Ctrl+C将停止服务，若要在后台运行请使用: RUN_IN_BACKGROUND=true $0${NC}"
        echo ""
        
        # 在容器内执行命令（交互模式）
        $DOCKER_CMD exec -it "$CONTAINER_NAME" bash -c "$cmd"
        cmd_status=$?
        
        # 检查启动结果
        if [ $cmd_status -ne 0 ]; then
            log_error "启动TensorRT-LLM服务失败，请检查错误信息"
            return 1
        fi
        
        log_info "TensorRT-LLM服务已启动成功"
        return 0
    fi
}

# 函数：停止TensorRT-LLM服务
stop_trt_service() {
    log_info "正在尝试停止TensorRT-LLM服务..."
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法停止服务"
        return 1
    fi
    
    # 显示当前运行的相关进程
    local current_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep -E 'mpirun|trtllm|llmapi' | grep -v grep")
    if [ -n "$current_processes" ]; then
        log_info "发现以下相关进程:"
        echo "$current_processes" | while read line; do
            echo -e "  ${BLUE}$line${NC}"
        done
    else
        log_info "未发现任何相关进程"
        return 0
    fi
    
    # 先尝试优雅地结束父进程
    if $DOCKER_CMD exec "$CONTAINER_NAME" pgrep -f "mpirun" > /dev/null; then
        log_info "发现mpirun进程，正在尝试优雅停止..."
        $DOCKER_CMD exec "$CONTAINER_NAME" pkill -TERM -f "mpirun"
        sleep 3
    fi
    
    # 强制杀死所有相关进程
    log_info "正在清理所有相关进程..."
    $DOCKER_CMD exec "$CONTAINER_NAME" pkill -9 -f "mpirun" 2>/dev/null || true
    $DOCKER_CMD exec "$CONTAINER_NAME" pkill -9 -f "trtllm-serve" 2>/dev/null || true
    $DOCKER_CMD exec "$CONTAINER_NAME" pkill -9 -f "trtllm-llmapi-launch" 2>/dev/null || true
    sleep 2
    
    # 清理僵尸进程
    log_info "正在清理可能的僵尸进程..."
    $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,state,cmd | grep -E 'Z.*trtllm|Z.*mpi' | awk '{print \$1}' | xargs -r kill -9" 2>/dev/null || true
    
    # 再次检查并显示可能仍在运行的进程
    local remaining_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep -v 'Z' | grep -E 'mpirun|trtllm'")
    if [ -n "$remaining_processes" ]; then
        log_error "以下进程无法停止，请手动终止:"
        echo "$remaining_processes" | while read line; do
            echo -e "  ${RED}$line${NC}"
        done
        echo ""
        log_error "可以尝试手动执行: docker exec $CONTAINER_NAME kill -9 <PID>"
        return 1
    fi
    
    log_info "TensorRT-LLM服务已成功停止"
    return 0
}

# 函数：清理僵尸进程
clean_zombie_processes() {
    log_info "正在尝试清理僵尸进程..."
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法清理僵尸进程"
        return 1
    fi
    
    # 显示当前僵尸进程
    local zombie_processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep 'Z'")
    if [ -n "$zombie_processes" ]; then
        log_info "发现以下僵尸进程:"
        echo "$zombie_processes" | while read line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
        
        # 尝试找出僵尸进程的父进程并终止
        log_info "正在尝试终止僵尸进程的父进程..."
        $DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep 'Z' | awk '{print \$2}' | sort -u | xargs -r kill -9" 2>/dev/null || true
        sleep 1
        
        # 检查是否还有僵尸进程
        local remaining_zombies=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep 'Z'")
        if [ -n "$remaining_zombies" ]; then
            log_warn "仍有僵尸进程存在，可能需要重启容器:"
            echo "$remaining_zombies" | while read line; do
                echo -e "  ${YELLOW}$line${NC}"
            done
            log_info "可以尝试重启容器: docker restart $CONTAINER_NAME"
            return 1
        fi
        
        log_info "僵尸进程已清理完成"
    else
        log_info "未发现任何僵尸进程"
    fi
    
    return 0
}

# 函数：显示帮助信息
show_help() {
    echo -e "${BOLD}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${BOLD}选项:${NC}"
    echo -e "  ${YELLOW}-h, --help${NC}             显示此帮助信息"
    echo -e "  ${YELLOW}-s, --stop${NC}             停止正在运行的TensorRT-LLM服务"
    echo -e "  ${YELLOW}-r, --restart${NC}          重启TensorRT-LLM服务"
    echo -e "  ${YELLOW}-b, --background${NC}       在后台运行服务 (等同于设置 RUN_IN_BACKGROUND=true)"
    echo -e "  ${YELLOW}-f, --follow-logs${NC}      在后台运行服务并自动显示日志"
    echo -e "  ${YELLOW}--logs${NC}                 显示当前运行服务的日志"
    echo -e "  ${YELLOW}--clean-zombies${NC}        清理僵尸进程"
    echo -e "  ${YELLOW}--status${NC}               显示当前服务状态及进程信息"
    echo -e "  ${YELLOW}--host-test${NC}            同时从宿主机测试节点SSH连接"
    echo ""
    echo -e "${BOLD}示例:${NC}"
    echo -e "  ${YELLOW}$0${NC}                     在前台启动服务 (按Ctrl+C停止)"
    echo -e "  ${YELLOW}$0 -b${NC}                  在后台启动服务"
    echo -e "  ${YELLOW}$0 -f${NC}                  在后台启动服务并自动显示日志"
    echo -e "  ${YELLOW}$0 --logs${NC}              显示当前运行服务的日志"
    echo -e "  ${YELLOW}$0 --status${NC}            检查服务状态"
    echo -e "  ${YELLOW}HOST_TEST=true $0${NC}      同时测试宿主机到各节点的SSH连接"
    echo ""
}

# 函数：显示当前服务状态
show_status() {
    log_info "正在检查TensorRT-LLM服务状态..."
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法获取服务状态"
        return 1
    fi
    
    # 显示所有相关进程
    echo -e "${BOLD}相关进程:${NC}"
    local processes=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "ps -eo pid,ppid,state,cmd | grep -E 'mpirun|trtllm|llmapi' | grep -v grep")
    if [ -n "$processes" ]; then
        echo "$processes" | while read line; do
            if echo "$line" | grep -q "Z"; then
                echo -e "  ${YELLOW}$line${NC} (僵尸进程)"
            else
                echo -e "  ${GREEN}$line${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}未发现任何相关进程${NC}"
    fi
    
    # 显示GPU使用情况
    echo ""
    echo -e "${BOLD}GPU使用情况:${NC}"
    $DOCKER_CMD exec "$CONTAINER_NAME" nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader
    
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

# 主函数
main() {
    log_info "👀开始启动TensorRT-LLM推理服务...🙏🙏🙏"
    
    # 打印所有环境变量参数
    log_info "环境变量参数信息:"
    echo -e "  🛠️ ${YELLOW}CONTAINER_NAME:${NC} $CONTAINER_NAME"
    echo -e "  🛠️ ${YELLOW}MODEL_PATH:${NC} $MODEL_PATH"
    echo -e "  🛠️ ${YELLOW}NUM_PROCESSES:${NC} $NUM_PROCESSES"
    echo -e "  🛠️ ${YELLOW}TP_SIZE:${NC} $TP_SIZE"
    echo -e "  🛠️ ${YELLOW}PP_SIZE:${NC} $PP_SIZE"
    echo -e "  🛠️ ${YELLOW}EP_SIZE:${NC} $EP_SIZE"
    echo -e "  🛠️ ${YELLOW}SSH_PORT:${NC} $SSH_PORT"
    echo -e "  🛠️ ${YELLOW}SERVER_PORT:${NC} $SERVER_PORT"
    echo -e "  🛠️ ${YELLOW}MAX_BATCH_SIZE:${NC} $MAX_BATCH_SIZE"
    echo -e "  🛠️ ${YELLOW}MAX_NUM_TOKENS:${NC} $MAX_NUM_TOKENS" 
    echo -e "  🛠️ ${YELLOW}KV_CACHE_FRACTION:${NC} $KV_CACHE_FRACTION"
    echo -e "  🛠️ ${YELLOW}EXTRA_CONFIG:${NC} $EXTRA_CONFIG"
    echo -e "  🛠️ ${YELLOW}ENABLE_EXTRA_CONFIG:${NC} $ENABLE_EXTRA_CONFIG"
    echo -e "  🛠️ ${YELLOW}RUN_IN_BACKGROUND:${NC} $RUN_IN_BACKGROUND"
    echo -e "  🛠️ ${YELLOW}SHOW_LOGS:${NC} $SHOW_LOGS"
    echo -e "  🛠️ ${YELLOW}LOG_FILE:${NC} $LOG_FILE"
    echo -e "  🛠️ ${YELLOW}IS_MASTER_NODE:${NC} $IS_MASTER_NODE"
    echo -e "  🛠️ ${YELLOW}MASTER_ADDR:${NC} $MASTER_ADDR"
    echo -e "  🛠️ ${YELLOW}MASTER_PORT:${NC} $MASTER_PORT"
    echo -e "  🛠️ ${YELLOW}TRT_BACKEND:${NC} $TRT_BACKEND"
    echo -e "  🛠️ ${YELLOW}HOST_TEST:${NC} $HOST_TEST"
    echo ""
    
    # 检查是否为主节点
    log_info "当前IS_MASTER_NODE值: $IS_MASTER_NODE"
    
    # 使用POSIX兼容的语法判断是否为主节点
    if [ "$IS_MASTER_NODE" = "true" ] || [ "$IS_MASTER_NODE" = "TRUE" ] || [ "$IS_MASTER_NODE" = "1" ] || [ "$IS_MASTER_NODE" = "yes" ] || [ "$IS_MASTER_NODE" = "YES" ]; then
        log_info "当前节点是主节点，将执行完整的服务启动流程"
    else
        log_warn "当前节点不是主节点，退出执行"
        exit 0
    fi
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法继续"
        exit 1
    fi
    
    # 检查mpirun进程是否已经在运行
    check_mpirun_running
    if [ $? -ne 0 ]; then
        log_error "检测到服务已在运行，无法重复启动"
        exit 1
    fi
    
    # 获取容器IP地址
    container_ip=$(get_container_ip)
    if [ $? -ne 0 ]; then
        log_error "获取容器IP地址失败，无法继续"
        exit 1
    fi
    
    # 获取宿主机IP地址（作为参考）
    host_ip=$(hostname -I | awk '{print $1}')
    log_info "宿主机IP: $host_ip (运行集群时使用该IP填写hostfile)"
    
    # 检查hostfile文件
    check_hostfile
    if [ $? -ne 0 ]; then
        log_error "hostfile文件检查失败，无法继续"
        exit 1
    fi
    
    # 检查SSH连通性 - 不再传递参数，函数内部使用默认hostfile路径
    check_ssh_connectivity
    if [ $? -ne 0 ]; then
        log_error "SSH连通性检查失败，无法继续"
        exit 1
    fi
    
    log_info "SSH连通性检查通过，继续启动服务..."
    
    # 检查模型目录
    check_model_dir
    if [ $? -ne 0 ]; then
        log_error "模型目录检查失败，无法继续"
        exit 1
    fi
    
    # 检查配置文件 - 重新实现直接内联逻辑，避免返回值问题
    log_info "检查配置文件是否存在: $EXTRA_CONFIG"
    
    if [ "$ENABLE_EXTRA_CONFIG" != "true" ]; then
        log_info "额外配置选项未启用 (ENABLE_EXTRA_CONFIG=$ENABLE_EXTRA_CONFIG)"
        config_exists=1  # 设置为1表示未启用配置文件
    elif ! $DOCKER_CMD exec "$CONTAINER_NAME" test -f "/$EXTRA_CONFIG"; then
        log_warn "容器内未找到配置文件: /$EXTRA_CONFIG"
        log_warn "将使用默认配置启动服务"
        config_exists=1  # 设置为1表示配置文件不存在
    else
        # 检查文件权限
        $DOCKER_CMD exec "$CONTAINER_NAME" chmod 644 "/$EXTRA_CONFIG"
        
        # 验证配置文件格式
        if $DOCKER_CMD exec "$CONTAINER_NAME" command -v python3 >/dev/null 2>&1; then
            log_info "验证配置文件格式..."
            local yaml_check=$($DOCKER_CMD exec "$CONTAINER_NAME" bash -c "python3 -c 'import yaml; yaml.safe_load(open(\"/$EXTRA_CONFIG\"))' 2>&1")
            yaml_check_status=$?
            
            if [ $yaml_check_status -ne 0 ]; then
                log_error "配置文件格式有误: $yaml_check"
                log_error "请检查配置文件格式是否符合YAML规范"
                log_error "配置文件格式验证失败，无法继续"
                exit 1  # 直接退出，不再继续
            fi
            
            # 打印配置文件内容
            log_info "配置文件内容:"
            $DOCKER_CMD exec "$CONTAINER_NAME" cat "/$EXTRA_CONFIG" | while read line; do
                echo -e "  ${BLUE}$line${NC}"
            done
        else
            log_warn "未找到Python，跳过配置文件格式验证"
        fi
        
        log_info "配置文件存在: /$EXTRA_CONFIG 且已启用"
        config_exists=0  # 设置为0表示配置文件存在且有效
    fi
    
    # 显示服务配置信息
    echo ""
    log_info "TensorRT-LLM服务配置信息:"
    echo -e "  ${YELLOW}模型路径:${NC} $MODEL_PATH"
    echo -e "  ${YELLOW}进程数量:${NC} $NUM_PROCESSES"
    echo -e "  ${YELLOW}Tensor并行度:${NC} $TP_SIZE"
    echo -e "  ${YELLOW}Pipeline并行度:${NC} $PP_SIZE"
    echo -e "  ${YELLOW}Expert并行度:${NC} $EP_SIZE"
    echo -e "  ${YELLOW}SSH端口:${NC} $SSH_PORT"
    echo -e "  ${YELLOW}服务端口:${NC} $SERVER_PORT"
    echo -e "  ${YELLOW}最大批处理大小:${NC} $MAX_BATCH_SIZE"
    echo -e "  ${YELLOW}最大Token数:${NC} $MAX_NUM_TOKENS" 
    echo -e "  ${YELLOW}KV缓存占比:${NC} $KV_CACHE_FRACTION"
    if [ $config_exists -eq 0 ]; then
        echo -e "  ${YELLOW}配置文件:${NC} /$EXTRA_CONFIG"
    else
        echo -e "  ${YELLOW}配置文件:${NC} 未找到或未启用，使用默认配置"
    fi
    echo -e "  ${YELLOW}运行模式:${NC} $([ "$RUN_IN_BACKGROUND" = "true" ] && echo "后台运行" || echo "前台运行")"
    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
        echo -e "  ${YELLOW}日志文件:${NC} $LOG_FILE"
        if [ "$SHOW_LOGS" = "true" ]; then
            echo -e "  ${YELLOW}自动显示日志:${NC} 是"
        fi
    fi
    echo ""
    
    log_info "准备启动TensorRT-LLM服务..."
    
    # 启动服务
    start_trt_service
    result=$?
    
    if [ $result -eq 0 ]; then
        log_info "TensorRT-LLM服务启动流程完成"
    else
        log_error "TensorRT-LLM服务启动失败"
    fi
    
    return $result
}

# 执行主函数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
elif [ "$1" = "-s" ] || [ "$1" = "--stop" ]; then
    stop_trt_service
    exit $?
elif [ "$1" = "-r" ] || [ "$1" = "--restart" ]; then
    stop_trt_service
    if [ $? -eq 0 ]; then
        main
    else
        log_error "服务停止失败，无法重启"
        exit 1
    fi
elif [ "$1" = "-b" ] || [ "$1" = "--background" ]; then
    RUN_IN_BACKGROUND=true
    shift
    main
elif [ "$1" = "-f" ] || [ "$1" = "--follow-logs" ]; then
    RUN_IN_BACKGROUND=true
    SHOW_LOGS=true
    shift
    main
elif [ "$1" = "--logs" ]; then
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法显示日志"
        exit 1
    fi
    show_logs
    exit $?
elif [ "$1" = "--clean-zombies" ]; then
    clean_zombie_processes
    exit $?
elif [ "$1" = "--status" ]; then
    show_status
    exit $?
elif [ "$1" = "--host-test" ]; then
    HOST_TEST=true
    shift
    main
else
    main
fi 