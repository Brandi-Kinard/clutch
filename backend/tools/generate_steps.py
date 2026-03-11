"""Tool: generate step-by-step instructions for a task."""

import asyncio
import base64
import json
import logging
import os
import urllib.request

from google import genai
from google.genai import types

from .annotate_image import session_id_var

logger = logging.getLogger("clutch.tools.generate_steps")

# Stores full step data (with base64 images) keyed by session_id.
# The tool returns only a tiny summary to the bidi stream; server.py reads this
# dict to send the full payload directly to the frontend WebSocket.
_pending_steps: dict[str, dict] = {}


def get_pending_steps(session_id: str) -> dict | None:
    """Pop and return the pending steps for a session, or None."""
    return _pending_steps.pop(session_id, None)

MAX_IMAGES = 4  # cap parallel image generation to keep latency reasonable

STEPS_PROMPT = """\
You are a hands-on expert generating step-by-step instructions for a physical \
task. Write like a patient friend explaining to someone doing this for the \
first time.

Rules:
- Plain language, no jargon
- Each step should be one clear action
- Include what tools or materials are needed per step
- Include a short image_search_query for each step (what someone would Google \
Image search to see that step)
- 5-12 steps max

Return ONLY valid JSON:
{
  "steps": [
    {
      "number": 1,
      "instruction": "...",
      "tools_needed": ["..."],
      "image_search_query": "..."
    }
  ]
}

Task to generate steps for:
"""


def _call_imagen_api(prompt: str) -> str | None:
    """Synchronous Imagen 4 Fast REST call. Wrapped in asyncio.to_thread for parallel use."""
    api_key = os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        return None
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"imagen-4.0-fast-generate-001:predict?key={api_key}"
    )
    payload = json.dumps({
        "instances": [{"prompt": prompt}],
        "parameters": {"sampleCount": 1},
    }).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = json.loads(resp.read())
    b64 = data["predictions"][0]["bytesBase64Encoded"]
    return f"data:image/jpeg;base64,{b64}"


async def _generate_image_for_step(step: dict) -> str | None:
    """Generate an Imagen 4 Fast image for a single step. Returns a data URL or None."""
    query = step.get("image_search_query", "")
    if not query:
        return None
    prompt = (
        f"Generate a clear, helpful instructional reference image showing: {query}. "
        "Make it a clean, well-lit, realistic photo or diagram that would help someone "
        "understand this step. No text overlays. Simple and easy to understand."
    )
    try:
        data_url = await asyncio.to_thread(_call_imagen_api, prompt)
        return data_url
    except Exception as e:
        logger.warning("Imagen 4 Fast failed for step %s (%r): %s", step.get("number"), query, e)
    return None


async def generate_steps(task_description: str) -> dict:
    """Generate step-by-step instructions for a physical task, with images.

    Args:
        task_description: A description of the task the user needs help with.

    Returns:
        A lightweight dict with step count and summary. The full step data
        (including base64 images) is stored in _pending_steps and sent directly
        to the frontend by server.py, bypassing the bidi stream size limit.
    """
    client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"))
    response = await client.aio.models.generate_content(
        model="gemini-2.5-flash",
        contents=types.Content(
            role="user",
            parts=[types.Part.from_text(text=STEPS_PROMPT + task_description)],
        ),
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.3,
        ),
    )

    try:
        result = json.loads(response.text)
    except (json.JSONDecodeError, AttributeError):
        result = {"steps": [{"number": 1, "instruction": response.text or "Could not generate steps.", "tools_needed": [], "image_search_query": ""}]}

    steps = result.get("steps", [])

    # Generate images in parallel for the first MAX_IMAGES steps via Imagen 4 Fast
    image_steps = steps[:MAX_IMAGES]
    if image_steps:
        logger.info("Generating Imagen 4 Fast images for %d steps in parallel", len(image_steps))
        image_tasks = [_generate_image_for_step(step) for step in image_steps]
        image_results = await asyncio.gather(*image_tasks)
        for step, data_url in zip(image_steps, image_results):
            step["image_data_url"] = data_url
            logger.info("Step %s image: %s", step.get("number"), "ok" if data_url else "none")

    # Steps beyond MAX_IMAGES get null image_data_url
    for step in steps[MAX_IMAGES:]:
        step["image_data_url"] = None

    # Store full data (with base64 images) for server.py to forward to the
    # frontend WebSocket directly — do NOT return it here or it will be sent
    # back through the bidi stream and trigger a 1007 size error.
    session_id = session_id_var.get()
    if session_id:
        _pending_steps[session_id] = result
        logger.info("Stored %d steps for session %s (bypassing bidi stream)", len(steps), session_id)
    else:
        logger.warning("generate_steps: no session_id in context, steps will not reach frontend")

    return {
        "action": "steps",
        "step_count": len(steps),
        "summary": f"Generated {len(steps)} steps for: {task_description}",
    }
