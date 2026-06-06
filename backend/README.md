# Backend

Run the development server from the repository root:

```sh
python3 -m uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

The iOS app currently connects to:

```text
http://10.10.11.214:8000
```

The Explorer endpoint is hard-wired to:

```text
/Users/jules/Documents/testrepo1234
```

Qwen Code chat endpoints also run `qwen` from that same workspace.
