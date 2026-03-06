"""Tool: generate step-by-step instructions for a task."""

import json
import os

from google import genai
from google.genai import types


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


async def generate_steps(task_description: str) -> dict:
    """Generate step-by-step instructions for a physical task.

    Args:
        task_description: A description of the task the user needs help with.

    Returns:
        dict with a list of steps, each containing number, instruction,
        tools_needed, and image_search_query.
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
        return json.loads(response.text)
    except (json.JSONDecodeError, AttributeError):
        return {"steps": [{"number": 1, "instruction": response.text or "Could not generate steps.", "tools_needed": [], "image_search_query": ""}]}
