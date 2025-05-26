#!/bin/bash

# 测试SSH连接脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 默认值
REMOTE_HOST=${1:-"localhost"}

echo -e "${GREEN}测试SSH免密登录到 ${REMOTE_HOST}...${NC}"
echo "使用的SSH密钥目录: ${SCRIPT_DIR}/sshkey"

# 执行SSH测试连接
ssh -i "${SCRIPT_DIR}/sshkey/id_rsa" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p 2233 \
    root@${REMOTE_HOST} "echo -e '${GREEN}成功连接到 \$(hostname)${NC}'; echo '当前工作目录: \$(pwd)'; echo '当前用户: \$(whoami)'"

# 检查连接结果
if [ $? -eq 0 ]; then
    echo -e "${GREEN}SSH连接测试成功!${NC}"
else
    echo -e "${RED}SSH连接测试失败!${NC}"
    echo "请确保:"
    echo "1. 目标主机 ${REMOTE_HOST} 已正常启动并运行"
    echo "2. 容器内SSH服务已正确配置并启动"
    echo "3. SSH端口(2233)已正确配置"
    echo "4. 公钥已添加到目标主机的authorized_keys中"
fi 