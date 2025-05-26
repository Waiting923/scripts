echo "stop vllm server ..."
docker exec -it node pkill -f 'vllm serve'
