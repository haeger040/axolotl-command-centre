import os
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Optional

from fastapi import HTTPException
from pydantic import BaseModel


REPO_ROOT = Path("/Users/jules/Documents/testrepo1234").resolve()
GIT_LOCK = threading.Lock()


class GitFile(BaseModel):
    path: str
    index_status: str
    worktree_status: str
    status: str
    staged: bool
    conflicted: bool


class GitStatusResponse(BaseModel):
    root: str
    branch: str
    upstream: Optional[str]
    ahead: int
    behind: int
    staged: list[GitFile]
    changes: list[GitFile]
    untracked: list[GitFile]
    conflicted: list[GitFile]


class GitDiffResponse(BaseModel):
    path: str
    staged: bool
    diff: str


class GitPathsRequest(BaseModel):
    paths: Optional[list[str]] = None


class GitCommitRequest(BaseModel):
    message: str


class GitCommandResponse(BaseModel):
    status: GitStatusResponse
    output: str = ""


def status() -> GitStatusResponse:
    _validate_repo()
    porcelain = _git(["status", "--porcelain=v1", "-b"])
    branch, upstream, ahead, behind = _parse_branch(porcelain.splitlines()[0] if porcelain else "")

    staged: list[GitFile] = []
    changes: list[GitFile] = []
    untracked: list[GitFile] = []
    conflicted: list[GitFile] = []

    for line in porcelain.splitlines()[1:]:
        if not line:
            continue

        index_status = line[0]
        worktree_status = line[1]
        raw_path = line[3:]
        path = _parse_status_path(raw_path)
        is_untracked = index_status == "?" and worktree_status == "?"
        is_conflicted = _is_conflicted(index_status, worktree_status)

        file = GitFile(
            path=path,
            index_status=index_status,
            worktree_status=worktree_status,
            status=_display_status(index_status, worktree_status),
            staged=index_status not in (" ", "?") and not is_conflicted,
            conflicted=is_conflicted,
        )

        if is_conflicted:
            conflicted.append(file)
        elif is_untracked:
            untracked.append(file)
        else:
            if file.staged:
                staged.append(file)
            if worktree_status != " ":
                changes.append(file)

    return GitStatusResponse(
        root=str(REPO_ROOT),
        branch=branch,
        upstream=upstream,
        ahead=ahead,
        behind=behind,
        staged=staged,
        changes=changes,
        untracked=untracked,
        conflicted=conflicted,
    )


def diff(path: str, staged: bool = False) -> GitDiffResponse:
    safe_path = _safe_relative_path(path)
    args = ["diff", "--", safe_path]
    if staged:
        args = ["diff", "--cached", "--", safe_path]
    return GitDiffResponse(path=safe_path, staged=staged, diff=_git(args))


def stage(paths: Optional[list[str]]) -> GitCommandResponse:
    safe_paths = _safe_paths(paths)
    _git(["add", "--", *safe_paths])
    return GitCommandResponse(status=status())


def unstage(paths: Optional[list[str]]) -> GitCommandResponse:
    safe_paths = _safe_paths(paths)
    _git(["restore", "--staged", "--", *safe_paths])
    return GitCommandResponse(status=status())


def discard(paths: Optional[list[str]]) -> GitCommandResponse:
    safe_paths = _safe_paths(paths)
    current = status()
    untracked_paths = {file.path for file in current.untracked}
    tracked_paths = [path for path in safe_paths if path not in untracked_paths]
    delete_paths = [path for path in safe_paths if path in untracked_paths]

    if tracked_paths:
        _git(["restore", "--", *tracked_paths])

    for path in delete_paths:
        target = _safe_absolute_path(path)
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()

    return GitCommandResponse(status=status())


def commit(message: str) -> GitCommandResponse:
    message = message.strip()
    if not message:
        raise HTTPException(status_code=400, detail="Commit message cannot be empty")
    output = _git(["commit", "-m", message])
    return GitCommandResponse(status=status(), output=output)


def fetch() -> GitCommandResponse:
    output = _git(["fetch"])
    return GitCommandResponse(status=status(), output=output)


def pull() -> GitCommandResponse:
    output = _git(["pull", "--ff-only"])
    return GitCommandResponse(status=status(), output=output)


def push() -> GitCommandResponse:
    output = _git(["push"])
    return GitCommandResponse(status=status(), output=output)


def sync() -> GitCommandResponse:
    before = status()
    outputs: list[str] = []
    if before.behind > 0:
        outputs.append(_git(["pull", "--ff-only"]))
    after_pull = status()
    if after_pull.ahead > 0:
        outputs.append(_git(["push"]))
    return GitCommandResponse(status=status(), output="\n".join(part for part in outputs if part))


def _git(args: list[str]) -> str:
    _validate_repo()
    with GIT_LOCK:
        process = subprocess.run(
            ["git", *args],
            cwd=str(REPO_ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip() or f"git {' '.join(args)} failed"
        raise HTTPException(status_code=502, detail=detail)
    return process.stdout.strip()


def _validate_repo() -> None:
    if not REPO_ROOT.exists() or not REPO_ROOT.is_dir():
        raise HTTPException(status_code=404, detail=f"Repository does not exist: {REPO_ROOT}")
    if not (REPO_ROOT / ".git").exists():
        raise HTTPException(status_code=400, detail=f"Not a Git repository: {REPO_ROOT}")


def _parse_branch(line: str) -> tuple[str, Optional[str], int, int]:
    if not line.startswith("## "):
        return "unknown", None, 0, 0

    value = line[3:]
    ahead = 0
    behind = 0
    upstream = None

    if "..." in value:
        branch, rest = value.split("...", 1)
        if " [" in rest:
            upstream, tracking = rest.split(" [", 1)
            tracking = tracking.rstrip("]")
            for part in tracking.split(", "):
                if part.startswith("ahead "):
                    ahead = int(part.removeprefix("ahead "))
                elif part.startswith("behind "):
                    behind = int(part.removeprefix("behind "))
        else:
            upstream = rest
        return branch, upstream, ahead, behind

    return value, None, 0, 0


def _parse_status_path(raw_path: str) -> str:
    if " -> " in raw_path:
        return raw_path.split(" -> ", 1)[1]
    return raw_path.strip('"')


def _display_status(index_status: str, worktree_status: str) -> str:
    if index_status == "?" and worktree_status == "?":
        return "untracked"
    if _is_conflicted(index_status, worktree_status):
        return "conflict"
    status_code = index_status if index_status != " " else worktree_status
    return {
        "A": "added",
        "M": "modified",
        "D": "deleted",
        "R": "renamed",
        "C": "copied",
        "T": "typechange",
    }.get(status_code, "changed")


def _is_conflicted(index_status: str, worktree_status: str) -> bool:
    return (index_status + worktree_status) in {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}


def _safe_paths(paths: Optional[list[str]]) -> list[str]:
    if not paths:
        return ["."]
    return [_safe_relative_path(path) for path in paths]


def _safe_relative_path(path: str) -> str:
    target = _safe_absolute_path(path)
    return os.path.relpath(target, REPO_ROOT)


def _safe_absolute_path(path: str) -> Path:
    target = (REPO_ROOT / path).resolve()
    if not str(target).startswith(str(REPO_ROOT)):
        raise HTTPException(status_code=400, detail=f"Path escapes repository: {path}")
    return target
