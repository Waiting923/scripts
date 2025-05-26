#!/bin/bash

CONTAINER_NAME="node"
RAY_ACTIVE_NODES=3  # 明确指定整数类型
LOG_PATH="/var/log/vllm.log"

# 检查容器存在性（精确匹配）
if ! docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "错误：容器 ${CONTAINER_NAME} 不存在"
    exit 1
fi

# 检查容器运行状态
if ! docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} | grep -q "true"; then
    echo "错误：容器 ${CONTAINER_NAME} 未运行"
    exit 1
fi

# 获取 Ray 状态（添加超时机制）
RAY_STATUS=$(timeout 10s docker exec ${CONTAINER_NAME} ray status 2>&1)
if [ $? -ne 0 ]; then
    echo "Ray 状态检查失败：命令执行超时或出错"
    exit 2
fi

# 精确提取 Active 节点数
ACTIVE_COUNT=$(echo "${RAY_STATUS}" | awk '
/Active:/ { active=1; next }
/Pending:/ { active=0 }
active && /^ *[0-9]+ +node_/ { count++ }  # 匹配带前导空格和 node_ 的行
END { print count+0 }')

echo "调试信息：ACTIVE_COUNT=${ACTIVE_COUNT}"

# 数值验证
if ! [ "${ACTIVE_COUNT}" -eq "${ACTIVE_COUNT}" ] 2>/dev/null; then
    echo "错误：无法解析节点数，请检查 ray status 输出格式"
    exit 3
fi

if [ "${ACTIVE_COUNT}" -ne "${RAY_ACTIVE_NODES}" ]; then
    echo "Ray 节点异常：当前 Active 节点数=${ACTIVE_COUNT}，期望值=${RAY_ACTIVE_NODES}"
    exit 4
fi

echo ">>>RAY 服务检查正常..."
echo "########################### Ray 集群信息如下 #################################"
docker exec -it node bash -c "ray status;"
echo "##############################################################################"

# 检查服务是否存在,如果存在了，则不要重复启动了。
if docker exec -it ${CONTAINER_NAME} pgrep -f 'vllm serve' >/dev/null 2>&1; then
    echo "错误：vllm 服务已在运行" >&2
    echo "如需强制重启，请执行：" >&2
    echo "1. 停止现有进程：docker exec -it ${CONTAINER_NAME} pkill -f 'vllm serve'"
    echo "2. 如果需要查看日志,请执行 docker exec -it node tail -f /var/log/vllm.log "
    exit 5
fi

# 新增GPU资源检查,避免在其他node节点执行这个启动脚本
GPU_USAGE=$(echo "${RAY_STATUS}" | grep -E '[0-9.]+/[0-9.]+ GPU')
if [ -z "${GPU_USAGE}" ]; then
    echo "错误：未找到GPU使用数据"
    exit 5
fi

# 使用参数扩展替代here-string
gpu_usage_value=$(echo "${GPU_USAGE}" | awk '{print $1}')
USED_GPU="${gpu_usage_value%/*}"
TOTAL_GPU="${gpu_usage_value#*/}"

# 精度比较（支持小数）
if [ $(echo "${USED_GPU} == ${TOTAL_GPU}" | bc) -eq 1 ]; then
    echo "错误：RAY集群GPU资源已耗尽（${USED_GPU}/${TOTAL_GPU}）,请确认是否在其他node节点已经启动vllm推理了。"
    exit 7
fi

###################### 所有检查都通过了,启动VLLM 服务 ##########################
echo "所有检查都通过了,启动VLLM 服务 ..."

# 启动 vllm 服务
docker exec -d ${CONTAINER_NAME} bash -c "nohup vllm serve /mnt/share/deepseek-ai/DeepSeek-R1-bf16 \
--served-model-name DeepSeek-R1 --dtype bfloat16 --trust-remote-code --max-model-len 65536  --enable_chunked_prefill \
--quantization None --tensor-parallel-size 8 --pipeline-parallel-size 3 --port 40000 \
--disable-log-requests --max-num-batched-tokens 12800 --gpu-memory-utilization 0.9 > /var/log/vllm.log 2>&1 &"

echo "已成功在容器 ${CONTAINER_NAME} 中启动 vllm 服务,可能会需要一会时间,请耐心等待..."
echo "##### check vllm logs #####"
docker exec -it node tail -f /var/log/vllm.log
