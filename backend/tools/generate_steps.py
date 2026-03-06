"""Tool: generate step-by-step instructions for a task."""

import asyncio
import base64
import json
import logging
import os

from google import genai
from google.genai import types

logger = logging.getLogger("clutch.tools.generate_steps")

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


async def _generate_image_for_step(client: genai.Client, step: dict) -> str | None:
    """Generate an image for a single step. Returns a base64 data URL or None."""
    query = step.get("image_search_query", "")
    if not query:
        return None
    prompt = (
        f"Generate a clear, helpful instructional reference image showing: {query}. "
        "Make it a clean, well-lit, realistic photo or diagram that would help someone "
        "understand this step. No text overlays. Simple and easy to understand."
    )
    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash-image",
            contents=[prompt],
        )
        if not response.candidates:
            return None
        for part in response.candidates[0].content.parts:
            if part.inline_data and part.inline_data.mime_type and part.inline_data.mime_type.startswith("image/"):
                b64 = base64.b64encode(part.inline_data.data).decode()
                return f"data:{part.inline_data.mime_type};base64,{b64}"
    except Exception as e:
        logger.warning("Image generation failed for step %s (%r): %s", step.get("number"), query, e)
    return None


async def generate_steps(task_description: str) -> dict:
    """Generate step-by-step instructions for a physical task, with images.

    Args:
        task_description: A description of the task the user needs help with.

    Returns:
        dict with a list of steps, each containing number, instruction,
        tools_needed, image_search_query, and image_data_url.
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

    # Generate images in parallel for the first MAX_IMAGES steps
    image_steps = steps[:MAX_IMAGES]
    if image_steps:
        logger.info("Generating images for %d steps in parallel", len(image_steps))
        image_tasks = [_generate_image_for_step(client, step) for step in image_steps]
        image_results = await asyncio.gather(*image_tasks)
        for step, data_url in zip(image_steps, image_results):
            step["image_data_url"] = data_url
            logger.info("Step %s image: %s", step.get("number"), "ok" if data_url else "none")

    # Steps beyond MAX_IMAGES get null image_data_url
    for step in steps[MAX_IMAGES:]:
        step["image_data_url"] = None

    return result
