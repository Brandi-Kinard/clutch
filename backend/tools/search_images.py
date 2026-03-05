"""Tool: search for relevant images using Google Custom Search API."""

import os

from googleapiclient.discovery import build


async def search_images(query: str, num_results: int = 3) -> list[dict]:
    """Search for images related to a task step using Google Custom Search.

    Args:
        query: The search query for finding relevant how-to images.
        num_results: Number of image results to return (default 3, max 10).

    Returns:
        List of dicts with title, image_url, thumbnail_url, and source_url.
    """
    api_key = os.environ.get("GOOGLE_SEARCH_API_KEY")
    cx = os.environ.get("GOOGLE_SEARCH_CX")

    if not api_key or not cx:
        return [{"error": "Google Custom Search API key or CX not configured."}]

    num_results = min(max(num_results, 1), 10)

    try:
        service = build("customsearch", "v1", developerKey=api_key)
        result = (
            service.cse()
            .list(q=query, cx=cx, searchType="image", num=num_results, safe="active")
            .execute()
        )

        images = []
        for item in result.get("items", []):
            images.append({
                "title": item.get("title", ""),
                "image_url": item.get("link", ""),
                "thumbnail_url": item.get("image", {}).get("thumbnailLink", ""),
                "source_url": item.get("image", {}).get("contextLink", ""),
            })
        return images

    except Exception as e:
        return [{"error": f"Image search failed: {str(e)}"}]
