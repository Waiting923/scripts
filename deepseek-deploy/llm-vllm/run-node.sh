echo " start node1 ..."
# node 1
bash run_cluster.sh \
                vllm/vllm-openai:v0.8.0 \
                10.83.0.21 \
                --head \
                /mnt \
		-e GLOO_SOCKET_IFNAME=bond0 \
                -e NCCL_SOCKET_IFNAME=bond0 \
                -e NCCL_IB_HCA=mlx5_0,mlx5_1,mlx5_4,mlx5_5 \
                -e VLLM_HOST_IP=10.198.0.201 --privileged

####说明 
#NCCL_IB_HCA=mlx5_0,mlx5_1,mlx5_4,mlx5_5 ,根据实际情况填写,排除存储ib网络接口
#主节点为--head ,其他节点为--worker
