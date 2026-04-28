#!/bin/bash
killall server gdb 2>/dev/null
gdb -batch -ex "b append_todo" -ex "run" -ex "display /i \$pc" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" -ex "stepi" --args ./bin/server > gdb_step.log 2>&1 &
GDB_PID=$!
sleep 1
curl -s -X POST -d "title=Hello" http://localhost:8087/add
wait $GDB_PID
