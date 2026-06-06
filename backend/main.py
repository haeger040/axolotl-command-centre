from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


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
