from pathlib import Path

from fastapi import FastAPI, HTTPException, WebSocket
from pydantic import BaseModel

from backend import git_service, qwen_service, terminal_service


EXPLORER_ROOT = Path("/Users/jules/Documents/testrepo1234").resolve()

app = FastAPI(title="Axolotl Command Centre")


class ExplorerEntry(BaseModel):
    name: str
    path: str
    kind: str


class ExplorerResponse(BaseModel):
    root: str
    entries: list[ExplorerEntry]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/explorer", response_model=ExplorerResponse)
def explorer() -> ExplorerResponse:
    if not EXPLORER_ROOT.exists():
        raise HTTPException(status_code=404, detail=f"Root does not exist: {EXPLORER_ROOT}")

    if not EXPLORER_ROOT.is_dir():
        raise HTTPException(status_code=400, detail=f"Root is not a directory: {EXPLORER_ROOT}")

    entries = [
        ExplorerEntry(
            name=entry.name,
            path=str(entry),
            kind="directory" if entry.is_dir() else "file",
        )
        for entry in EXPLORER_ROOT.iterdir()
    ]
    entries.sort(key=lambda entry: (entry.kind != "directory", entry.name.lower()))

    return ExplorerResponse(root=str(EXPLORER_ROOT), entries=entries)


@app.get("/qwen/chats", response_model=qwen_service.QwenChatsResponse)
def qwen_chats() -> qwen_service.QwenChatsResponse:
    return qwen_service.list_chats()


@app.post("/qwen/chats", response_model=qwen_service.QwenChat)
def qwen_create_chat(request: qwen_service.QwenCreateChatRequest) -> qwen_service.QwenChat:
    return qwen_service.create_chat(request.prompt)


@app.get("/qwen/chats/{chat_id}", response_model=qwen_service.QwenChat)
def qwen_get_chat(chat_id: str) -> qwen_service.QwenChat:
    return qwen_service.get_chat(chat_id)


@app.post("/qwen/chats/{chat_id}/messages", response_model=qwen_service.QwenChat)
async def qwen_send_message(chat_id: str, request: qwen_service.QwenSendMessageRequest) -> qwen_service.QwenChat:
    return await qwen_service.send_message(chat_id, request.prompt)


@app.get("/git/status", response_model=git_service.GitStatusResponse)
def git_status() -> git_service.GitStatusResponse:
    return git_service.status()


@app.get("/git/diff", response_model=git_service.GitDiffResponse)
def git_diff(path: str, staged: bool = False) -> git_service.GitDiffResponse:
    return git_service.diff(path, staged)


@app.post("/git/stage", response_model=git_service.GitCommandResponse)
def git_stage(request: git_service.GitPathsRequest) -> git_service.GitCommandResponse:
    return git_service.stage(request.paths)


@app.post("/git/unstage", response_model=git_service.GitCommandResponse)
def git_unstage(request: git_service.GitPathsRequest) -> git_service.GitCommandResponse:
    return git_service.unstage(request.paths)


@app.post("/git/discard", response_model=git_service.GitCommandResponse)
def git_discard(request: git_service.GitPathsRequest) -> git_service.GitCommandResponse:
    return git_service.discard(request.paths)


@app.post("/git/commit", response_model=git_service.GitCommandResponse)
def git_commit(request: git_service.GitCommitRequest) -> git_service.GitCommandResponse:
    return git_service.commit(request.message)


@app.post("/git/fetch", response_model=git_service.GitCommandResponse)
def git_fetch() -> git_service.GitCommandResponse:
    return git_service.fetch()


@app.post("/git/pull", response_model=git_service.GitCommandResponse)
def git_pull() -> git_service.GitCommandResponse:
    return git_service.pull()


@app.post("/git/push", response_model=git_service.GitCommandResponse)
def git_push() -> git_service.GitCommandResponse:
    return git_service.push()


@app.post("/git/sync", response_model=git_service.GitCommandResponse)
def git_sync() -> git_service.GitCommandResponse:
    return git_service.sync()


@app.get("/terminals", response_model=terminal_service.TerminalListResponse)
def terminals() -> terminal_service.TerminalListResponse:
    return terminal_service.list_terminals()


@app.post("/terminals", response_model=terminal_service.TerminalSummary)
def create_terminal(request: terminal_service.TerminalCreateRequest) -> terminal_service.TerminalSummary:
    return terminal_service.create_terminal(request)


@app.delete("/terminals/{terminal_id}")
def delete_terminal(terminal_id: str) -> dict[str, str]:
    return terminal_service.delete_terminal(terminal_id)


@app.post("/terminals/{terminal_id}/resize", response_model=terminal_service.TerminalSummary)
def resize_terminal(terminal_id: str, request: terminal_service.TerminalResizeRequest) -> terminal_service.TerminalSummary:
    return terminal_service.resize_terminal(terminal_id, request)


@app.websocket("/terminals/{terminal_id}/ws")
async def terminal_ws(terminal_id: str, websocket: WebSocket) -> None:
    await terminal_service.terminal_socket(terminal_id, websocket)
