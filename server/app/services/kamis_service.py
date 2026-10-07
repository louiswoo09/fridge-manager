import asyncio
import logging
import time

from datetime import date

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

KAMIS_URL = "https://www.kamis.or.kr/service/price/xml.do"

DAILY_TTL = 30 * 60           # 일별 목록 30분
MIN_REFRESH_INTERVAL = 60     # 새로고침 연타 방지
TREND_TTL = 60 * 60           # 가격 추이 1시간
CODE_TTL = 24 * 60 * 60       # 품목 코드표 하루

TREND_KEYS = {
    "daily": ["d40", "d30", "d20", "d10", "d0"],
    "monthly": [f"m{i}" for i in range(1, 13)],
    "yearly": ["avg_data"],
}


# ───────── 공통 ─────────

async def _kamis_get(params: dict) -> dict:
    if not settings.kamis_cert_key or not settings.kamis_cert_id:
        raise RuntimeError("KAMIS 키가 .env에 설정되지 않았습니다")
    full = {
        **params,
        "p_cert_key": settings.kamis_cert_key,
        "p_cert_id": settings.kamis_cert_id,
        "p_returntype": "json",
    }
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        res = await client.get(KAMIS_URL, params=full)
    res.raise_for_status()
    return res.json()


def _parse_price(value) -> float | None:
    if value is None or isinstance(value, (list, dict)):
        return None
    try:
        price = float(str(value).replace(",", ""))
    except ValueError:
        return None
    return price if price > 0 else None


# ───────── 일별 가격 목록 (가격 동향 탭) ─────────

_daily_items: list[dict] | None = None
_daily_fetched_at: float = 0.0
_daily_lock = asyncio.Lock()


async def _fetch_daily_list() -> list[dict]:
    data = await _kamis_get({"action": "dailySalesList"})
    price = data.get("price")
    if not isinstance(price, list):
        return []
    return [
        item for item in price
        if isinstance(item, dict)
        and str(item.get("product_cls_code", "")) == "01"
        and _parse_price(item.get("dpr1")) is not None
    ]


async def get_daily_items(force_refresh: bool = False) -> tuple[list[dict], float, bool]:
    """(items, fetched_at, from_cache) 반환"""
    global _daily_items, _daily_fetched_at

    age = time.time() - _daily_fetched_at
    if _daily_items is not None:
        if not force_refresh and age < DAILY_TTL:
            return _daily_items, _daily_fetched_at, True
        if force_refresh and age < MIN_REFRESH_INTERVAL:
            return _daily_items, _daily_fetched_at, True

    async with _daily_lock:
        if _daily_items is not None and time.time() - _daily_fetched_at < MIN_REFRESH_INTERVAL:
            return _daily_items, _daily_fetched_at, True
        try:
            items = await _fetch_daily_list()
        except Exception:
            if _daily_items is not None:
                return _daily_items, _daily_fetched_at, True
            raise
        _daily_items = items
        _daily_fetched_at = time.time()
        return items, _daily_fetched_at, False


# ───────── 품목·품종 코드표 ─────────

# category_code → (저장 시각, {품목명: [{itemcode, kindcode, kindname}, ...]})
_item_codes: dict[str, tuple[float, dict[str, list[dict]]]] = {}


async def _get_item_kind(category_code: str, item_name: str) -> tuple[str | None, str | None]:
    """'포도/샤인머스켓' → ('414', '12') 처럼 품목 코드와 품종 코드를 찾음"""
    cached = _item_codes.get(category_code)
    if cached is None or time.time() - cached[0] > CODE_TTL:
        data = await _kamis_get({
            "action": "productInfo",
            "p_itemcategorycode": category_code,
        })
        mapping: dict[str, list[dict]] = {}
        info = data.get("info")
        if isinstance(info, list):
            for entry in info:
                if not isinstance(entry, dict):
                    continue
                name = entry.get("itemname")
                code = entry.get("itemcode")
                kind = entry.get("kindcode")
                if not isinstance(name, str) or not isinstance(code, str):
                    continue
                mapping.setdefault(name, []).append({
                    "itemcode": code,
                    "kindcode": kind if isinstance(kind, str) else "",
                    "kindname": entry.get("kindname") if isinstance(entry.get("kindname"), str) else "",
                })
        cached = (time.time(), mapping)
        _item_codes[category_code] = cached

    parts = item_name.split("/", 1)
    name = parts[0].strip()
    kind_part = parts[1].strip() if len(parts) > 1 else ""

    kinds = cached[1].get(name)
    if not kinds:
        return None, None

    item_code = kinds[0]["itemcode"]

    # 품종이 하나뿐이면 그걸로
    if len(kinds) == 1:
        return item_code, kinds[0]["kindcode"] or None

    if kind_part:
        # 1순위: 품종 이름이 정확히 같음
        for k in kinds:
            if k["kindname"] == kind_part:
                return item_code, k["kindcode"] or None
        # 2순위: 한쪽이 다른 쪽을 포함 (예: '풋고추(녹광 등)' ↔ '녹광')
        for k in kinds:
            if k["kindname"] and (k["kindname"] in kind_part or kind_part in k["kindname"]):
                return item_code, k["kindcode"] or None

    # 품종을 못 찾음 → 기존처럼 품종 없이 요청 (섞일 수 있으니 로그 남김)
    logger.warning("품종 매칭 실패: %s (후보: %s)", item_name, [k["kindname"] for k in kinds])
    return item_code, None


# ───────── 가격 추이 (상세 화면 그래프) ─────────

_trend_cache: dict[tuple, tuple[float, list[dict]]] = {}


def _retail_items(data: dict) -> list[dict]:
    """월별/연별 응답에서 소매(productclscode=01) 데이터만"""
    price = data.get("price")
    if price is None:
        return []
    entries = price if isinstance(price, list) else [price]
    for entry in entries:
        if isinstance(entry, dict) and str(entry.get("productclscode", "")) == "01":
            items = entry.get("item")
            if isinstance(items, dict):
                items = [items]
            if isinstance(items, list):
                return [i for i in items if isinstance(i, dict)]
    return []


async def _fetch_trend(mode: str, product_no: str, category_code: str, item_name: str) -> list[dict]:
    today = date.today()

    # 축산물은 KAMIS 코드표에 소매 품목이 없고 productno도 실제 번호가 아님
    # → 다른 상품 데이터가 섞이므로 가격 추이를 제공하지 않음
    if category_code == "500":
        return []

    if mode == "daily":
        if not product_no:
            return []
        data = await _kamis_get({
            "action": "recentlyPriceTrendList",
            "p_productno": product_no,
            "p_regday": today.isoformat(),
        })
        price = data.get("price")
        return [p for p in price if isinstance(p, dict)] if isinstance(price, list) else []

    if not category_code or not item_name:
        return []

    item_code, kind_code = await _get_item_kind(category_code, item_name)
    if not item_code:
        return []

    common = {
        "p_yyyy": str(today.year),
        "p_itemcategorycode": category_code,
        "p_itemcode": item_code,
        "p_graderank": "1",
        "p_countycode": "1101",
        "p_convert_kg_yn": "N",
    }
    if kind_code:
        common["p_kindcode"] = kind_code

    if mode == "monthly":
        data = await _kamis_get({"action": "monthlySalesList", "p_period": "4", **common})
        return _retail_items(data)

    # yearly: 평년 빼고 연도순
    data = await _kamis_get({"action": "yearlySalesList", **common})
    items = [i for i in _retail_items(data) if str(i.get("div", "")) != "평년"]
    items.sort(key=lambda i: int(i["div"]) if str(i.get("div", "")).isdigit() else 0)
    return items


def _remove_outliers(rows: list[dict], keys: list[str], ref_price: float | None) -> list[dict]:
    """현재가 기준 1/10 ~ 10배를 벗어나는 값은 '-' 로 (앱 그래프에서 자동으로 건너뜀)"""
    cleaned = [dict(row) for row in rows]   # 캐시 원본은 건드리지 않음
    if not ref_price or ref_price <= 0:
        return cleaned
    low, high = ref_price / 10, ref_price * 10
    for row in cleaned:
        for key in keys:
            price = _parse_price(row.get(key))
            if price is not None and not (low <= price <= high):
                row[key] = "-"
    return cleaned


async def get_trend(
    mode: str,
    product_no: str,
    category_code: str,
    item_name: str,
    ref_price: float | None,
) -> list[dict]:
    key = (mode, product_no, category_code, item_name, date.today().isoformat())
    hit = _trend_cache.get(key)
    if hit and time.time() - hit[0] < TREND_TTL:
        rows = hit[1]
    else:
        rows = await _fetch_trend(mode, product_no, category_code, item_name)
        _trend_cache[key] = (time.time(), rows)

    return _remove_outliers(rows, TREND_KEYS[mode], ref_price)