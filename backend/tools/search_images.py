"""Tool: generate reference images using Gemini native image generation."""

import base64
import logging
import os

from google import genai

logger = logging.getLogger("clutch.tools.search_images")


async def search_images(query: str, num_results: int = 1) -> list[dict]:
    """Generate a reference image for a task step using Gemini image generation.

    Args:
        query: Description of what to illustrate.
        num_results: Number of images (default 1, max 2).

    Returns:
        List of dicts with title, image_url as base64 data URL.
    """
    num_results = min(max(num_results, 1), 2)

    api_key = os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        logger.error("GOOGLE_API_KEY not set")
        return []

    client = genai.Client(api_key=api_key)

    prompt = (
        f"Generate a clear, helpful instructional reference image showing: {query}. "
        "Make it a clean, well-lit, realistic photo or diagram that would help someone "
        "understand this step. No text overlays. Simple and easy to understand."
    )

    images = []
    for i in range(num_results):
        try:
            logger.info("Generating image %d/%d for: %s", i + 1, num_results, query)
            response = await client.aio.models.generate_content(
                model="gemini-2.5-flash-image",
                contents=[prompt],
            )

            if not response.candidates:
                logger.warning("No candidates in response for '%s'", query)
                continue

            for part in response.candidates[0].content.parts:
                if part.inline_data and part.inline_data.mime_type and part.inline_data.mime_type.startswith("image/"):
                    raw = part.inline_data.data
                    b64 = base64.b64encode(raw).decode()
                    mime = part.inline_data.mime_type
                    data_url = f"data:{mime};base64,{b64}"
                    logger.info("Generated image: mime=%s, size=%d bytes", mime, len(raw))
                    images.append({
                        "title": f"AI-generated: {query}",
                        "image_url": data_url,
                        "thumbnail_url": data_url,
                        "ai_generated": True,
                    })
                    break

        except Exception as e:
            logger.warning("Image generation failed for '%s' (attempt %d): %s", query, i + 1, e)

    logger.info("search_images returning %d images", len(images))
    return images
