import asyncio
import json
import os
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from fastapi import HTTPException
from pydantic import BaseModel


WORKSPACE_ROOT = Path("/Users/jules/Documents/testrepo1234").resolve()
DATA_DIR = Path(__file__).resolve().parent / "data"
CHATS_FILE = DATA_DIR / "qwen_chats.json"


class QwenMessage(BaseModel):
    id: str
    role: str
    content: str
    created_at: str


class QwenChat(BaseModel):
    id: str
    title: str
    workspace: str
    created_at: str
    updated_at: str
    messages: list[QwenMessage] = []


class QwenCreateChatRequest(BaseModel):
    prompt: Optional[str] = None


class QwenSendMessageRequest(BaseModel):
    prompt: str


class QwenChatSummary(BaseModel):
    id: str
    title: str
    workspace: str
    created_at: str
    updated_at: str
    message_count: int


class QwenChatsResponse(BaseModel):
    chats: list[QwenChatSummary]


def list_chats() -> QwenChatsResponse:
    chats = _load_chats()
    summaries = [
        QwenChatSummary(
            id=chat.id,
            title=chat.title,
            workspace=chat.workspace,
            created_at=chat.created_at,
            updated_at=chat.updated_at,
            message_count=len(chat.messages),
        )
        for chat in chats.values()
    ]
    summaries.sort(key=lambda chat: chat.updated_at, reverse=True)
    return QwenChatsResponse(chats=summaries)


def create_chat(prompt: Optional[str] = None) -> QwenChat:
    chats = _load_chats()
    now = _now()
    chat = QwenChat(
        id=str(uuid.uuid4()),
        title=_title_from_prompt(prompt) if prompt else "New Qwen Chat",
        workspace=str(WORKSPACE_ROOT),
        created_at=now,
        updated_at=now,
        messages=[],
    )
    chats[chat.id] = chat
    _save_chats(chats)
    return chat


def get_chat(chat_id: str) -> QwenChat:
    chats = _load_chats()
    chat = chats.get(chat_id)
    if chat is None:
        raise HTTPException(status_code=404, detail="Qwen chat not found")
    return chat


async def send_message(chat_id: str, prompt: str) -> QwenChat:
    prompt = prompt.strip()
    if not prompt:
        raise HTTPException(status_code=400, detail="Prompt cannot be empty")

    _validate_qwen()
    chats = _load_chats()
    chat = chats.get(chat_id)
    if chat is None:
        raise HTTPException(status_code=404, detail="Qwen chat not found")

    user_message = _message("user", prompt)
    assistant_text = await _run_qwen(chat, prompt)
    assistant_message = _message("assistant", assistant_text or "(No response)")

    if not chat.messages:
        chat.title = _title_from_prompt(prompt)

    chat.messages.extend([user_message, assistant_message])
    chat.updated_at = _now()
    chats[chat.id] = chat
    _save_chats(chats)
    return chat


async def _run_qwen(chat: QwenChat, prompt: str) -> str:
    args = [
        "qwen",
        "--chat-recording",
        "true",
        "--approval-mode",
        "yolo",
        "--output-format",
        "stream-json",
        "--include-partial-messages",
    ]

    if chat.messages:
        args.extend(["--resume", chat.id])
    else:
        args.extend(["--session-id", chat.id])

    args.extend(["--prompt", prompt])

    process = await asyncio.create_subprocess_exec(
        *args,
        cwd=str(WORKSPACE_ROOT),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=_qwen_env(),
    )

    final_result = ""
    assistant_chunks: list[str] = []

    assert process.stdout is not None
    async for raw_line in process.stdout:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        final_result = _result_text(event) or final_result
        delta = _delta_text(event)
        if delta:
            assistant_chunks.append(delta)

    stderr = ""
    if process.stderr is not None:
        stderr = (await process.stderr.read()).decode("utf-8", errors="replace").strip()

    return_code = await process.wait()
    if return_code != 0:
        detail = stderr or f"qwen exited with code {return_code}"
        raise HTTPException(status_code=502, detail=detail)

    if final_result:
        return final_result

    return "".join(assistant_chunks).strip()


def _result_text(event: dict[str, Any]) -> str:
    if event.get("type") == "result" and isinstance(event.get("result"), str):
        return event["result"].strip()
    return ""


def _delta_text(event: dict[str, Any]) -> str:
    if event.get("type") != "assistant":
        return ""

    message = event.get("message")
    if not isinstance(message, dict):
        return ""

    content = message.get("content")
    if not isinstance(content, list):
        return ""

    parts = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):
            parts.append(item["text"])
    return "".join(parts)


def _load_chats() -> dict[str, QwenChat]:
    if not CHATS_FILE.exists():
        return {}

    data = json.loads(CHATS_FILE.read_text())
    return {item["id"]: QwenChat.model_validate(item) for item in data.get("chats", [])}


def _save_chats(chats: dict[str, QwenChat]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"chats": [chat.model_dump() for chat in chats.values()]}
    CHATS_FILE.write_text(json.dumps(payload, indent=2))


def _message(role: str, content: str) -> QwenMessage:
    return QwenMessage(id=str(uuid.uuid4()), role=role, content=content, created_at=_now())


def _title_from_prompt(prompt: Optional[str]) -> str:
    if not prompt:
        return "New Qwen Chat"
    title = " ".join(prompt.strip().split())
    return title[:42] + ("..." if len(title) > 42 else "")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _validate_qwen() -> None:
    if not WORKSPACE_ROOT.exists() or not WORKSPACE_ROOT.is_dir():
        raise HTTPException(status_code=404, detail=f"Workspace does not exist: {WORKSPACE_ROOT}")
    if shutil.which("qwen", path=_qwen_env().get("PATH")) is None:
        raise HTTPException(status_code=500, detail="qwen executable not found in backend PATH")


def _qwen_env() -> dict[str, str]:
    env = os.environ.copy()
    node_bin = "/Users/jules/.nvm/versions/node/v20.20.2/bin"
    env["PATH"] = f"{node_bin}:{env.get('PATH', '')}"
    return env
