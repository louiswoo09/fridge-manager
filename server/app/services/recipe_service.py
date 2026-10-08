import time
from collections import OrderedDict
from urllib.parse import quote

import httpx

from app.config import settings

FOOD_BASE_URL = "https://openapi.foodsafetykorea.go.kr/api"
CACHE_TTL = 24 * 60 * 60   # 레시피 데이터는 거의 안 바뀌어서 하루
CACHE_MAX = 300            # 검색어 300개까지만 기억 (오래된 것부터 삭제)

SEARCH_FIELD = {
    "ingredient": "RCP_PARTS_DTLS",   # 재료명 검색
    "name": "RCP_NM",                 # 요리명 검색
}

# (검색 기준, 키워드) → (저장 시각, 결과)
_cache: OrderedDict[tuple[str, str], tuple[float, list[dict]]] = OrderedDict()


async def _fetch_from_food_api(by: str, keyword: str) -> list[dict]:
    if not settings.food_api_key:
        raise RuntimeError("FOOD_API_KEY가 .env에 설정되지 않았습니다")

    url = (
        f"{FOOD_BASE_URL}/{settings.food_api_key}/COOKRCP01/json/1/20/"
        f"{SEARCH_FIELD[by]}={quote(keyword)}"
    )
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        res = await client.get(url)
    res.raise_for_status()

    cook = res.json().get("COOKRCP01")
    if not isinstance(cook, dict):
        return []

    rows = cook.get("row")
    if isinstance(rows, list) and rows:
        return [r for r in rows if isinstance(r, dict)]

    # 결과가 없을 때: '데이터 없음'이면 빈 목록, 그 외 코드는 진짜 오류
    result = cook.get("RESULT") or {}
    code = str(result.get("CODE", ""))
    if code in ("", "INFO-000", "INFO-200"):
        return []
    raise RuntimeError(f"식약처 API 오류: {code} {result.get('MSG', '')}")


async def search(by: str, keyword: str) -> tuple[list[dict], bool]:
    """(결과, 캐시에서 왔는지) 반환"""
    key = (by, keyword.strip())
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < CACHE_TTL:
        _cache.move_to_end(key)
        return hit[1], True

    rows = await _fetch_from_food_api(by, key[1])
    _cache[key] = (time.time(), rows)
    _cache.move_to_end(key)
    while len(_cache) > CACHE_MAX:
        _cache.popitem(last=False)
    return rows, False