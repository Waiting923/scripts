# TensorRT-LLM 集群配置脚本

此脚本用于自动化配置TensorRT-LLM的分布式训练和推理环境，包括Docker容器启动、SSH服务配置和主节点MPICH安装。

关于Tensorrt-LLM，请参看官网[Tensorrt-LLM](https://nvidia.github.io/TensorRT-LLM/overview.html)

## cuda要求
```
存储旧版本则需要卸载旧版cuda
sudo /usr/local/cuda-12.4/bin/cuda-uninstaller
sudo apt-get --purge remove "*nvidia*"
sudo apt-get autoremove
reboot 系统

安装新版cuda
wget https://developer.download.nvidia.com/compute/cuda/12.8.1/local_installers/cuda_12.8.1_570.124.06_linux.run
sudo sh cuda_12.8.1_570.124.06_linux.run

apt install nvidia-cuda-toolkit

# nvidia-fabricmanager
sudo systemctl stop nvidia-fabricmanager
sudo systemctl disable nvidia-fabricmanager
dpkg --list | grep nvidia-fabricmanager
sudo apt remove nvidia-fabricmanager-550 (如果存在旧的就卸载)

https://developer.download.nvidia.cn/compute/cuda/repos/ubuntu2004/x86_64/nvidia-fabricmanager-570_570.124.06-1_amd64.deb
apt-get install ./nvidia-fabricmanager-570_570.124.06-1_amd64.deb -y
systemctl enable nvidia-fabricmanager
systemctl restart nvidia-fabricmanager
systemctl status nvidia-fabricmanager


# 安装 NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker    
```

## 文件说明

- configuration 目录: 配置文件,所有节点均需要有。
  - hostfile: 集群内的节点ip列表，宿主机的ip即可，请确保各IP之间互通。
- sshkey 目录: 免密登录用途,所有节点均需要。
- `1-start-cluster-env.sh`: 用于配置集群节点
- `1-stop-cluster-env.sh`: 停止整个集群包括里面的推理服务
- `2-check-cluster-env.sh`: 用于检查容器环境状态，并获取节点IP
- `3-setup-node-config.sh`: 用于设置配置到node节点
- `4-start-trt-server.sh`: 启动推理服务-仅主节点执行。
- `env.example`: 环境变量示例文件

## 使用方法

### 1. 配置环境变量

复制环境变量示例文件，并根据需要修改：

```bash
cd llm-tensorrt
cp env.example .env
```

在`.env`文件中，你可以修改以下配置：
- `DOCKER_IMAGE`: Docker镜像名称
- `SSH_PORT`: SSH服务端口
- `SSHKEY_DIR`: SSH密钥目录（默认为脚本目录下的"sshkey"文件夹，将被挂载到容器内的/root/.ssh）
- `MODEL_REPO_DIR`: 模型仓库目录（默认为"/mnt/share/deepseek-ai"）
- `IS_MASTER`: 是否为主节点（主节点会安装MPICH）

### 2. 准备Docker镜像

在运行脚本前，确保已经准备好所需的Docker镜像。可通过以下方式获取镜像：

```bash
# 从Docker Hub拉取镜像
docker pull baseten/tensorrt_llm-release:0.19.0rc0

# 或者从本地文件导入镜像
docker load -i <镜像文件路径>
如：
docker load < /modelshare_readonly/software/docker-images/tensorrt_llm/tensorrt_llm-release-0.19.0rc0.tar 
```

### 3. 运行脚本

给脚本添加执行权限：

```bash
chmod +x 1-start-cluster-env.sh
```

以root用户运行脚本：

```bash
sudo ./1-start-cluster-env.sh
```

### 4. 主从节点配置
> 如果是多节点部署，则集群内所有节点均需要执行该步骤。

- 主节点: 将`.env`文件中的`IS_MASTER`设置为`true`
- 从节点: 将`.env`文件中的`IS_MASTER`设置为`false`（默认）

### 5. 验证配置

脚本执行完成后，可以通过以下命令检查容器是否正常运行：

```bash
sh 2-check-cluster-env.sh

-e 
-e ###############################################################################
-e #                                                                             #
-e #                                                                             #
-e #           TensorRT-LLM 集群部署工具                                           #
-e #                                                                             #
-e #                                                                             #
-e ###############################################################################

-e [INFO] 开始检查TensorRT-LLM集群环境...
-e [INFO] 当前环境变量配置如下：
-e   🛠️ DOCKER_IMAGE    = baseten/tensorrt_llm-release:0.19.0rc0
-e   🛠️ SSH_PORT        = 2233
-e   🛠️ IS_MASTER       = false
-e   🛠️ SSHKEY_DIR      = ./sshkey
-e   🛠️ MODEL_REPO_DIR  = /modelshare_readonly/deepseek-ai

-e [INFO] 检查dsnode容器是否存在并运行...
-e [PASS] dsnode容器正在运行
-e [INFO] 检查SSH服务是否正常...
-e [PASS] SSH服务正常，监听端口 2233
-e [INFO] 测试SSH免密连接...
-e [PASS] SSH连接测试成功
-e [INFO] 检查GPU是否可用...
Warning: Permanently added '[localhost]:2233' (ED25519) to the list of known hosts.
Warning: Permanently added '[localhost]:2233' (ED25519) to the list of known hosts.
-e [PASS] GPU可用，已验证nvidia-smi可以正常运行
-e [INFO] 检查CUDA版本和驱动兼容性...
SSH连接测试成功
SSH_TEST_OK
-e [PASS] CUDA版本: 12.8, 驱动版本: 570.124.06, 兼容性检查通过
-e [INFO] 非主节点，跳过MPICH检查
-e [INFO] 检查模型仓库目录挂载...
-e [PASS] 模型仓库目录已正确挂载: /workspace
-e [INFO] /workspace目录内容:
  - DeepSeek-R1
  - DeepSeek-R1-Block-INT8
  - DeepSeek-R1-Channel-INT8
  - DeepSeek-R1-Distill-Llama-70B
  - DeepSeek-R1-Distill-Llama-8B
  - DeepSeek-R1-Distill-Qwen-1.5B
  - DeepSeek-R1-Distill-Qwen-14B
  - DeepSeek-R1-Distill-Qwen-32B
  - DeepSeek-R1-Distill-Qwen-7B
  - DeepSeek-R1-GGUF
  - DeepSeek-R1-bf16
  - DeepSeek-V3
  - DeepSeek-V3-0324
  - DeepSeek-V3-0324-Channel-INT8
  - DeepSeek-V3-0324-bf16
  - DeepSeek-V3-Channel-INT8
  - DeepSeek-V3-bf16


-e [INFO] ══════════════════════════════════════════════════════════════════
-e [INFO] ✅ 环境检查完成：所有检查通过
-e [INFO]   容器名称: dsnode
-e [INFO]   容器IP地址: -e [INFO] 获取dsnode容器IP地址...
-e [WARNING] 无法获取dsnode容器的IP地址，尝试使用宿主机IP
-e [INFO] 容器IP地址: 10.83.0.103
-e [INFO] 宿主机IP地址: 10.83.0.103
10.83.0.103
-e [INFO]   宿主机IP地址: 10.83.0.103
-e [INFO]   SSH端口: 2233
-e [INFO] ══════════════════════════════════════════════════════════════════
```

### 5. 修改配置并上传 
> 如果是多节点部署，则集群内所有节点均需要执行该步骤。

```
根据实际情况修改configuration文件夹的配置,主要设置configuration中的hostfile。其他的如extra-llm-api-config.yml则根据实际需要修改。

然后执行 sh 3-setup-node-config.sh 保存。
```

### 6. 启动推理服务
> 该步骤在主节点上执行即可。
> 先确保集群内所有的节点都加入到了configuration中的hostfile中。


执行 sh 4-start-trt-server.sh -f 启动推理服务。

启动完成后，会有如下日志：
```
INFO:     Started server process [8924]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8888 (Press CTRL+C to quit)
```

#### 命令使用帮助
```
-e [INFO] 已从/root/llm-tensorrtllm/llm-tensorrt/.env加载环境变量
-e 用法: 4-start-trt-server.sh [选项]

-e 选项:
-e   -h, --help             显示此帮助信息
-e   -s, --stop             停止正在运行的TensorRT-LLM服务
-e   -r, --restart          重启TensorRT-LLM服务
-e   -b, --background       在后台运行服务 (等同于设置 RUN_IN_BACKGROUND=true)
-e   -f, --follow-logs      在后台运行服务并自动显示日志
-e   --logs                 显示当前运行服务的日志
-e   --clean-zombies        清理僵尸进程
-e   --status               显示当前服务状态及进程信息

-e 示例:
-e   4-start-trt-server.sh                     在前台启动服务 (按Ctrl+C停止)
-e   4-start-trt-server.sh -b                  在后台启动服务
-e   4-start-trt-server.sh -f                  在后台启动服务并自动显示日志
-e   4-start-trt-server.sh --logs              显示当前运行服务的日志
-e   4-start-trt-server.sh --status            检查服务状态
```


## 注意事项

1. 脚本需要以root用户权限运行
2. 确保已安装Docker
3. 确保Docker可以访问GPU（需要安装nvidia-docker）
4. 如果容器已存在，脚本会询问是否删除现有容器
5. 如果是在远程服务器上，请确保SSH到服务器后再执行这些命令
6. 脚本会检查所需的Docker镜像是否存在，如果不存在将退出并提示导入镜像

## 常见问题

### 容器间SSH能通,但是MIPRUN不通
```
 sudo iptables -L -v -n  查看防火墙策略

 Chain DOCKER (1 references)
 pkts bytes target     prot opt in     out     source               destination         
   54  3240 ACCEPT     tcp  --  !docker0 docker0  0.0.0.0/0            172.17.0.2           tcp dpt:40000
    0     0 ACCEPT     tcp  --  !docker0 docker0  0.0.0.0/0            172.17.0.2           tcp dpt:2233
    🈲0     0 DROP       all  --  !docker0 docker0  0.0.0.0/0            0.0.0.0/0   

这个drop策略导致容器间的通讯问题，把这个规则drop掉
    

 测试
mpirun -np 3 --hostfile /hostfile \
  -mca oob_tcp_if_include bond0 \
  -mca btl_tcp_if_include bond0 \
  --mca btl_base_verbose 10 \
  --allow-run-as-root \
  hostname
```