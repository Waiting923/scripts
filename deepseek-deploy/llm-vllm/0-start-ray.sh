mkdir -p logs

# 检查是否已存在名为 "node" 的容器
if docker ps --format '{{.Names}}' | grep -qw "node"; then
    echo "错误：名为 node 的容器已存在！请先处理后再运行。"
    exit 1
fi

# 使用 setsid 完全脱离终端会话（比 nohup 更彻底）
setsid ./run-node.sh > logs/run.log 2>&1 &

echo "启动成功！等待日志生成..."
tail -f logs/run.log
