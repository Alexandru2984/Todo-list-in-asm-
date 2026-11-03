#!/usr/bin/env python3
"""Start a disposable preview and print its URL. No production data is used."""
from pathlib import Path
import signal
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tests'))
from server import Server
server = Server()
if '--json' in sys.argv:
    import json
    print(json.dumps({'url': f'http://127.0.0.1:{server.port}', 'data': str(server.root / 'data')}), flush=True)
else:
    print(f'http://127.0.0.1:{server.port}', flush=True)
try:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.pause()
finally:
    server.close()
