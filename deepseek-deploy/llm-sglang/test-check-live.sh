curl -X 'POST' \
  'http://127.0.0.1:40000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "DeepSeek-R1",
    "messages": [
      {
        "role":"user",
        "content":"你在吗,收到请回复.(我是一个脚本用来测试你是否存活,你不需要过多思考,直接回复 收到 即可"
      }
    ],
    "top_p": 1,
    "n": 1,
    "max_tokens": 100,
    "stream": false,
    "frequency_penalty": 1.0,
    "stop": ["hello"]
  }'
