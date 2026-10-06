import asyncio
import time

import httpx

from app.config import settings

KAMIS_URL = "https://www.kamis.or.kr/service/price/xml.do"
CACHE_TTL = 30 * 60          # 30분
MIN_REFRESH_INTERVAL = 60    # 새로고침 연타 방지: 1분 안엔 캐시 재사용

_cache_items: list[dict] | None = None
_fetched_at: float = 0.0
_lock = asyncio.Lock()


async def _fetch_from_kamis() -> list[dict]:
    if not settings.kamis_cert_key or not settings.kamis_cert_id:
        raise RuntimeError("KAMIS 키가 .env에 설정되지 않았습니다")

    params = {
        "action": "dailySalesList",
        "p_cert_key": settings.kamis_cert_key,
        "p_cert_id": settings.kamis_cert_id,
        "p_returntype": "json",
    }
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        res = await client.get(KAMIS_URL, params=params)
    res.raise_for_status()

    price = res.json().get("price")
    if not isinstance(price, list):
        return []

    # 소매 + 가격 있는 것만
    return [
        item for item in price
        if str(item.get("product_cls_code", "")) == "01"
        and str(item.get("dpr1", "")).replace(",", "").strip() not in ("", "-")
    ]


async def get_daily_items(force_refresh: bool = False) -> tuple[list[dict], float, bool]:
    """(items, fetched_at, from_cache) 반환"""
    global _cache_items, _fetched_at

    age = time.time() - _fetched_at
    if _cache_items is not None:
        if not force_refresh and age < CACHE_TTL:
            return _cache_items, _fetched_at, True
        if force_refresh and age < MIN_REFRESH_INTERVAL:
            return _cache_items, _fetched_at, True

    # 동시에 여러 요청이 와도 KAMIS는 한 번만 호출 (기존 in-flight 공유와 같은 역할)
    async with _lock:
        if _cache_items is not None and time.time() - _fetched_at < MIN_REFRESH_INTERVAL:
            return _cache_items, _fetched_at, True
        try:
            items = await _fetch_from_kamis()
        except Exception:
            # KAMIS가 죽었어도 예전 캐시가 있으면 그걸로 버팀
            if _cache_items is not None:
                return _cache_items, _fetched_at, True
            raise
        _cache_items = items
        _fetched_at = time.time()
        return items, _fetched_at, False