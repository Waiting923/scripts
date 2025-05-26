echo "##### check vllm logs #####"
docker exec -it node tail -f /var/log/vllm.log
