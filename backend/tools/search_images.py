"""Tool: generate reference images using Imagen 4 Fast."""

import asyncio
import json
import logging
import os
import urllib.request

logger = logging.getLogger("clutch.tools.search_images")


def _call_imagen_api(prompt: str) -> str | None:
    """Synchronous Imagen 4 Fast REST call. Returns a JPEG data URL or None."""
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


async def search_images(query: str, num_results: int = 1) -> list[dict]:
    """Generate a reference image for a task step using Imagen 4 Fast.

    Args:
        query: Description of what to illustrate.
        num_results: Number of images (default 1, max 2).

    Returns:
        List of dicts with title, image_url as base64 data URL.
    """
    num_results = min(max(num_results, 1), 2)

    if not os.environ.get("GOOGLE_API_KEY"):
        logger.error("GOOGLE_API_KEY not set")
        return []

    prompt = (
        f"Generate a clear, helpful instructional reference image showing: {query}. "
        "Make it a clean, well-lit, realistic photo or diagram that would help someone "
        "understand this step. No text overlays. Simple and easy to understand."
    )

    images = []
    for i in range(num_results):
        try:
            logger.info("Generating Imagen 4 Fast image %d/%d for: %s", i + 1, num_results, query)
            data_url = await asyncio.to_thread(_call_imagen_api, prompt)
            if data_url:
                logger.info("Generated image %d: ok", i + 1)
                images.append({
                    "title": f"AI-generated: {query}",
                    "image_url": data_url,
                    "thumbnail_url": data_url,
                    "ai_generated": True,
                })
        except Exception as e:
            logger.warning("Imagen 4 Fast failed for '%s' (attempt %d): %s", query, i + 1, e)

    logger.info("search_images returning %d images", len(images))
    return images
