说明：
本方案用于vllm 三台部署Deepseek bf16 版本
*需要3台节点,node1,node2,node3
*依赖ray环境

脚本说明:
#####################################################
1）0-start-ray.sh  启动ray (3个节点都需要执行)
2）0-stop-ray.sh  停止ray
3）1-start-vllm-server.sh  启动vllm推理服务(只需要node1执行)

4) rcheck-ray-status.sh  用于检查ray集群状态
5) rcheck-vllm-log.sh   用于查看vllm推理服务的日志

6) run_cluster.sh  辅助脚本,无需关心无需修改。
7) run-node.sh  启动ray的辅助脚本，需要根据实际情况修改,(在每个node节点上均需要修改这个文件,修改内容如下)
 --->镜像版本:如vllm/vllm-openai:v0.7.3 ,根据实际情况修改。
 --->主head节点的IP ,如:10.83.0.2
 --->各VLLM_HOST_IP=10.83.0.21的ip,根据实际情况修改。

*** 测试脚本 **
8)test-check-server.sh  测试服务器状态
9)test-chat-stream.sh  聊天测试

实施步骤：
####################################################
1）把整个脚本包复制到各node节点下,并解压,假定我们放到/root/llm-vllm下。
2）根据实际情况修改run-node.sh 这个文件,主要修改主节点IP和work节点的HOST_IP, 如果要更新镜像版本也是在这个文件修改.
3）在主节点执行1-start-vllm-server.sh (可以根据实际情况调整vllm启动参数, 该脚本做了防止重复启动的判断)

等待启动完成,可能需要一定的时间... 可以用rcheck-vllm-log.sh 查看启动的日志。

4)启动完成后,可以用test-check-server.sh ,test-chat-stream.sh 进行测试。


如何关闭:
##################################################
1) 如果要关闭vllm推理服务,可以执行 停止现有进程：docker exec -it node pkill -f 'vllm serve'
2) 也可以每个节点执行  0-stop-ray.sh 来关闭ray集群。


节点端点：
##################################################
http://127.0.0.1:40000/v1/models   模型列表
http://127.0.0.1:40000/v1/chat/completions  聊天


