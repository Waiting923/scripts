echo "清理旧的资源..."
docker stop dsnode
docker rm dsnode

echo "加载ib设备.."
sudo modprobe nvidia-peermem

echo "启动 node镜像..."
docker run -d --gpus all \
    --name dsnode \
    --shm-size 512g \
    --network=host \
    -v /mnt/share/deepseek-ai:/deepseek \
    --restart always \
    -p 40000:40000 \
    --privileged --device=/dev/infiniband:/dev/infiniband \
    -e NCCL_IB_HCA=mlx5_0,mlx5_1,mlx5_4,mlx5_5 \
    -e GLOO_SOCKET_IFNAME=bond0 \
    -e NCCL_SOCKET_IFNAME=bond0 \
    -e NCCL_DEBUG=INFO \
    --ipc=host \
    lmsysorg/sglang:v0.4.4-cu125 \
    python3 -m sglang.launch_server \
      --model-path /deepseek/DeepSeek-R1 \
      --served-model-name DeepSeek-R1 \
      --trust-remote-code \
      --tp 16 \
      --enable-metrics \
      --enable-cache-report \
      --show-time-cost \
      --mem-fraction-static 0.9 \
      --max-prefill-tokens 2000 \
      --max-total-tokens 65536 \
      --dist-init-addr 10.82.1.11:20001 \
      --nnodes 2 \
      --node-rank 0 \
      --host 0.0.0.0 \
      --port 40000 \
      --enable-torch-compile --torch-compile-max-bs 8 \
      --stream-output \
      --allow-auto-truncate

echo "查看日志 ..."
docker logs -f dsnode
