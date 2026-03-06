"""Tool: analyze what physical task the user needs help with."""

import json
import os

from google import genai
from google.genai import types


ANALYSIS_PROMPT = """\
You are analyzing a video frame and/or audio transcript to identify what \
physical task a person needs help with.

Return ONLY valid JSON with this exact schema:
{
  "task_id": "<short-kebab-case-id>",
  "task_description": "<one sentence describing the task>",
  "domain": "<category like plumbing, automotive, cooking, electrical, etc.>",
  "safety_warnings": ["<any safety concern observed>"]
}

If the frame shows something dangerous (car engine running, exposed wires, gas \
leak indicators, etc.), include it in safety_warnings.

If you cannot determine the task, set task_id to "unknown" and ask for \
clarification in task_description.
"""


async def analyze_task(
    frame_base64: str = "",
    audio_transcript: str = "",
) -> dict:
    """Analyze a video frame and/or audio transcript to identify the physical task.

    Args:
        frame_base64: Base64-encoded JPEG image from the user's camera.
        audio_transcript: Text transcript of what the user said.

    Returns:
        dict with task_id, task_description, domain, and safety_warnings.
    """
    parts = []

    if frame_base64:
        import base64
        image_bytes = base64.b64decode(frame_base64)
        parts.append(types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))

    if audio_transcript:
        parts.append(types.Part.from_text(text=f"User said: {audio_transcript}"))

    if not parts:
        return {
            "task_id": "unknown",
            "task_description": "No frame or transcript provided. What do you need help with?",
            "domain": "unknown",
            "safety_warnings": [],
        }

    parts.insert(0, types.Part.from_text(text=ANALYSIS_PROMPT))

    client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"))
    response = await client.aio.models.generate_content(
        model="gemini-2.5-flash",
        contents=types.Content(role="user", parts=parts),
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.2,
        ),
    )

    try:
        return json.loads(response.text)
    except (json.JSONDecodeError, AttributeError):
        return {
            "task_id": "unknown",
            "task_description": response.text if response.text else "Could not analyze the image.",
            "domain": "unknown",
            "safety_warnings": [],
        }
