curl -X 'POST' \
  'http://127.0.0.1:40000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "DeepSeek-R1",
    "messages": [
      {
        "role":"user",
        "content":"Hello! How are you?"
      },
      {
        "role":"assistant",
        "content":"Hi! I am quite well, how can I help you today?"
      },
      {
        "role":"user",
        "content":"思考一下长沙有什么好玩的?"
      }
    ],
    "top_p": 1,
    "n": 1,
    "max_tokens": 500,
    "stream": true,
    "frequency_penalty": 1.0,
    "stop": ["hello"]
  }'
