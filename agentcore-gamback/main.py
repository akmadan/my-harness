"""AgentCore Runtime entrypoint for the Gamback ADK copilot.

Implements the AgentCore Runtime HTTP contract directly: ``POST /invocations``
and ``GET /ping`` on 0.0.0.0:8080. The agent itself is a Google ADK ``LlmAgent``
whose model calls are routed through the Portkey gateway to Groq.

AgentCore sends a per-session header, so it is reused as the ADK session id and
multi-turn memory works without extra wiring. Sessions are process-local; the
runtime keeps an instance warm for the duration of a session.
"""

from __future__ import annotations

import logging
import os
import uuid
from functools import lru_cache

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from google.adk.agents import LlmAgent
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
from portkey_ai.integrations.adk import PortkeyAdk

logging.basicConfig(level=os.environ.get("AI_LOG_LEVEL", "INFO"))
logger = logging.getLogger("gamback.agentcore")

APP_NAME = "gamback-ai"
AGENT_NAME = "gamback_copilot"
DEFAULT_USER_ID = "anonymous"
SESSION_HEADER = "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id"

AGENT_DESCRIPTION = (
    "Gamback copilot — a conversational business assistant for small and "
    "mid-size business owners."
)

INSTRUCTION = """You are Gamback, an AI copilot and "second brain" for small \
and mid-size business owners.

Your job is to help the owner understand and act on their business data through \
natural conversation. Be concise, practical, and grounded in facts.

Guidelines:
- Answer clearly and directly; avoid jargon.
- When you are unsure or lack data, say so instead of guessing.
- Keep a helpful, professional, and friendly tone.
- Preserve conversational context across the session.

You currently have no external tools. When capabilities such as web search, \
data integrations, or write-back are available, use them only when they clearly \
help answer the owner's question."""


class LLMNotConfiguredError(RuntimeError):
    """Raised when the gateway credentials are missing."""


def _build_model() -> PortkeyAdk:
    portkey_api_key = os.environ.get("AI_PORTKEY_API_KEY", "")
    groq_api_key = os.environ.get("AI_GROQ_API_KEY", "")

    if not portkey_api_key:
        raise LLMNotConfiguredError("AI_PORTKEY_API_KEY is not set")
    if not groq_api_key:
        raise LLMNotConfiguredError("AI_GROQ_API_KEY is not set")

    kwargs: dict = {
        "model": os.environ.get("AI_LLM_MODEL", "llama-3.3-70b-versatile"),
        "api_key": portkey_api_key,
        "provider": os.environ.get("AI_LLM_PROVIDER", "groq"),
        "Authorization": f"Bearer {groq_api_key}",
    }
    base_url = os.environ.get("AI_PORTKEY_BASE_URL", "")
    if base_url:
        kwargs["base_url"] = base_url

    return PortkeyAdk(**kwargs)


# Built lazily so /ping stays healthy even when credentials are absent.
@lru_cache
def get_runner() -> Runner:
    agent = LlmAgent(
        name=AGENT_NAME,
        model=_build_model(),
        description=AGENT_DESCRIPTION,
        instruction=INSTRUCTION,
        tools=[],
    )
    return Runner(
        app_name=APP_NAME,
        agent=agent,
        session_service=InMemorySessionService(),
    )


app = FastAPI(title="Gamback copilot on AgentCore")


@app.get("/ping")
async def ping() -> dict:
    return {"status": "Healthy"}


@app.post("/invocations")
async def invocations(request: Request) -> JSONResponse:
    try:
        body = await request.json()
    except ValueError:
        return JSONResponse(status_code=400, content={"error": "body must be JSON"})

    prompt = body.get("prompt") or body.get("message") or ""
    if not isinstance(prompt, str) or not prompt.strip():
        return JSONResponse(status_code=400, content={"error": "'prompt' is required"})

    session_id = request.headers.get(SESSION_HEADER) or body.get("session_id") or uuid.uuid4().hex
    user_id = body.get("user_id") or DEFAULT_USER_ID

    try:
        runner = get_runner()
    except LLMNotConfiguredError as exc:
        logger.error("agent not configured: %s", exc)
        return JSONResponse(status_code=500, content={"error": str(exc)})

    session_service = runner.session_service
    existing = await session_service.get_session(
        app_name=APP_NAME, user_id=user_id, session_id=session_id
    )
    if existing is None:
        await session_service.create_session(
            app_name=APP_NAME, user_id=user_id, session_id=session_id
        )

    new_message = types.Content(role="user", parts=[types.Part.from_text(text=prompt)])

    reply_parts: list[str] = []
    async for event in runner.run_async(
        user_id=user_id, session_id=session_id, new_message=new_message
    ):
        if event.is_final_response() and event.content and event.content.parts:
            for part in event.content.parts:
                text = getattr(part, "text", None)
                if text:
                    reply_parts.append(text)

    return JSONResponse(
        content={
            "result": "".join(reply_parts),
            "session_id": session_id,
            "user_id": user_id,
        }
    )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
