#!/bin/bash
killall server gdb 2>/dev/null
gdb -batch -ex "b handle_request" -ex "b append_todo" -ex "b load_todos" -ex "run" -ex "c" -ex "c" -ex "c" --args ./bin/server > gdb_null.log 2>&1 &
GDB_PID=$!
sleep 1
curl -s -X POST -d "title=Hello" http://localhost:8087/add
wait $GDB_PID
