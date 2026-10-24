import ctypes
import os
import subprocess
import sys
import threading
import time
import traceback
import urllib.request
import webbrowser
from pathlib import Path

DATA_DIR = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "CineBook"
DATA_DIR.mkdir(parents=True, exist_ok=True)

if sys.stdout is None or sys.stderr is None:
    log = open(DATA_DIR / "cinebook.log", "a", buffering=1, encoding="utf-8")
    sys.stdout = sys.stderr = log

import uvicorn

from main import HOST, PORT, app

URL = f"http://127.0.0.1:{PORT}"
EDGE_PATHS = [
    Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
    Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
]


def server_up():
    try:
        urllib.request.urlopen(URL + "/index.html", timeout=1)
        return True
    except Exception:
        return False


def start_server():
    if server_up():
        return
    server = uvicorn.Server(uvicorn.Config(app, host=HOST, port=PORT, log_config=None))
    threading.Thread(target=server.run, daemon=True).start()
    for _ in range(150):
        if server_up():
            return
        time.sleep(0.1)
    raise RuntimeError(f"The CineBook server did not start on port {PORT}. See {DATA_DIR / 'cinebook.log'}.")


def open_window():
    edge = next((p for p in EDGE_PATHS if p.exists()), None)
    if edge is None:
        webbrowser.open(URL)
        threading.Event().wait()
    subprocess.run([
        str(edge),
        f"--app={URL}",
        f"--user-data-dir={DATA_DIR / 'window'}",
        "--window-size=1366,860",
        "--no-first-run",
        "--no-default-browser-check",
    ])


def main():
    try:
        start_server()
        open_window()
    except Exception as e:
        traceback.print_exc()
        ctypes.windll.user32.MessageBoxW(0, str(e), "CineBook", 0x10)


if __name__ == "__main__":
    main()
