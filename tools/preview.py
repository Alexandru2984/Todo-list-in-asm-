#!/usr/bin/env python3
"""Start a disposable preview and print its URL. No production data is used."""
from pathlib import Path
import signal
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from server import Server
server = Server()
print(f'http://127.0.0.1:{server.port}', flush=True)
try:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.pause()
finally:
    server.close()
