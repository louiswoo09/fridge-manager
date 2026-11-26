import asyncio
import json
import logging
import time
from collections import OrderedDict
from pathlib import Path
from urllib.parse import quote

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

SOURCE = "식품의약품안전처"
FOOD_BASE_URL = "https://openapi.foodsafetykorea.go.kr/api"

API_TIMEOUT = 5            # 내장 데이터가 없을 때만 쓰는 검색 API 대기 시간
RESULT_LIMIT = 100         # 검색 API로 받을 때 최대 개수
CACHE_TTL = 24 * 60 * 60   # 검색 API 결과 캐시 (내장 데이터가 없을 때만 사용)
CACHE_MAX = 300

REFRESH_INTERVAL = 7 * 24 * 60 * 60   # 일주일 지나면 내장 데이터 전체 갱신
DOWNLOAD_PAGE = 200               # 전체 받을 때 한 번에 받는 개수
DOWNLOAD_TIMEOUT = 30

SEARCH_FIELD = {
    "ingredient": "RCP_PARTS_DTLS",   # 재료명 검색
    "name": "RCP_NM",                 # 요리명 검색
}

# (검색 기준, 키워드) → (저장 시각, 결과)
_cache: OrderedDict[tuple[str, str], tuple[float, list[dict]]] = OrderedDict()


# ───────── 내장 레시피 (식약처 전체) ─────────

_LOCAL_PATH = Path(__file__).resolve().parent.parent / "data" / "recipes.json"


def _load_local() -> list[dict]:
    try:
        rows = json.loads(_LOCAL_PATH.read_text(encoding="utf-8"))
        rows = [r for r in rows if isinstance(r, dict)]
        for r in rows:
            r["source"] = SOURCE
        logger.info("내장 레시피 %d개 불러옴", len(rows))
        return rows
    except Exception:
        logger.warning("내장 레시피 파일을 불러오지 못했습니다: %s", _LOCAL_PATH)
        return []


def _file_time() -> float:
    """파일 수정 시각 = 마지막 갱신 시각. 파일이 없으면 0 → 첫 검색 때 바로 갱신"""
    try:
        return _LOCAL_PATH.stat().st_mtime
    except OSError:
        return 0.0


_LOCAL_RECIPES = _load_local()
_last_refresh = _file_time()
_refreshing = False
_refresh_task: asyncio.Task | None = None   # 갱신 작업이 중간에 정리되지 않게 붙잡아 둠


def _search_local(by: str, keyword: str) -> list[dict]:
    """해당 필드에 키워드가 포함된 레시피 전부 (고르는 건 라우터가 함)"""
    field = SEARCH_FIELD[by]
    return [r for r in _LOCAL_RECIPES if keyword in (r.get(field) or "")]


# ───────── 내장 데이터 자동 갱신 ─────────

async def _download_all() -> list[dict]:
    """식약처 레시피 전체를 DOWNLOAD_PAGE개씩 받음. 전체를 못 받으면 예외"""
    rows: list[dict] = []
    start, total = 1, None
    async with httpx.AsyncClient(timeout=DOWNLOAD_TIMEOUT, follow_redirects=True) as client:
        while total is None or start <= total:
            end = start + DOWNLOAD_PAGE - 1
            url = f"{FOOD_BASE_URL}/{settings.food_api_key}/COOKRCP01/json/{start}/{end}"
            res = await client.get(url)
            if res.status_code >= 400:
                raise RuntimeError(f"식약처 API 응답 오류 ({res.status_code})")
            body = res.json().get("COOKRCP01")
            if not isinstance(body, dict):
                raise RuntimeError("식약처 API 응답 형식 오류")
            total = int(body.get("total_count") or 0)
            page = body.get("row") or []
            if not page:
                break
            rows.extend(r for r in page if isinstance(r, dict))
            start = end + 1

    if not total or len(rows) != total:
        raise RuntimeError(f"전체를 받지 못함 ({len(rows)}/{total})")
    return rows


async def _refresh_local() -> None:
    """전체를 다시 받아 교체. 실패하면 기존 데이터 유지"""
    global _LOCAL_RECIPES, _last_refresh, _refreshing
    try:
        logger.info("내장 레시피 갱신 시작 (현재 %d개)", len(_LOCAL_RECIPES))
        rows = await _download_all()
        for r in rows:
            r["source"] = SOURCE
        _LOCAL_RECIPES = rows          # 한 번에 교체 → 검색 중에도 안전
        _last_refresh = time.time()

        # 파일도 갱신 (로컬 개발용. Cloud Run에선 재시작하면 배포된 파일로 돌아감)
        try:
            _LOCAL_PATH.parent.mkdir(parents=True, exist_ok=True)
            _LOCAL_PATH.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        except OSError:
            logger.warning("내장 레시피 파일 저장 실패 (메모리 데이터는 갱신됨)")

        logger.info("내장 레시피 갱신 완료: %d개", len(rows))
    except Exception as e:
        # 오류 메시지에 키가 든 URL이 섞이지 않도록 종류만 남김
        logger.warning("내장 레시피 갱신 실패(%s), 기존 데이터 유지", type(e).__name__)
        _last_refresh = time.time()    # 실패해도 다음 주기까지 재시도 안 함 (한도 보호)
    finally:
        _refreshing = False


def _maybe_refresh() -> None:
    """마지막 갱신 후 REFRESH_INTERVAL이 지났으면 뒤에서 전체 갱신 시작"""
    global _refreshing, _refresh_task
    if not settings.food_api_key or _refreshing:
        return
    if time.time() - _last_refresh < REFRESH_INTERVAL:
        return
    _refreshing = True
    _refresh_task = asyncio.create_task(_refresh_local())


# ───────── 식약처 검색 API (내장 데이터가 없을 때만) ─────────

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
    logger.info("식약처 검색 '%s': 전체 %s개 중 최대 %d개 요청", keyword, cook.get("total_count"), RESULT_LIMIT)

    rows = cook.get("row")
    if isinstance(rows, list) and rows:
        rows = [r for r in rows if isinstance(r, dict)]
        for r in rows:
            r["source"] = SOURCE
        return rows

    # 결과가 없을 때: '데이터 없음'이면 빈 목록, 그 외 코드는 진짜 오류
    result = cook.get("RESULT") or {}
    code = str(result.get("CODE", ""))
    if code in ("", "INFO-000", "INFO-200"):
        return []
    raise RuntimeError(f"식약처 API 오류: {code} {result.get('MSG', '')}")


# ───────── 검색 ─────────

async def search(by: str, keyword: str) -> tuple[list[dict], bool]:
    """(결과, 캐시에서 왔는지) 반환.
    내장 데이터가 있으면 거기서 검색, 없으면 식약처 검색 API 사용"""
    _maybe_refresh()   # 오래됐으면 뒤에서 전체 갱신 (검색은 기다리지 않음)
    kw = keyword.strip()

    if _LOCAL_RECIPES:
        return _search_local(by, kw), False

    # 내장 데이터가 없는 환경: 검색 API + 캐시
    key = (by, kw)
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < CACHE_TTL:
        _cache.move_to_end(key)
        return hit[1], True

    rows = await _fetch_from_food_api(by, kw)
    _cache[key] = (time.time(), rows)
    _cache.move_to_end(key)
    while len(_cache) > CACHE_MAX:
        _cache.popitem(last=False)
    return rows, False