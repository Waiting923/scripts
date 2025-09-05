curl -X POST http://146.56.220.105:28443/v1/chat/completions -d '{
"model": "deepseek-r1",
"messages": [
	{"role": "system",
	"content": "三国演义剧情总结"}],
"max_tokens": 200,
"stream": false}' 