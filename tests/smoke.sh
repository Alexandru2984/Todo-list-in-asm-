#!/usr/bin/env bash
# End-to-end smoke test for the ASM TODO server.
# Builds nothing itself — run `make` first (CI does).
set -u

PORT=${SMOKE_PORT:-9473}
UID_T=00112233445566778899aabbccddeeff
BASE="http://localhost:$PORT"
DATA="data/todos-$UID_T.txt"
PASS=0
FAIL=0

check() { # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS+1)); echo "ok   - $1"
    else
        FAIL=$((FAIL+1)); echo "FAIL - $1 (expected '$2', got '$3')"
    fi
}

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
    rm -f "$DATA" "$DATA.tmp" "$DATA.lock"
}
trap cleanup EXIT

rm -f "$DATA" "$DATA.tmp" "$DATA.lock"
./bin/server "$PORT" > /dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 20); do
    curl -s -o /dev/null -m 1 "$BASE/" && break
    sleep 0.2
done

# --- basic routing ---
check "GET / is 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$BASE/")"
check "unknown path is 404" 404 "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$BASE/nope")"
check "GET /add is 405" 405 "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$BASE/add")"

# --- headers ---
HDRS=$(curl -s -D - -o /dev/null -m 5 "$BASE/?uid=$UID_T")
echo "$HDRS" | grep -qi '^Content-Length:';       check "200 has Content-Length" 0 $?
echo "$HDRS" | grep -qi 'X-Content-Type-Options'; check "200 has nosniff" 0 $?
echo "$HDRS" | grep -qi 'Referrer-Policy';        check "200 has Referrer-Policy" 0 $?
CL=$(echo "$HDRS" | grep -i '^Content-Length:' | tr -dc 0-9)
BL=$(curl -s -m 5 "$BASE/?uid=$UID_T" | wc -c)
check "Content-Length matches body" "$CL" "$BL"

# --- CRUD ---
curl -s -o /dev/null -m 5 -X POST "$BASE/add" --data "uid=$UID_T&title=first+task"
check "add persists" 1 "$(grep -c 'first task' "$DATA")"

curl -s -o /dev/null -m 5 -X POST "$BASE/add" --data "uid=$UID_T&title=second"
curl -s -o /dev/null -m 5 -X POST "$BASE/complete" --data "uid=$UID_T&id=1"
check "complete sets status" 1 "$(grep -c '^1|1|' "$DATA")"
check "complete keeps one line per id" 1 "$(grep -c '^1|' "$DATA")"

curl -s -o /dev/null -m 5 -X POST "$BASE/edit" --data "uid=$UID_T&id=2&title=renamed"
check "edit replaces title" 1 "$(grep -c '^2|0|.*|renamed$' "$DATA")"

curl -s -o /dev/null -m 5 -X POST "$BASE/clear-done" --data "uid=$UID_T"
check "clear-done removes completed" 0 "$(grep -c '^1|' "$DATA")"

curl -s -o /dev/null -m 5 -X POST "$BASE/delete" --data "uid=$UID_T&id=2"
check "delete removes record" 0 "$(grep -c '^2|' "$DATA")"

# --- security ---
curl -s -o /dev/null -m 5 -X POST "$BASE/add" --data "uid=$UID_T&title=%3Cscript%3Ealert(1)%3C%2Fscript%3E"
PAGE=$(curl -s -m 5 "$BASE/?uid=$UID_T")
echo "$PAGE" | grep -q '<script>alert(1)</script>';        check "XSS is escaped" 1 $?
echo "$PAGE" | grep -q '&lt;script&gt;alert(1)&lt;/script&gt;'; check "escaped title rendered" 0 $?

curl -s -o /dev/null -m 5 -X POST "$BASE/add" --data "uid=$UID_T&title=inj%7C9%7C1%0A99%7C0%7C1%7Cfake"
check "format injection stripped" 0 "$(grep -c '^99|' "$DATA")"

curl -s -o /dev/null -m 5 -X POST "$BASE/add" --data "uid=../../../tmp/evil&title=pwn"
check "path traversal rejected" 0 "$(ls data/ | grep -c evil)"

# --- protocol robustness ---
( printf 'POST /add HTTP/1.1\r\nHost: x\r\nContent-Length: 49\r\n\r\n'
  sleep 0.7
  printf 'uid=%s&title=split' "$UID_T" ) | nc -q2 localhost "$PORT" > /dev/null
check "split-packet POST body received" 1 "$(grep -c 'split$' "$DATA")"

# --- concurrency ---
# wait only for the curls; a bare `wait` would also wait for the server
CURL_PIDS=""
for i in $(seq 1 10); do
    curl -s -o /dev/null -m 8 -X POST "$BASE/add" --data "uid=$UID_T&title=par$i" &
    CURL_PIDS="$CURL_PIDS $!"
done
wait $CURL_PIDS
check "10 parallel adds all stored" 10 "$(grep -c 'par' "$DATA")"
check "parallel adds produce unique ids" 0 "$(awk -F'|' '{print $1}' "$DATA" | sort -n | uniq -d | wc -l)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
