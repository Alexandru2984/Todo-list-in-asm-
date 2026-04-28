#!/bin/bash
killall server gdb 2>/dev/null
gdb -batch -ex "run" -ex "bt" --args ./bin/server > gdb.log 2>&1 &
GDB_PID=$!
sleep 1
curl -s -X POST -d "title=Hello" http://localhost:8087/add
wait $GDB_PID
