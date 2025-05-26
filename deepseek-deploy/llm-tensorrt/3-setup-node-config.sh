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

# 集群节点配置文件上传脚本
# 该脚本用于将配置文件上传到TensorRT-LLM集群节点的容器中

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

# 设置配置文件目录
CONFIG_DIR="$(dirname "$0")/configuration"

# 加载环境变量（如果存在）
ENV_FILE="$(dirname "$0")/.env"

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

if [ -f "$ENV_FILE" ]; then
    # 使用点命令替代source命令，更兼容
    . "$ENV_FILE"
    log_info "已从$ENV_FILE加载环境变量"
else
    log_warn "未找到.env文件，将使用默认值"
fi

# 设置默认值（如果未在.env中定义）
MODEL_PATH=${MODEL_PATH:-"/workspace/"} # 添加 MODEL_PATH 加载

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
    log_info "宿主机IP地址: $host_ip"
    
    echo "$container_ip"
    return 0
}

# 函数：检查配置目录是否存在
check_config_dir() {
    log_info "检查配置文件目录是否存在..."
    
    if [ ! -d "$CONFIG_DIR" ]; then
        log_error "配置文件目录 $CONFIG_DIR 不存在"
        log_info "正在创建配置文件目录..."
        mkdir -p "$CONFIG_DIR"
        if [ $? -ne 0 ]; then
            log_error "创建配置文件目录失败"
            return 1
        fi
        log_warn "配置文件目录已创建，但目录为空，请先将配置文件放入该目录后再运行此脚本"
        return 1
    fi
    
    # 检查是否有文件
    if [ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ]; then
        log_warn "配置文件目录 $CONFIG_DIR 为空，请先将配置文件放入该目录后再运行此脚本"
        return 1
    fi
    
    log_info "配置文件目录 $CONFIG_DIR 存在并包含文件"
    return 0
}

# 函数：上传配置文件到容器
upload_config_files() {
    log_info "开始上传配置文件到容器..."
    
    local hf_quant_config_found=false
    
    # 遍历配置目录下的所有文件
    for file in "$CONFIG_DIR"/*; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            
            # --- 开始: hf_quant_config.json 特殊处理 ---
            #if [ "$filename" = "hf_quant_config.json" ]; then
                #log_info "检测到 hf_quant_config.json，将额外上传到模型目录: ${MODEL_PATH}"
                
                # 确保模型目录存在 (通常由 1-start-cluster-env.sh 挂载，但以防万一)
                # $DOCKER_CMD exec "$CONTAINER_NAME" mkdir -p "$MODEL_PATH"
                
                # 上传到模型目录
                # $DOCKER_CMD cp "$file" "$CONTAINER_NAME:$MODEL_PATH/$filename"
                
                # if [ $? -ne 0 ]; then
                #     log_error "上传 $filename 到 $MODEL_PATH 失败"
                #     # 根据需要决定是否要因为这个特定文件的失败而中止整个脚本
                #     # return 1 
                #else
                #    log_info "成功上传 $filename 到 $MODEL_PATH"
                #fi
                #hf_quant_config_found=true
            #fi
            # --- 结束: hf_quant_config.json 特殊处理 ---
            
            # --- 开始: 原有的上传到根目录逻辑 ---
            log_info "正在上传 $filename 到容器根目录 /"
            $DOCKER_CMD cp "$file" "$CONTAINER_NAME:/$filename"
            
            if [ $? -ne 0 ]; then
                log_error "上传文件 $filename 到根目录失败"
                return 1 # 如果上传到根目录失败，则中止脚本
            fi
            # --- 结束: 原有的上传到根目录逻辑 ---
        fi
    done

    log_info "配置文件上传完成"
    return 0
}

# 函数：显示容器根目录文件列表
show_container_files() {
    log_info "容器根目录文件列表:"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────┐${NC}"

    # 获取文件列表，过滤目录，并按名称排序
    local file_list=$($DOCKER_CMD exec "$CONTAINER_NAME" ls -lh --ignore='.*' / | grep -v "^d" | sort -k9)

    # 检查列表是否为空
    if [ -z "$file_list" ]; then
        printf "${BLUE}│${NC} %-66s ${BLUE}│${NC}\n" "(根目录中没有普通文件)"
    else
        # 使用 printf 格式化输出
        echo "$file_list" | while IFS= read -r line; do
            # 提取大小 (第5字段) 和 文件名 (第9字段开始)
            local size=$(echo "$line" | awk '{print $5}')
            local name=$(echo "$line" | awk '{ $1=$2=$3=$4=$5=$6=$7=$8=""; print substr($0,9) }')
            printf "${BLUE}│${NC} %-50s %15s ${BLUE}│${NC}\n" "$name" "($size)"
        done
    fi

    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# 主函数
main() {
    log_info "开始上传配置文件到TensorRT-LLM集群节点容器..."
    
    # 检查容器是否存在并运行
    check_container_running
    if [ $? -ne 0 ]; then
        log_error "容器检查失败，无法继续"
        exit 1
    fi
    
    # 获取容器IP地址
    container_ip=$(get_container_ip)
    if [ $? -ne 0 ]; then
        log_error "获取容器IP地址失败，无法继续"
        exit 1
    fi
    
    # 检查配置文件目录
    check_config_dir
    if [ $? -ne 0 ]; then
        log_error "配置文件目录检查失败，无法继续"
        exit 1
    fi
    
    # 上传配置文件
    upload_config_files
    if [ $? -ne 0 ]; then
        log_error "上传配置文件失败"
        exit 1
    fi
    
    # 显示容器根目录文件列表
    show_container_files
    
    # 显示成功信息
    echo ""
    log_info "══════════════════════════════════════════════════════════════════"
    log_info "✅ 配置文件上传成功 ✅"
    log_info "  容器名称: ${BOLD}$CONTAINER_NAME${NC}"
    log_info "  配置文件已上传到容器目录中"
    log_info "══════════════════════════════════════════════════════════════════"
    
    return 0
}

# 执行主函数
main 