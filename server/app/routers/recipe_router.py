import logging
import random
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query

from app.auth import get_current_uid
from app.services import mafra_recipe_service, recipe_service

router = APIRouter(
    prefix="/recipes", tags=["레시피"], dependencies=[Depends(get_current_uid)]
)
logger = logging.getLogger(__name__)

PER_SOURCE = 50     # 출처별 목표 개수 (식약처 50 + 농정원 50)
PER_KEYWORD = 100   # 검색어 하나당 최대 개수


def _balance(food: list[dict], mafra: list[dict]) -> list[dict]:
    """식약처·농정원을 반반씩 무작위로 고르고, 한쪽이 모자라면 다른 쪽으로 채워 번갈아 배치
    (같은 요리명이라도 출처가 다르면 둘 다 표시)"""
    food = list(food)
    mafra = list(mafra)
    random.shuffle(food)
    random.shuffle(mafra)

    take_food, take_mafra = food[:PER_SOURCE], mafra[:PER_SOURCE]

    # 한쪽이 50개가 안 되면 남은 쪽에서 채워 100개 맞추기
    short = PER_KEYWORD - len(take_food) - len(take_mafra)
    if short > 0:
        extra_food = food[PER_SOURCE:PER_SOURCE + short]
        take_food += extra_food
        take_mafra += mafra[PER_SOURCE:PER_SOURCE + short - len(extra_food)]

    # 식약처, 농정원 번갈아 배치
    result = []
    for i in range(max(len(take_food), len(take_mafra))):
        if i < len(take_food):
            result.append(take_food[i])
        if i < len(take_mafra):
            result.append(take_mafra[i])
    return result


@router.get("/search")
async def search_recipes(
    keyword: str = Query(..., min_length=1),
    by: Literal["ingredient", "name"] = "ingredient",
):
    # 농정원 레시피: 서버 안 파일에서 찾음 (실패할 일 없음)
    mafra_items = mafra_recipe_service.search(keyword, by)

    try:
        food_items, cached = await recipe_service.search(by, keyword)
    except Exception:
        # 식약처 URL에 키가 들어 있으므로 상세 내용은 서버 로그에만
        logger.exception("식약처 레시피 검색 실패 (by=%s, keyword=%s)", by, keyword)
        if not mafra_items:
            raise HTTPException(status_code=502, detail="레시피를 가져오지 못했습니다")
        food_items, cached = [], False   # 식약처가 안 돼도 농정원 결과는 보여줌

    items = _balance(food_items, mafra_items)

    n_mafra = sum(1 for r in items if r.get("source") == mafra_recipe_service.SOURCE)
    logger.info(
        "레시피 검색 %s '%s': 식약처 %d/%d개 + 농정원 %d/%d개 → %d개",
        by, keyword,
        len(items) - n_mafra, len(food_items),
        n_mafra, len(mafra_items),
        len(items),
    )
    return {"count": len(items), "cached": cached, "items": items}