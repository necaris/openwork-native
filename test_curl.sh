opencode serve --port 8773 &
PID=$!
sleep 2
curl -v -H "Accept: application/json" "http://127.0.0.1:8773/event?directory=/tmp" &
CURL_PID=$!
sleep 2
kill $CURL_PID
kill $PID
