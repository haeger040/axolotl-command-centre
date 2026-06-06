import shutil
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, WebSocket
from pydantic import AliasChoices, BaseModel, Field

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


class FileContentResponse(BaseModel):
    path: str
    name: str
    content: str


class FileSaveRequest(BaseModel):
    path: str
    content: str


class FilesystemCreateRequest(BaseModel):
    parent_path: str = Field(validation_alias=AliasChoices("parent_path", "parentPath"))
    name: str


class FilesystemRenameRequest(BaseModel):
    path: str
    name: str


class FilesystemCopyRequest(BaseModel):
    source_path: str = Field(validation_alias=AliasChoices("source_path", "sourcePath"))
    destination_folder: str = Field(validation_alias=AliasChoices("destination_folder", "destinationFolder"))


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/explorer", response_model=ExplorerResponse)
def explorer(path: Optional[str] = None) -> ExplorerResponse:
    if not EXPLORER_ROOT.exists():
        raise HTTPException(status_code=404, detail=f"Root does not exist: {EXPLORER_ROOT}")

    if not EXPLORER_ROOT.is_dir():
        raise HTTPException(status_code=400, detail=f"Root is not a directory: {EXPLORER_ROOT}")

    folder = _safe_folder_path(path or str(EXPLORER_ROOT))
    entries = [
        ExplorerEntry(
            name=entry.name,
            path=str(entry),
            kind="directory" if entry.is_dir() else "file",
        )
        for entry in folder.iterdir()
    ]
    entries.sort(key=lambda entry: (entry.kind != "directory", entry.name.lower()))

    return ExplorerResponse(root=str(folder), entries=entries)


@app.get("/files", response_model=FileContentResponse)
def read_file(path: str) -> FileContentResponse:
    file_path = _safe_file_path(path)
    data = file_path.read_bytes()
    if len(data) > 1_000_000:
        raise HTTPException(status_code=413, detail="File is too large to edit")
    if b"\x00" in data:
        raise HTTPException(status_code=415, detail="Binary files are not supported")
    try:
        content = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise HTTPException(status_code=415, detail="Only UTF-8 text files are supported") from error
    return FileContentResponse(path=str(file_path), name=file_path.name, content=content)


@app.put("/files", response_model=FileContentResponse)
def save_file(request: FileSaveRequest) -> FileContentResponse:
    file_path = _safe_file_path(request.path)
    encoded = request.content.encode("utf-8")
    if len(encoded) > 1_000_000:
        raise HTTPException(status_code=413, detail="File is too large to save")
    file_path.write_bytes(encoded)
    return FileContentResponse(path=str(file_path), name=file_path.name, content=request.content)


@app.post("/filesystem/file", response_model=ExplorerEntry)
def create_file(request: FilesystemCreateRequest) -> ExplorerEntry:
    parent = _safe_folder_path(request.parent_path)
    name = _safe_name(request.name)
    file_path = parent / name
    if file_path.exists():
        raise HTTPException(status_code=409, detail="A file or folder with that name already exists")
    file_path.write_text("", encoding="utf-8")
    return ExplorerEntry(name=file_path.name, path=str(file_path), kind="file")


@app.post("/filesystem/folder", response_model=ExplorerEntry)
def create_folder(request: FilesystemCreateRequest) -> ExplorerEntry:
    parent = _safe_folder_path(request.parent_path)
    name = _safe_name(request.name)
    folder_path = parent / name
    if folder_path.exists():
        raise HTTPException(status_code=409, detail="A file or folder with that name already exists")
    folder_path.mkdir()
    return ExplorerEntry(name=folder_path.name, path=str(folder_path), kind="directory")


@app.post("/filesystem/rename", response_model=ExplorerEntry)
def rename_path(request: FilesystemRenameRequest) -> ExplorerEntry:
    source = _safe_existing_path(request.path)
    name = _safe_name(request.name)
    destination = source.parent / name
    if destination.exists():
        raise HTTPException(status_code=409, detail="A file or folder with that name already exists")
    source.rename(destination)
    return ExplorerEntry(
        name=destination.name,
        path=str(destination),
        kind="directory" if destination.is_dir() else "file",
    )


@app.post("/filesystem/copy", response_model=ExplorerEntry)
def copy_path(request: FilesystemCopyRequest) -> ExplorerEntry:
    source = _safe_existing_path(request.source_path)
    destination_folder = _safe_folder_path(request.destination_folder)
    destination = destination_folder / source.name
    if destination.exists():
        raise HTTPException(status_code=409, detail="A file or folder with that name already exists")
    if source.is_dir() and destination_folder.is_relative_to(source):
        raise HTTPException(status_code=400, detail="Cannot copy a folder into itself")
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        shutil.copy2(source, destination)
    return ExplorerEntry(
        name=destination.name,
        path=str(destination),
        kind="directory" if destination.is_dir() else "file",
    )


@app.delete("/filesystem")
def delete_path(path: str) -> dict[str, str]:
    target = _safe_existing_path(path)
    if target == EXPLORER_ROOT:
        raise HTTPException(status_code=400, detail="Cannot delete the workspace root")
    if target.is_dir():
        shutil.rmtree(target)
    else:
        target.unlink()
    return {"status": "ok"}


def _safe_file_path(path: str) -> Path:
    file_path = _safe_existing_path(path)
    if not file_path.is_file():
        raise HTTPException(status_code=400, detail="Path is not a file")
    return file_path


def _safe_folder_path(path: str) -> Path:
    folder_path = _safe_existing_path(path)
    if not folder_path.is_dir():
        raise HTTPException(status_code=400, detail="Path is not a folder")
    return folder_path


def _safe_existing_path(path: str) -> Path:
    target = Path(path).expanduser().resolve()
    if not target.is_relative_to(EXPLORER_ROOT):
        raise HTTPException(status_code=403, detail="Path is outside the workspace")
    if not target.exists():
        raise HTTPException(status_code=404, detail=f"Path does not exist: {path}")
    return target


def _safe_name(name: str) -> str:
    clean = name.strip()
    if not clean:
        raise HTTPException(status_code=400, detail="Name cannot be empty")
    if clean in {".", ".."} or "/" in clean or "\\" in clean:
        raise HTTPException(status_code=400, detail="Invalid name")
    return clean


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
