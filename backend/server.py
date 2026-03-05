"""WebSocket server for Clutch — bridges frontend clients to the ADK live agent."""

import asyncio
import base64
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

load_dotenv()

# Ensure the backend package is importable
sys.path.insert(0, os.path.dirname(__file__))

from agent import clutch_agent

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("clutch.server")

APP_NAME = "clutch"
session_service = InMemorySessionService()


async def handle_client(websocket):
    """Handle a single WebSocket client connection with ADK live streaming."""
    user_id = f"user-{uuid.uuid4().hex[:8]}"
    session_id = f"session-{uuid.uuid4().hex[:8]}"
    logger.info("Client connected: user=%s session=%s", user_id, session_id)

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

    run_config = RunConfig(
        response_modalities=["AUDIO", "TEXT"],
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
                msg = _event_to_message(event)
                if msg:
                    await websocket.send(json.dumps(msg))
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

            elif msg_type == "activity_start":
                live_queue.send_activity_start()

            elif msg_type == "activity_end":
                live_queue.send_activity_end()

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

    # Transcription events
    if event.input_transcription:
        return {
            "type": "input_transcription",
            "text": event.input_transcription,
            "partial": event.partial or False,
        }
    if event.output_transcription:
        return {
            "type": "output_transcription",
            "text": event.output_transcription,
            "partial": event.partial or False,
        }

    # Function call results (tool outputs with tutorial card data)
    function_responses = event.get_function_responses()
    if function_responses:
        results = []
        for resp in function_responses:
            if resp.response:
                results.append({
                    "tool": resp.name,
                    "result": resp.response,
                })
        if results:
            return {
                "type": "tool_result",
                "results": results,
            }

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

    async with serve(handle_client, host, port, max_size=10 * 1024 * 1024):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
