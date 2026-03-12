"""Tool: search for nearby products matching a query (mock data, no API)."""

import logging

logger = logging.getLogger("clutch.tools.search_products")

_DRYWALL_PRODUCTS = [
    {
        "name": "DAP DryDex Spackling",
        "price": "$7.98",
        "store": "Home Depot",
        "rating": 4.6,
        "reviews": 2847,
        "distance_mi": 3.2,
        "thumbnail": "https://images.thdstatic.com/productImages/305b60f8-dc64-40ca-8510-bf6ec9d1b63a/svn/dap-spackle-12348-64_1000.jpg",
        "url": "https://www.homedepot.com",
    },
    {
        "name": "3M Patch Plus Primer",
        "price": "$9.47",
        "store": "Lowe's",
        "rating": 4.4,
        "reviews": 1523,
        "distance_mi": 4.8,
        "thumbnail": "https://mobileimages.lowes.com/productimages/155650e6-7003-4ac2-832b-2b91dd7391a7/02456624.jpg",
        "url": "https://www.lowes.com",
    },
    {
        "name": "Red Devil Onetime Lightweight Spackling",
        "price": "$5.98",
        "store": "Walmart",
        "rating": 4.3,
        "reviews": 892,
        "distance_mi": 2.1,
        "thumbnail": "https://m.media-amazon.com/images/I/71gGVxzFGoL._AC_UF894,1000_QL80_.jpg",
        "url": "https://www.walmart.com",
    },
]

_OIL_PRODUCTS = [
    {
        "name": "Mobil 1 5W-30 Full Synthetic",
        "price": "$27.97",
        "store": "AutoZone",
        "rating": 4.8,
        "reviews": 5234,
        "distance_mi": 1.8,
        "thumbnail": "https://i5.walmartimages.com/asr/d34f23c4-cd29-4087-b80e-92ae631cb463.4ec0289c33eb4f4cc23ca41ec98254cd.jpeg",
        "url": "https://www.autozone.com",
    },
    {
        "name": "Valvoline Full Synthetic 5W-30",
        "price": "$25.99",
        "store": "O'Reilly Auto Parts",
        "rating": 4.7,
        "reviews": 3102,
        "distance_mi": 3.5,
        "thumbnail": "https://images-na.ssl-images-amazon.com/images/I/71g5tpmprCL.jpg",
        "url": "https://www.oreillyauto.com",
    },
    {
        "name": "Castrol Edge 5W-30",
        "price": "$26.47",
        "store": "Walmart",
        "rating": 4.6,
        "reviews": 4521,
        "distance_mi": 2.1,
        "thumbnail": "https://m.media-amazon.com/images/I/71gGVxzFGoL._AC_UF894,1000_QL80_.jpg",
        "url": "https://www.walmart.com",
    },
]

_GLASSES_PRODUCTS = [
    {
        "name": "Zeiss Lens Cleaning Kit",
        "price": "$8.99",
        "store": "Amazon",
        "rating": 4.7,
        "reviews": 12453,
        "distance_mi": None,
        "thumbnail": "https://m.media-amazon.com/images/I/41F7T9+oAwL._AC_UF894,1000_QL80_.jpg",
        "url": "https://www.amazon.com",
    },
    {
        "name": "Koala Eyeglass Cleaner Spray",
        "price": "$9.95",
        "store": "Target",
        "rating": 4.5,
        "reviews": 3201,
        "distance_mi": 5.1,
        "thumbnail": "https://m.media-amazon.com/images/I/81PuR5AvkKL._AC_UF1000,1000_QL80_.jpg",
        "url": "https://www.target.com",
    },
]

_KEYWORD_MAP = [
    (["drywall", "spackle", "spackling", "wall mud", "mud", "patch", "hole in wall", "joint compound"], _DRYWALL_PRODUCTS),
    (["oil", "motor oil", "engine oil", "synthetic", "automotive", "5w-30", "5w30", "quart"], _OIL_PRODUCTS),
    (["glasses", "lens", "eyeglass", "spectacle", "cleaning kit", "microfiber", "cleaner spray"], _GLASSES_PRODUCTS),
]


async def search_products(query: str) -> dict:
    """Search for nearby products matching the user's query.

    Returns mock shopping results styled like Google Shopping cards.
    Matches based on keywords in the query — no real API call.

    Args:
        query: What the user needs to buy (e.g. "wall spackle", "motor oil").

    Returns:
        dict with action="products", the original query, and a list of product dicts.
    """
    q = query.lower()
    products = []
    for keywords, items in _KEYWORD_MAP:
        if any(k in q for k in keywords):
            products = items
            break

    logger.info(
        "search_products: query=%r → %d result(s)",
        query, len(products),
    )
    return {"action": "products", "query": query, "products": products}
