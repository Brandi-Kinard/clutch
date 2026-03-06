"""Tool: search YouTube for how-to videos."""

import asyncio
import os
import re

from googleapiclient.discovery import build


def _search_youtube_sync(query: str, max_results: int) -> list[dict]:
    """Synchronous YouTube search — runs in a thread pool."""
    api_key = os.environ.get("YOUTUBE_API_KEY")
    if not api_key:
        return [{"error": "YouTube API key not configured."}]

    youtube = build("youtube", "v3", developerKey=api_key)

    search_response = (
        youtube.search()
        .list(
            q=f"how to {query}",
            part="snippet",
            type="video",
            maxResults=max_results,
            order="relevance",
            safeSearch="moderate",
        )
        .execute()
    )

    video_ids = [item["id"]["videoId"] for item in search_response.get("items", [])]
    if not video_ids:
        return []

    details_response = (
        youtube.videos()
        .list(part="contentDetails,snippet", id=",".join(video_ids))
        .execute()
    )

    videos = []
    for item in details_response.get("items", []):
        duration_iso = item["contentDetails"]["duration"]
        videos.append({
            "title": item["snippet"]["title"],
            "channel": item["snippet"]["channelTitle"],
            "video_url": f"https://www.youtube.com/watch?v={item['id']}",
            "thumbnail": item["snippet"]["thumbnails"].get("high", {}).get("url", ""),
            "duration": _parse_duration(duration_iso),
        })
    return videos


async def search_youtube(query: str, max_results: int = 3) -> list[dict]:
    """Search YouTube for how-to videos related to the task.

    Args:
        query: The search query (e.g. "how to fix a leaky faucet").
        max_results: Number of results to return (default 3, max 5).

    Returns:
        List of dicts with title, channel, video_url, thumbnail, and duration.
    """
    max_results = min(max(max_results, 1), 5)

    try:
        return await asyncio.to_thread(_search_youtube_sync, query, max_results)
    except Exception as e:
        return [{"error": f"YouTube search failed: {str(e)}"}]


def _parse_duration(iso_duration: str) -> str:
    """Convert ISO 8601 duration (PT1H2M3S) to human-readable (1:02:03)."""
    match = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso_duration)
    if not match:
        return iso_duration
    h, m, s = (int(g) if g else 0 for g in match.groups())
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"
