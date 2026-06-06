# Axolotl Command Centre

Axolotl is a mobile command centre for AI coding agents. It lets you connect your iPhone to your Mac, browse and edit project files, work with Qwen Code, use a persistent terminal, review source control changes, run commands, and push work from one focused mobile interface.

## Usage

Paste this inside `/Users/jules/Documents/axolotl-command-centre` on the Mac:

```sh
.venv/bin/python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```
