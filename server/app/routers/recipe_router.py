import logging
from typing import Literal

from fastapi import APIRouter, HTTPException, Query

from app.services import recipe_service

router = APIRouter(prefix="/recipes", tags=["레시피"])
logger = logging.getLogger(__name__)


@router.get("/search")
async def search_recipes(
    keyword: str = Query(..., min_length=1),
    by: Literal["ingredient", "name"] = "ingredient",
):
    try:
        items, cached = await recipe_service.search(by, keyword)
    except Exception:
        # 식약처 URL에 키가 들어 있으므로 상세 내용은 서버 로그에만
        logger.exception("식약처 레시피 검색 실패 (by=%s, keyword=%s)", by, keyword)
        raise HTTPException(status_code=502, detail="레시피를 가져오지 못했습니다")

    return {"count": len(items), "cached": cached, "items": items}