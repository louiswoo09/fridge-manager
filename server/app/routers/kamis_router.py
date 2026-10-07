import logging

from datetime import datetime

from fastapi import APIRouter, HTTPException

from app.services import kamis_service

from typing import Literal


router = APIRouter(prefix="/kamis", tags=["KAMIS"])
logger = logging.getLogger(__name__)


@router.get("/daily")
async def get_daily(force_refresh: bool = False):
    try:
        items, fetched_at, cached = await kamis_service.get_daily_items(force_refresh)
    except Exception:
        # 상세 원인은 서버 터미널에만 (URL에 키가 포함될 수 있음)
        logger.exception("KAMIS 일별 가격 조회 실패")
        raise HTTPException(status_code=502, detail="가격 정보를 가져오지 못했습니다")

    return {
        "count": len(items),
        "cached": cached,
        "fetched_at": datetime.fromtimestamp(fetched_at).isoformat(),
        "items": items,
    }

@router.get("/trend")
async def get_trend(
    mode: Literal["daily", "monthly", "yearly"],
    product_no: str = "",
    category_code: str = "",
    item_name: str = "",
    ref_price: float | None = None,
):
    try:
        items = await kamis_service.get_trend(
            mode, product_no, category_code, item_name, ref_price
        )
    except Exception:
        logger.exception("KAMIS 가격 추이 조회 실패 (mode=%s, item=%s)", mode, item_name)
        raise HTTPException(status_code=502, detail="가격 추이를 가져오지 못했습니다")

    return {"mode": mode, "count": len(items), "items": items}