"""Tool: search for relevant reference images (placeholder — image gen disabled)."""

import logging

logger = logging.getLogger("clutch.tools.search_images")


async def search_images(query: str, num_results: int = 1) -> list[dict]:
    """Search for reference images related to a task step.

    Note: Image generation is currently disabled. Returns empty list.
    The wizard UI focuses on clear text instructions instead.

    Args:
        query: Description of what to illustrate.
        num_results: Number of images (currently ignored).

    Returns:
        Empty list (image generation disabled).
    """
    logger.info("search_images called for '%s' — image generation disabled, returning empty", query)
    return []
