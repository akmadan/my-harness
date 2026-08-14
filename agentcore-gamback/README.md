# Gamback copilot — AgentCore direct code deployment

A standalone package of the Gamback ADK copilot for Amazon Bedrock AgentCore
Runtime. Nothing here reads from or writes to
`~/Documents/My_Docs/Gamback/services/ai`; `main.py` is a self-contained copy of
that project's conversation agent (same instruction, same Portkey → Groq model)
behind the AgentCore HTTP contract.

## Layout

| File | Purpose |
| --- | --- |
| `main.py` | Entrypoint. Serves `POST /invocations` and `GET /ping` on `0.0.0.0:8080`. |
| `pyproject.toml` | Runtime dependencies only (no langchain, no dev tooling). |
| `build.sh` | Builds the arm64 zip to `~/Desktop/deployment_package.zip`. |

## Build

```bash
./build.sh
```

Produces roughly 21 MB zipped / 71 MB unzipped, against limits of 250 MB and
750 MB. The build fails if any bundled `.so` is not aarch64, since AgentCore
Runtime only supports arm64 and an x86 wheel deploys cleanly before failing at
startup with an opaque `424 RuntimeClientError`.

## Run locally

```bash
uv venv --python 3.12 .venv-local
uv pip install --python .venv-local/bin/python -r pyproject.toml
set -a && . /path/to/.env && set +a
.venv-local/bin/python main.py
```

```bash
curl localhost:8080/ping
curl -X POST localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "are you there?"}'
```

## Deploy

Upload the zip to S3, then run the Harness template
`ADK_Deployment_to_AWS_AgentCore` with:

| Variable | Value |
| --- | --- |
| `codeBucket` / `codeObjectKey` | wherever the zip was uploaded |
| `pythonRuntime` | `PYTHON_3_12` |
| `entrypoint` | `main.py` |
| `useOtel` | `false` — `aws-opentelemetry-distro` is not bundled |

The runtime needs `AI_PORTKEY_API_KEY` and `AI_GROQ_API_KEY` in its environment
variables. Optional: `AI_LLM_MODEL` (default `llama-3.3-70b-versatile`),
`AI_LLM_PROVIDER`, `AI_PORTKEY_BASE_URL`.

The AgentCore session header is used as the ADK session id, so multi-turn memory
works per session. Sessions are in-memory and process-local.
