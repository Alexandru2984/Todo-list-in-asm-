#!/bin/bash
killall server gdb 2>/dev/null
gdb -batch -ex "b format_and_append" -ex "run" -ex "display /i \$pc" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" -ex "ni" --args ./bin/server > gdb_step2.log 2>&1 &
GDB_PID=$!
sleep 1
curl -s -X POST -d "title=Hello" http://localhost:8087/add
wait $GDB_PID
