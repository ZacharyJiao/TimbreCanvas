import json
import os
import subprocess
import sys


def _send(process, command, request_id):
    process.stdin.write(
        json.dumps({"command": command, "requestID": request_id, "payload": {}}) + "\n"
    )
    process.stdin.flush()
    return json.loads(process.stdout.readline())


def test_worker_handles_multiple_requests_in_one_resident_process():
    process = subprocess.Popen(
        [sys.executable, "-m", "timbrecanvas_runtime.main"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    try:
        first = _send(process, "ping", "r1")
        second = _send(process, "ping", "r2")
        engines = _send(process, "list_engines", "r3")
        stopped = _send(process, "shutdown", "r4")

        assert first["processID"] == second["processID"] == process.pid
        assert first["processID"] != os.getpid()
        assert engines["engines"][0]["engineID"] == "indextts2"
        assert stopped["shutdown"] is True
        assert process.wait(timeout=5) == 0
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
