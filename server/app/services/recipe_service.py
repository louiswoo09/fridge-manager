import json
import logging
import time
from collections import OrderedDict
from pathlib import Path
from urllib.parse import quote

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

FOOD_BASE_URL = "https://openapi.foodsafetykorea.go.kr/api"
CACHE_TTL = 24 * 60 * 60   # 레시피 데이터는 거의 안 바뀌어서 하루
CACHE_MAX = 300            # 검색어 300개까지만 기억 (오래된 것부터 삭제)
API_TIMEOUT = 5            # 실패해도 내장 데이터가 있으니 짧게
RESULT_LIMIT = 20          # API가 주는 개수와 맞춤

SEARCH_FIELD = {
    "ingredient": "RCP_PARTS_DTLS",   # 재료명 검색
    "name": "RCP_NM",                 # 요리명 검색
}

# (검색 기준, 키워드) → (저장 시각, 결과)
_cache: OrderedDict[tuple[str, str], tuple[float, list[dict]]] = OrderedDict()


# ───────── 내장 레시피 (식약처 API 장애 대비) ─────────

_LOCAL_PATH = Path(__file__).resolve().parent.parent / "data" / "recipes.json"


def _load_local() -> list[dict]:
    try:
        rows = json.loads(_LOCAL_PATH.read_text(encoding="utf-8"))
        logger.info("내장 레시피 %d개 불러옴", len(rows))
        return [r for r in rows if isinstance(r, dict)]
    except Exception:
        logger.warning("내장 레시피 파일을 불러오지 못했습니다: %s", _LOCAL_PATH)
        return []


_LOCAL_RECIPES = _load_local()


def _search_local(by: str, keyword: str) -> list[dict]:
    """식약처 API와 같은 기준: 해당 필드에 키워드가 포함된 레시피"""
    field = SEARCH_FIELD[by]
    return [r for r in _LOCAL_RECIPES if keyword in (r.get(field) or "")][:RESULT_LIMIT]


# ───────── 식약처 API ─────────

async def _fetch_from_food_api(by: str, keyword: str) -> list[dict]:
    if not settings.food_api_key:
        raise RuntimeError("FOOD_API_KEY가 .env에 설정되지 않았습니다")

    url = (
        f"{FOOD_BASE_URL}/{settings.food_api_key}/COOKRCP01/json/1/{RESULT_LIMIT}/"
        f"{SEARCH_FIELD[by]}={quote(keyword)}"
    )
    async with httpx.AsyncClient(timeout=API_TIMEOUT, follow_redirects=True) as client:
        res = await client.get(url)
    if res.status_code >= 400:
        raise RuntimeError(f"식약처 API 응답 오류 ({res.status_code})")

    cook = res.json().get("COOKRCP01")
    if not isinstance(cook, dict):
        raise RuntimeError("식약처 API 응답 형식 오류")

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
    """(결과, 캐시에서 왔는지) 반환. 식약처 API 실패 시 내장 레시피로 검색"""
    key = (by, keyword.strip())
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < CACHE_TTL:
        _cache.move_to_end(key)
        return hit[1], True

    try:
        rows = await _fetch_from_food_api(by, key[1])
    except Exception as e:
        # 오류 메시지에 키가 든 URL이 섞이지 않도록 종류만 남김
        logger.warning("식약처 API 실패(%s) → 내장 레시피로 검색: %s", type(e).__name__, key[1])
        if not _LOCAL_RECIPES:
            raise
        # 내장 결과는 캐시하지 않음 → API가 살아나면 다음 검색부터 최신
        return _search_local(by, key[1]), False

    _cache[key] = (time.time(), rows)
    _cache.move_to_end(key)
    while len(_cache) > CACHE_MAX:
        _cache.popitem(last=False)
    return rows, False