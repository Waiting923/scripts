#!/bin/bash
# Copyright (c) 2024, 作者
# All rights reserved.

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

# TensorRT-LLM 聊天测试脚本
# 该脚本用于测试TensorRT-LLM大语言模型推理服务的聊天功能

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
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
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
SERVER_HOST=${SERVER_HOST:-"localhost"}
SERVER_PORT=${SERVER_PORT:-8888}
TIMEOUT=${TIMEOUT:-5}
TEST_MESSAGE=${TEST_MESSAGE:-"你好，请介绍一下自己"}

# 函数：检查服务是否启动正常
check_service() {
    log_info "检查TensorRT-LLM服务是否运行在 $SERVER_HOST:$SERVER_PORT..."
    
    # 使用curl检查服务状态
    response=$(curl -s -o /dev/null -w "%{http_code}" http://${SERVER_HOST}:${SERVER_PORT}/v1/models -m $TIMEOUT)
    
    if [ "$response" = "200" ]; then
        log_info "服务运行正常，获取模型信息..."
        
        # 获取并格式化模型信息
        models_info=$(curl -s http://${SERVER_HOST}:${SERVER_PORT}/v1/models | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'data' in data:
        for model in data['data']:
            print(f\"模型名称: {model['id']}, 版本: {model.get('version', 'N/A')}，最大上下文: {model.get('context_window', 'N/A')}，最大生成长度: {model.get('max_tokens', 'N/A')}\")
    else:
        print('未找到模型数据')
except Exception as e:
    print(f'解析模型信息出错: {str(e)}')
")
        
        log_info "模型信息:\n$models_info"
        return 0
    else
        log_error "无法连接到TensorRT-LLM服务，响应码: $response (或超时)"
        return 1
    fi
}

# 函数：测试聊天功能
test_chat() {
    local message=${1:-$TEST_MESSAGE}
    log_info "测试聊天功能，发送消息: '$message'"
    
    # 创建聊天请求JSON
    local request_json='{
        "model": "llm",
        "messages": [
            {
                "role": "user",
                "content": "'"$message"'"
            }
        ],
        "temperature": 0.7,
        "max_tokens": 100
    }'

    # 发送请求并解析响应
    echo -e "${BLUE}请求中...${NC}"
    response=$(curl -s -X POST http://${SERVER_HOST}:${SERVER_PORT}/v1/chat/completions \
                   -H "Content-Type: application/json" \
                   -d "$request_json")
    
    # 保存原始响应到临时文件供后续分析
    local tmp_file=$(mktemp)
    echo "$response" > "$tmp_file"
    
    # 检查响应是否为空
    if [ -z "$response" ]; then
        log_error "接收到空响应，服务可能未返回任何数据"
        rm -f "$tmp_file"
        return 1
    fi
    
    # 使用Python解析并格式化输出
    local parse_result=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'choices' in data and len(data['choices']) > 0:
        message = data['choices'][0]['message']
        content = message['content']
        print(f\"\033[0;32m[模型响应]\033[0m {content}\")
        print(f\"\033[0;34m[详细信息]\033[0m 用时: {data.get('usage', {}).get('total_time', 'N/A')}毫秒, 生成Token: {data.get('usage', {}).get('completion_tokens', 'N/A')}, 输入Token: {data.get('usage', {}).get('prompt_tokens', 'N/A')}\")
        print('SUCCESS')  # 标记成功
    else:
        print(f\"\033[0;31m[错误]\033[0m 响应数据格式不正确: {data}\")
        print('FAIL')  # 标记失败
except json.JSONDecodeError:
    raw_data = sys.stdin.read()
    print(f\"\033[0;31m[错误]\033[0m 无法解析JSON响应\")
    print('FAIL')  # 标记失败
except Exception as e:
    print(f\"\033[0;31m[错误]\033[0m 处理响应时出错: {str(e)}\")
    print('FAIL')  # 标记失败
")

    # 检查解析结果
    if ! echo "$parse_result" | grep -q "SUCCESS"; then
        log_error "聊天测试失败"
        echo -e "${RED}[原始响应]${NC}"
        cat "$tmp_file"
        echo ""
        rm -f "$tmp_file"
        return 1
    fi
    
    rm -f "$tmp_file"
    return 0
}

# 函数：显示帮助信息
show_help() {
    echo -e "${BOLD}用法:${NC} $0 [选项]"
    echo ""
    echo -e "${BOLD}选项:${NC}"
    echo -e "  ${YELLOW}-h, --help${NC}             显示此帮助信息"
    echo -e "  ${YELLOW}-H, --host${NC} HOST        指定服务主机地址 (默认: ${SERVER_HOST})"
    echo -e "  ${YELLOW}-p, --port${NC} PORT        指定服务端口号 (默认: ${SERVER_PORT})"
    echo -e "  ${YELLOW}-m, --models-only${NC}      仅测试模型列表接口"
    echo -e "  ${YELLOW}-c, --chat-only${NC}        仅测试聊天接口"
    echo -e "  ${YELLOW}-t, --timeout${NC} SECONDS  设置请求超时时间 (默认: ${TIMEOUT}秒)"
    echo -e "  ${YELLOW}--message${NC} \"消息\"       指定要发送的测试消息 (默认: \"${TEST_MESSAGE}\")"
    echo ""
    echo -e "${BOLD}示例:${NC}"
    echo -e "  ${YELLOW}$0${NC}                            使用默认参数测试"
    echo -e "  ${YELLOW}$0 -H 192.168.1.100${NC}           指定主机IP测试"
    echo -e "  ${YELLOW}$0 -H api.example.com -p 8000${NC} 指定主机名和端口测试"
    echo -e "  ${YELLOW}$0 -m${NC}                         仅测试模型列表接口"
    echo -e "  ${YELLOW}$0 -c${NC}                         仅测试聊天接口"
    echo -e "  ${YELLOW}$0 -t 10${NC}                      设置超时时间为10秒"
    echo -e "  ${YELLOW}$0 --message \"讲个笑话\"${NC}     发送自定义消息测试"
    echo ""
}

# 主函数
main() {
    local models_only=false
    local chat_only=false
    local status=0
    
    # 解析命令行参数
    while [ "$#" -gt 0 ]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -H|--host)
                SERVER_HOST="$2"
                shift 2
                ;;
            -p|--port)
                SERVER_PORT="$2"
                shift 2
                ;;
            -m|--models-only)
                models_only=true
                shift
                ;;
            -c|--chat-only)
                chat_only=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --message)
                TEST_MESSAGE="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "开始测试TensorRT-LLM聊天功能..."
    log_info "服务地址: http://${SERVER_HOST}:${SERVER_PORT}"
    
    # 根据参数决定测试流程
    if [ "$chat_only" = "true" ]; then
        log_info "仅测试聊天API..."
        test_chat "$TEST_MESSAGE"
        status=$?
    elif [ "$models_only" = "true" ]; then
        log_info "仅测试模型列表API..."
        check_service
        status=$?
    else
        # 默认测试流程：先检查服务，然后测试聊天
        check_service
        server_status=$?
        
        if [ $server_status -eq 0 ]; then
            echo ""
            test_chat "$TEST_MESSAGE"
            chat_status=$?
            
            # 如果任一测试失败，设置总状态为失败
            if [ $chat_status -ne 0 ]; then
                status=1
            fi
        else
            status=1
        fi
    fi
    
    # 测试结果总结
    echo ""
    if [ $status -eq 0 ]; then
        log_info "✅ 测试完成，一切正常"
    else
        log_error "❌ 测试失败，请检查服务状态和日志"
    fi
    
    exit $status
}

# 执行主函数
main "$@" 