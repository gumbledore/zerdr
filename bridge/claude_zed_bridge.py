#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["websockets>=14"]
# ///
"""Claude Code IDE bridge for Zed.

Speaks Claude Code's IDE protocol (MCP over WebSocket + ~/.claude/ide/<port>.lock)
and renders proposed edits as Zed diffs, routed to the window that owns the file's
project. Save the right-hand side in Zed to accept; close the tab to reject.
"""

import asyncio
import json
import logging
import os
import secrets
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

from websockets.asyncio.server import serve
from websockets.datastructures import Headers
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Response

LOCK_DIR = Path.home() / ".claude" / "ide"
ZED = os.environ.get("ZED_BIN", "zeditor")
FOLDERS = [
    f for f in os.environ.get("CLAUDE_ZED_FOLDERS", str(Path.home())).split(":") if f
]
# Port + token persist so live Claude sessions can reconnect after a bridge restart
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "zed-herdr/bridge.json"
try:
    _saved = json.loads(STATE.read_text())
except (OSError, ValueError):
    _saved = {}
TOKEN = _saved.get("token") or secrets.token_hex(16)
TMP = Path(tempfile.mkdtemp(prefix="claude-zed-"))

log = logging.getLogger("claude-zed")


def project_root(path: str) -> str:
    """Git toplevel (worktree-aware) of path, else its nearest existing dir."""
    d = Path(path).parent
    while not d.exists():
        d = d.parent
    r = subprocess.run(
        ["git", "-C", str(d), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    return r.stdout.strip() if r.returncode == 0 else str(d)


def text(s: str) -> dict:
    return {"type": "text", "text": s}


class Diff:
    def __init__(self, old: str, new: str, contents: str, tab: str):
        self.tab = tab
        self.dir = d = TMP / secrets.token_hex(4)
        d.mkdir()
        self.proposed = d / Path(new).name
        self.proposed.write_text(contents)
        self.old = old
        if not Path(old).exists():  # new file: diff against empty
            self.old = str(d / f"empty-{Path(old).name}")
            Path(self.old).write_text("")
        self.mtime = self.proposed.stat().st_mtime_ns
        self.root = project_root(new)
        self.proc: asyncio.subprocess.Process | None = None

    async def run(self) -> list[dict]:
        # cwd=root routes the diff to the Zed window that has this project open;
        # -w returns when the diff tab is closed.
        self.proc = await asyncio.create_subprocess_exec(
            ZED, "-w", "--diff", self.old, str(self.proposed), cwd=self.root,
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        while True:
            if self.proposed.stat().st_mtime_ns != self.mtime:
                return [text("FILE_SAVED"), text(self.proposed.read_text())]
            if self.proc.returncode is not None:
                return [text("DIFF_REJECTED"), text(self.tab)]
            try:
                await asyncio.wait_for(self.proc.wait(), 0.3)
            except TimeoutError:
                pass

    def close(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
        shutil.rmtree(self.dir, ignore_errors=True)


def open_file(args: dict) -> list[dict]:
    path = args["filePath"]
    target, line = path, None
    if needle := args.get("startText"):
        try:
            for i, l in enumerate(Path(path).read_text().splitlines(), 1):
                if needle in l:
                    line = i
                    break
        except OSError:
            pass
    if line:
        target = f"{path}:{line}"
    subprocess.Popen([ZED, target], cwd=project_root(path),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return [text(f"Opened file: {path}")]


TOOLS = {
    "openDiff": "Open a diff of proposed changes in Zed (blocking)",
    "openFile": "Open a file in Zed",
    "close_tab": "Close a diff tab",
    "closeAllDiffTabs": "Close all diff tabs",
}


async def call_tool(name: str, args: dict, diffs: dict[str, Diff]) -> list[dict]:
    log.info("tool %s %s", name, {k: v for k, v in args.items() if k != "new_file_contents"})
    match name:
        case "openDiff":
            diff = Diff(args["old_file_path"], args["new_file_path"],
                        args["new_file_contents"], args["tab_name"])
            if prev := diffs.pop(diff.tab, None):  # stale re-open of same tab
                prev.close()
            diffs[diff.tab] = diff
            try:
                return await diff.run()
            finally:
                diff.close()
                if diffs.get(diff.tab) is diff:
                    del diffs[diff.tab]
        case "openFile":
            return open_file(args)
        case "close_tab":
            if d := diffs.pop(args.get("tab_name", ""), None):
                d.close()
            return [text("TAB_CLOSED")]
        case "closeAllDiffTabs":
            n = len(diffs)
            for d in diffs.values():
                d.close()
            diffs.clear()
            return [text(f"CLOSED_{n}_DIFF_TABS")]
        case _:
            raise ValueError(f"unknown tool {name}")


async def handle(ws):
    diffs: dict[str, Diff] = {}  # tab_name -> pending diff, per Claude session

    async def send(obj: dict):
        try:
            await ws.send(json.dumps(obj))
        except ConnectionClosed:
            pass

    async def respond(msg: dict):
        mid, method = msg.get("id"), msg.get("method")
        params = msg.get("params") or {}
        if method == "initialize":
            result = {
                "protocolVersion": params.get("protocolVersion", "2025-03-26"),
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "claude-zed-bridge", "version": "0.1.0"},
            }
        elif method == "tools/list":
            result = {"tools": [
                {"name": n, "description": d, "inputSchema": {"type": "object"}}
                for n, d in TOOLS.items()
            ]}
        elif method == "tools/call":
            try:
                content = await call_tool(params["name"], params.get("arguments") or {}, diffs)
                result = {"content": content}
            except Exception as e:
                log.exception("tool failed")
                result = {"content": [text(f"Error: {e}")], "isError": True}
        elif method == "ping":
            result = {}
        else:
            if mid is not None:
                await send({"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32601, "message": f"Method not found: {method}"}})
            return
        if mid is not None:
            await send({"jsonrpc": "2.0", "id": mid, "result": result})

    log.info("claude connected")
    tasks = set()
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            if "method" not in msg:
                continue  # response to something we never send
            t = asyncio.create_task(respond(msg))  # openDiff blocks; keep reading
            tasks.add(t)
            t.add_done_callback(tasks.discard)
    except ConnectionClosed:
        pass
    finally:
        for t in list(tasks):  # pending openDiffs: their finally closes the diff
            t.cancel()
        log.info("claude disconnected")


def check_auth(connection, request):
    if not secrets.compare_digest(request.headers.get("x-claude-code-ide-authorization", ""), TOKEN):
        return Response(401, "Unauthorized", Headers())


async def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    os.umask(0o077)  # lockfile/state hold the auth token
    kw = {"process_request": check_auth, "subprotocols": ["mcp"], "max_size": None}
    try:
        server = await serve(handle, "127.0.0.1", _saved.get("port", 0), **kw)
    except OSError:  # saved port taken
        server = await serve(handle, "127.0.0.1", 0, **kw)
    async with server:
        port = server.sockets[0].getsockname()[1]
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({"port": port, "token": TOKEN}))
        LOCK_DIR.mkdir(parents=True, exist_ok=True)
        lock = LOCK_DIR / f"{port}.lock"
        lock.write_text(json.dumps({
            "pid": os.getpid(), "workspaceFolders": FOLDERS, "ideName": "Zed",
            "transport": "ws", "runningInWindows": False, "authToken": TOKEN,
        }))
        log.info("listening on %d, lock %s, folders %s", port, lock, FOLDERS)
        stop = asyncio.Event()
        for s in (signal.SIGINT, signal.SIGTERM):
            asyncio.get_running_loop().add_signal_handler(s, stop.set)
        try:
            await stop.wait()
        finally:
            lock.unlink(missing_ok=True)
            shutil.rmtree(TMP, ignore_errors=True)


if __name__ == "__main__":
    asyncio.run(main())
