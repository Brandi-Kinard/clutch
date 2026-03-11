"""WebSocket server for Clutch — bridges frontend clients to the ADK live agent."""

import asyncio
import base64
import contextvars
import json
import logging
import os
import sys
import uuid

from dotenv import load_dotenv
from google.adk.agents import LiveRequestQueue, RunConfig
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types
import websockets
from websockets.asyncio.server import serve
from websockets.http11 import Response
from websockets.datastructures import Headers

load_dotenv()

# Ensure the backend package is importable
sys.path.insert(0, os.path.dirname(__file__))

from agent import clutch_agent
from tools.annotate_image import clear_session, get_pending_annotation, session_id_var, set_latest_frame
from tools.generate_steps import get_pending_steps

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("clutch.server")

APP_NAME = "clutch"
session_service = InMemorySessionService()

# Path to the frontend HTML file
HTML_PATH = os.path.join(os.path.dirname(__file__), "..", "web-app", "index.html")


def process_request(connection, request):
    """Serve index.html for HTTP GET /; pass through WebSocket upgrades."""
    if request.headers.get("Upgrade", "").lower() == "websocket" or request.path == "/ws":
        return None  # let the WebSocket handshake proceed
    if request.path == "/" or request.path == "/index.html":
        try:
            body = open(HTML_PATH, "rb").read()
        except FileNotFoundError:
            return Response(404, "Not Found", Headers(), b"index.html not found")
        headers = Headers([
            ("Content-Type", "text/html; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control", "no-cache"),
        ])
        return Response(200, "OK", headers, body)
    return Response(404, "Not Found", Headers(), b"Not Found")


LANGUAGE_NAMES = {
    "en": "English",
    "es": "Spanish",
    "vi": "Vietnamese",
    "fr": "French",
}


async def handle_client(websocket):
    """Handle a single WebSocket client connection with ADK live streaming."""
    user_id = f"user-{uuid.uuid4().hex[:8]}"
    session_id = f"session-{uuid.uuid4().hex[:8]}"
    logger.info("Client connected: user=%s session=%s", user_id, session_id)

    # Per-session language preference
    session_language = "en"

    # Create session
    session = await session_service.create_session(
        app_name=APP_NAME, user_id=user_id, session_id=session_id
    )

    runner = Runner(
        app_name=APP_NAME,
        agent=clutch_agent,
        session_service=session_service,
    )

    live_queue = LiveRequestQueue()

    # Set the session_id contextvar before creating the event task so the
    # annotate_image tool can look up the right frame via session_id_var.
    session_id_var.set(session_id)

    run_config = RunConfig(
        response_modalities=[types.Modality.AUDIO],
        output_audio_transcription=types.AudioTranscriptionConfig(),
        input_audio_transcription=types.AudioTranscriptionConfig(),
    )

    # Task to consume events from the agent and forward to the client
    async def forward_events():
        try:
            async for event in runner.run_live(
                user_id=user_id,
                session_id=session_id,
                live_request_queue=live_queue,
                run_config=run_config,
            ):
                msgs = _event_to_message(event)
                if msgs:
                    if not isinstance(msgs, list):
                        msgs = [msgs]
                    for msg in msgs:
                        try:
                            await websocket.send(json.dumps(msg, default=str))
                        except TypeError:
                            logger.warning("Skipping non-serializable event: %s", type(event))
        except Exception:
            logger.exception("Error in event stream")

    event_task = asyncio.create_task(forward_events())

    try:
        async for raw in websocket:
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                logger.warning("Received non-JSON message, ignoring")
                continue

            msg_type = data.get("type")

            if msg_type == "audio":
                # Audio chunk: base64-encoded audio bytes
                audio_bytes = base64.b64decode(data["data"])
                mime_type = data.get("mime_type", "audio/pcm;rate=16000")
                live_queue.send_realtime(
                    types.Blob(data=audio_bytes, mime_type=mime_type)
                )

            elif msg_type == "video":
                # Video frame: base64-encoded JPEG
                frame_bytes = base64.b64decode(data["data"])
                set_latest_frame(session_id, frame_bytes)
                live_queue.send_realtime(
                    types.Blob(data=frame_bytes, mime_type="image/jpeg")
                )

            elif msg_type == "text":
                # Text message from the user
                live_queue.send_content(
                    types.Content(
                        role="user",
                        parts=[types.Part.from_text(text=data["text"])],
                    )
                )

            elif msg_type == "config":
                if "language" in data:
                    session_language = data["language"]
                    lang_name = LANGUAGE_NAMES.get(session_language, session_language)
                    logger.info("Language switched to: %s (%s)", session_language, lang_name)
                else:
                    logger.info("Config update: %s", data)

            elif msg_type == "step_change":
                # User navigated to a different step in the wizard UI
                # Just log it server-side — do NOT send to agent (it reads it aloud)
                step_num = data.get("step_number", 0)
                total = data.get("total_steps", 0)
                logger.info("User moved to step %d/%d", step_num, total)

            elif msg_type in ("activity_start", "activity_end"):
                # Ignored — Gemini Live API uses automatic voice activity detection
                pass

            else:
                logger.warning("Unknown message type: %s", msg_type)

    except websockets.exceptions.ConnectionClosed:
        logger.info("Client disconnected: user=%s", user_id)
    finally:
        live_queue.close()
        event_task.cancel()
        try:
            await event_task
        except asyncio.CancelledError:
            pass
        clear_session(session_id)
        logger.info("Session ended: user=%s session=%s", user_id, session_id)


def _event_to_message(event) -> dict | None:
    """Convert an ADK Event to a JSON-serializable message for the frontend."""
    # Audio output from the model
    if event.content and event.content.parts:
        for part in event.content.parts:
            if part.inline_data and part.inline_data.mime_type and part.inline_data.mime_type.startswith("audio/"):
                return {
                    "type": "audio",
                    "data": base64.b64encode(part.inline_data.data).decode(),
                    "mime_type": part.inline_data.mime_type,
                }
            if part.text:
                return {
                    "type": "text",
                    "text": part.text,
                    "author": event.author or "clutch",
                }

    # Transcription events (Transcription objects have .text and .finished)
    if event.input_transcription:
        return {
            "type": "input_transcription",
            "text": event.input_transcription.text or "",
            "partial": not event.input_transcription.finished,
        }
    if event.output_transcription:
        return {
            "type": "output_transcription",
            "text": event.output_transcription.text or "",
            "partial": not event.output_transcription.finished,
        }

    # Function calls (agent requesting tool execution) — log for debugging
    function_calls = event.get_function_calls()
    if function_calls:
        for fc in function_calls:
            logger.info("Tool call: %s(%s)", fc.name, ", ".join(f"{k}={v!r:.80s}" if isinstance(v, str) else f"{k}={v!r}" for k, v in (fc.args or {}).items()))

    # Function call results (tool outputs with tutorial card data)
    function_responses = event.get_function_responses()
    if function_responses:
        results = []
        has_advance_step = False
        annotation_msg = None
        steps_msg = None
        for resp in function_responses:
            if resp.name == "advance_step":
                has_advance_step = True
                continue
            if resp.name == "annotate_image":
                # Full annotation (with base64 image) was stored out-of-band by the tool
                # to avoid exceeding the bidi stream size limit (1008 error).
                # The lightweight summary in resp.response tells us whether it succeeded.
                result = resp.response or {}
                if hasattr(result, "model_dump"):
                    result = result.model_dump()
                if isinstance(result, dict) and "result" in result and len(result) == 1:
                    result = result["result"]
                if isinstance(result, dict) and result.get("action") == "annotate_summary":
                    session_id = session_id_var.get()
                    full_annotation = get_pending_annotation(session_id) if session_id else None
                    if full_annotation:
                        annotation_msg = {
                            "type": "annotation",
                            "image": full_annotation["image"],
                            "label": full_annotation.get("label", ""),
                            "description": full_annotation.get("description", ""),
                        }
                        logger.info("annotate_image: forwarding annotation to frontend (bypassed bidi stream)")
                    else:
                        logger.warning("annotate_image: no pending annotation for session %s", session_id)
                else:
                    msg_text = result.get("message", "") if isinstance(result, dict) else ""
                    logger.info("annotate_image not_found: %s", msg_text)
                continue
            if resp.name == "generate_steps":
                # Full step data (with base64 images) was stored out-of-band by the
                # tool to avoid exceeding the bidi stream size limit. Retrieve it
                # here and ship it directly to the frontend WebSocket.
                session_id = session_id_var.get()
                full_data = get_pending_steps(session_id) if session_id else None
                if full_data:
                    steps_msg = {
                        "type": "tool_result",
                        "results": [{"tool": "generate_steps", "result": full_data}],
                    }
                    logger.info("generate_steps: forwarding %d steps to frontend (bypassed bidi stream)", len(full_data.get("steps", [])))
                else:
                    logger.warning("generate_steps: no pending steps found for session %s", session_id)
                continue
            if resp.response is not None:
                # resp.response may be a dict, list, or a pydantic model
                result = resp.response
                if hasattr(result, "model_dump"):
                    result = result.model_dump()
                # ADK may wrap result in {"result": ...}; unwrap if so
                if isinstance(result, dict) and "result" in result and len(result) == 1:
                    result = result["result"]
                logger.info("Tool response %s: type=%s keys=%s",
                    resp.name, type(result).__name__,
                    list(result.keys()) if isinstance(result, dict) else f"len={len(result)}" if isinstance(result, list) else "scalar")
                results.append({
                    "tool": resp.name,
                    "result": result,
                })
        msgs = []
        if has_advance_step:
            logger.info("advance_step tool called — signaling frontend")
            msgs.append({"type": "advance_step"})
        if annotation_msg:
            logger.info("annotate_image annotation ready — sending to frontend")
            msgs.append(annotation_msg)
        if steps_msg:
            msgs.append(steps_msg)
        if results:
            logger.info("Tool results: %s", [r["tool"] for r in results])
            msgs.append({"type": "tool_result", "results": results})
        if msgs:
            return msgs if len(msgs) > 1 else msgs[0]

    # Turn complete signal
    if event.turn_complete:
        return {"type": "turn_complete"}

    # Interrupted (barge-in)
    if event.interrupted:
        return {"type": "interrupted"}

    return None


async def main():
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8080"))

    logger.info("Clutch WebSocket server starting on ws://%s:%d", host, port)

    async with serve(
        handle_client, host, port,
        max_size=10 * 1024 * 1024,
        process_request=process_request,
    ):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
