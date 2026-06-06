import asyncio
import fcntl
import os
import pty
import select
import struct
import subprocess
import termios
import threading
import uuid
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel


TERMINAL_ROOT = Path("/Users/jules/Documents/testrepo1234").resolve()
DEFAULT_COLS = 80
DEFAULT_ROWS = 24


class TerminalSummary(BaseModel):
    id: str
    title: str
    cwd: str
    created_at: str
    alive: bool


class TerminalListResponse(BaseModel):
    terminals: list[TerminalSummary]


class TerminalCreateRequest(BaseModel):
    title: Optional[str] = None
    cwd: Optional[str] = None


class TerminalResizeRequest(BaseModel):
    cols: int = DEFAULT_COLS
    rows: int = DEFAULT_ROWS


@dataclass
class TerminalClient:
    loop: asyncio.AbstractEventLoop
    queue: asyncio.Queue[str]


@dataclass
class TerminalSession:
    id: str
    title: str
    cwd: Path
    created_at: str
    process: subprocess.Popen
    master_fd: int
    output: deque[str] = field(default_factory=lambda: deque(maxlen=3000))
    clients: list[TerminalClient] = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    @property
    def alive(self) -> bool:
        return self.process.poll() is None

    def summary(self) -> TerminalSummary:
        return TerminalSummary(
            id=self.id,
            title=self.title,
            cwd=str(self.cwd),
            created_at=self.created_at,
            alive=self.alive,
        )

    def write(self, data: str) -> None:
        if not self.alive:
            raise HTTPException(status_code=410, detail="Terminal has exited")
        os.write(self.master_fd, data.encode("utf-8", errors="replace"))

    def resize(self, cols: int, rows: int) -> None:
        cols = max(20, min(cols, 240))
        rows = max(5, min(rows, 80))
        packed = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, packed)

    def attach(self, client: TerminalClient) -> None:
        with self.lock:
            self.clients.append(client)
            replay = "".join(self.output)
        client.loop.call_soon_threadsafe(client.queue.put_nowait, replay)

    def detach(self, client: TerminalClient) -> None:
        with self.lock:
            if client in self.clients:
                self.clients.remove(client)

    def broadcast(self, data: str) -> None:
        with self.lock:
            self.output.append(data)
            clients = list(self.clients)
        for client in clients:
            client.loop.call_soon_threadsafe(client.queue.put_nowait, data)

    def terminate(self) -> None:
        if self.alive:
            self.process.terminate()
        try:
            os.close(self.master_fd)
        except OSError:
            pass


class TerminalManager:
    def __init__(self) -> None:
        self.sessions: dict[str, TerminalSession] = {}
        self.lock = threading.Lock()

    def list(self) -> TerminalListResponse:
        with self.lock:
            sessions = list(self.sessions.values())
        sessions.sort(key=lambda session: session.created_at)
        return TerminalListResponse(terminals=[session.summary() for session in sessions])

    def create(self, title: Optional[str] = None, cwd: Optional[str] = None) -> TerminalSession:
        terminal_id = str(uuid.uuid4())
        cwd_path = _safe_cwd(cwd)
        master_fd, slave_fd = pty.openpty()
        _set_nonblocking(master_fd)
        _set_window_size(master_fd, DEFAULT_COLS, DEFAULT_ROWS)

        env = os.environ.copy()
        env["TERM"] = "dumb"
        env["SHELL"] = "/bin/bash"
        env["PS1"] = r"\u@\h \W % "
        env["BASH_SILENCE_DEPRECATION_WARNING"] = "1"

        process = subprocess.Popen(
            ["/bin/bash", "--noprofile", "--norc", "-i"],
            cwd=str(cwd_path),
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=env,
            preexec_fn=os.setsid,
            close_fds=True,
        )
        os.close(slave_fd)

        session = TerminalSession(
            id=terminal_id,
            title=title or f"zsh {len(self.sessions) + 1}",
            cwd=cwd_path,
            created_at=datetime.now().isoformat(),
            process=process,
            master_fd=master_fd,
        )
        session.broadcast(_banner(cwd_path))

        with self.lock:
            self.sessions[terminal_id] = session

        thread = threading.Thread(target=_read_loop, args=(session,), daemon=True)
        thread.start()
        return session

    def get(self, terminal_id: str) -> TerminalSession:
        with self.lock:
            session = self.sessions.get(terminal_id)
        if session is None:
            raise HTTPException(status_code=404, detail="Terminal not found")
        return session

    def delete(self, terminal_id: str) -> None:
        session = self.get(terminal_id)
        session.terminate()
        with self.lock:
            self.sessions.pop(terminal_id, None)


manager = TerminalManager()


def list_terminals() -> TerminalListResponse:
    return manager.list()


def create_terminal(request: TerminalCreateRequest) -> TerminalSummary:
    return manager.create(request.title, request.cwd).summary()


def delete_terminal(terminal_id: str) -> dict[str, str]:
    manager.delete(terminal_id)
    return {"status": "ok"}


def resize_terminal(terminal_id: str, request: TerminalResizeRequest) -> TerminalSummary:
    session = manager.get(terminal_id)
    session.resize(request.cols, request.rows)
    return session.summary()


async def terminal_socket(terminal_id: str, websocket: WebSocket) -> None:
    await websocket.accept()
    session = manager.get(terminal_id)
    loop = asyncio.get_running_loop()
    client = TerminalClient(loop=loop, queue=asyncio.Queue())
    session.attach(client)

    async def send_output() -> None:
        while True:
            data = await client.queue.get()
            await websocket.send_json({"type": "output", "data": data})

    async def receive_input() -> None:
        while True:
            message = await websocket.receive_json()
            message_type = message.get("type")
            if message_type == "input":
                session.write(str(message.get("data", "")))
            elif message_type == "resize":
                session.resize(int(message.get("cols", DEFAULT_COLS)), int(message.get("rows", DEFAULT_ROWS)))

    sender = asyncio.create_task(send_output())
    receiver = asyncio.create_task(receive_input())
    try:
        done, pending = await asyncio.wait({sender, receiver}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        for task in done:
            try:
                task.result()
            except WebSocketDisconnect:
                pass
    finally:
        session.detach(client)


def _read_loop(session: TerminalSession) -> None:
    while session.alive:
        try:
            readable, _, _ = select.select([session.master_fd], [], [], 0.1)
            if not readable:
                continue
            data = os.read(session.master_fd, 4096)
            if not data:
                break
            session.broadcast(data.decode("utf-8", errors="replace"))
        except OSError:
            break
    session.broadcast("\r\n[process exited]\r\n")


def _set_nonblocking(fd: int) -> None:
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)


def _set_window_size(fd: int, cols: int, rows: int) -> None:
    packed = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)


def _safe_cwd(cwd: Optional[str]) -> Path:
    if cwd is None:
        return TERMINAL_ROOT
    path = Path(cwd).expanduser().resolve()
    if not path.exists() or not path.is_dir():
        raise HTTPException(status_code=400, detail=f"Invalid terminal cwd: {cwd}")
    return path


def _banner(cwd: Path) -> str:
    now = datetime.now().strftime("%a %b %e %H:%M:%S")
    return f"Last login: {now} on mobile-command-centre\r\n"
