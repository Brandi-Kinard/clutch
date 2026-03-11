"""Tool: annotate a live camera frame to highlight a specific object."""

import asyncio
import base64
import io
import json
import logging
import os
from contextvars import ContextVar

from google import genai
from google.genai import types

logger = logging.getLogger("clutch.tools.annotate_image")

# Set by server.py per-session so the tool knows which frame to use.
# asyncio.create_task() copies the current context, so a value set before
# task creation is visible inside the task (and all tools it calls).
session_id_var: ContextVar[str] = ContextVar("session_id", default="")

# Module-level frame store: session_id -> latest JPEG bytes
_latest_frames: dict[str, bytes] = {}


def set_latest_frame(session_id: str, jpeg_bytes: bytes) -> None:
    """Called by server.py each time a video frame arrives."""
    _latest_frames[session_id] = jpeg_bytes


def get_latest_frame(session_id: str) -> bytes | None:
    return _latest_frames.get(session_id)


def clear_session(session_id: str) -> None:
    _latest_frames.pop(session_id, None)


BBOX_PROMPT = """\
You are a computer vision assistant. The user wants to find: {query}

Look at the image carefully and:
1. If you find it, return ONLY valid JSON:
{{"found": true, "label": "<short 1-3 word name>", "description": "<1 sentence>", "box_2d": [y_min, x_min, y_max, x_max]}}
where coordinates are integers 0-1000 (0 = top or left edge, 1000 = bottom or right edge).

2. If you cannot find it, return ONLY:
{{"found": false}}

Return ONLY the JSON object. No markdown fences, no explanation."""


def _draw_annotation(jpeg_bytes: bytes, box: list[int], label: str) -> bytes:
    """Draw a violet rounded-rect + label pill on the image using Pillow."""
    from PIL import Image, ImageDraw, ImageFont  # local import — Pillow optional at module level

    img = Image.open(io.BytesIO(jpeg_bytes)).convert("RGBA")
    W, H = img.size

    y_min, x_min, y_max, x_max = box
    left   = int(x_min / 1000 * W)
    top    = int(y_min / 1000 * H)
    right  = int(x_max / 1000 * W)
    bottom = int(y_max / 1000 * H)

    # Clamp
    left, right = max(0, left), min(W, right)
    top, bottom = max(0, top), min(H, bottom)

    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    radius = max(8, (right - left) // 20)
    # Semi-transparent violet fill + solid border
    draw.rounded_rectangle(
        [left, top, right, bottom],
        radius=radius,
        outline=(167, 139, 250, 255),
        width=3,
        fill=(167, 139, 250, 45),
    )

    # Font with cross-platform fallbacks
    font = None
    for path in [
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]:
        try:
            font = ImageFont.truetype(path, 17)
            break
        except Exception:
            pass
    if font is None:
        font = ImageFont.load_default()

    # Label pill above the box
    text_bbox = draw.textbbox((0, 0), label, font=font)
    tw = text_bbox[2] - text_bbox[0]
    th = text_bbox[3] - text_bbox[1]
    pad = 6
    pill_x0 = left
    pill_y0 = max(0, top - th - pad * 2 - 4)
    pill_x1 = pill_x0 + tw + pad * 2
    pill_y1 = pill_y0 + th + pad * 2
    draw.rounded_rectangle(
        [pill_x0, pill_y0, pill_x1, pill_y1],
        radius=6,
        fill=(167, 139, 250, 230),
    )
    draw.text((pill_x0 + pad, pill_y0 + pad), label, font=font, fill=(255, 255, 255, 255))

    out = Image.alpha_composite(img, overlay).convert("RGB")
    buf = io.BytesIO()
    out.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


async def annotate_image(query: str) -> dict:
    """Highlight a specific object in the user's live camera view.

    Finds the object described by `query` in the latest camera frame,
    draws a violet bounding-box overlay using Gemini Vision + Pillow,
    and returns the annotated image.

    Args:
        query: What to find and highlight (e.g. "the oil dipstick").

    Returns:
        dict with action="annotate", image (data URL), label, description
        — or action="not_found" with a message if not visible.
    """
    session_id = session_id_var.get()
    jpeg_bytes = get_latest_frame(session_id)

    if not jpeg_bytes:
        logger.warning("annotate_image: no frame for session %s", session_id)
        return {"action": "not_found", "message": "No camera frame available yet. Try again in a moment."}

    client = genai.Client(api_key=os.environ.get("GOOGLE_API_KEY"))
    prompt = BBOX_PROMPT.format(query=query)

    try:
        response = await client.aio.models.generate_content(
            model="gemini-2.5-flash",
            contents=types.Content(
                role="user",
                parts=[
                    types.Part.from_bytes(data=jpeg_bytes, mime_type="image/jpeg"),
                    types.Part.from_text(text=prompt),
                ],
            ),
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.1,
            ),
        )
        result = json.loads(response.text)
    except Exception as e:
        logger.error("annotate_image: Gemini call failed: %s", e)
        return {"action": "not_found", "message": "Could not analyze the image."}

    if not result.get("found"):
        return {"action": "not_found", "message": f"I can't see '{query}' in the current view."}

    box = result.get("box_2d", [])
    label = result.get("label", query)
    description = result.get("description", "")

    if not box or len(box) != 4:
        return {"action": "not_found", "message": f"Found '{query}' but couldn't pinpoint it precisely."}

    try:
        annotated = await asyncio.to_thread(_draw_annotation, jpeg_bytes, box, label)
    except Exception as e:
        logger.error("annotate_image: Pillow draw failed: %s", e)
        annotated = jpeg_bytes  # fall back to unannotated frame

    b64 = base64.b64encode(annotated).decode()
    logger.info("annotate_image: '%s' found, returning annotated JPEG", query)
    return {
        "action": "annotate",
        "image": f"data:image/jpeg;base64,{b64}",
        "label": label,
        "description": description,
    }
