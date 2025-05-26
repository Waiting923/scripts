#!/bin/bash

PROCESS_NAME="run-node.sh"
LOG_FILE="logs/run.log"

# 查找所有相关进程
PIDS=$(pgrep -f "$PROCESS_NAME" || true)

if [ -z "$PIDS" ]; then
  echo "[INFO] 未找到运行中的 $PROCESS_NAME"
  exit 0
else
  echo "[DEBUG] 待终止进程列表: $PIDS"
  kill $PIDS 2>/dev/null && \
    echo "[SUCCESS] 已终止 $PROCESS_NAME (PIDs: $PIDS)" || \
    echo "[ERROR] 终止失败，可能需要 sudo 权限"
  
  # 可选：归档日志（保留历史）
  mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S).bak" 2>/dev/null
fi


docker stop node
docker rm node
