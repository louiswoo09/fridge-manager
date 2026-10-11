import logging
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.services import ai_service, gemini_service

from fastapi import Depends
from app.auth import get_current_uid

router = APIRouter(prefix="/ai", tags=["AI"], dependencies=[Depends(get_current_uid)])
logger = logging.getLogger(__name__)


class VariantRequest(BaseModel):
    recipe_name: str = Field(..., min_length=1, max_length=200)
    recipe_ingredients: str = Field("", max_length=5000)
    manuals: list[str] = Field(default_factory=list, max_length=20)
    owned: list[str] = Field(default_factory=list, max_length=300)
    cart: list[str] = Field(default_factory=list, max_length=300)
    imminent: list[str] = Field(default_factory=list, max_length=300)
    mode: Literal["fridge", "shopping"] = "fridge"
    imminent_only: bool = False


class AnalysisRequest(BaseModel):
    ingredients: list[str] = Field(..., min_length=1, max_length=300)
    imminent: list[str] = Field(default_factory=list, max_length=300)


def _to_http_error(e: Exception, what: str) -> HTTPException:
    if isinstance(e, gemini_service.GeminiTimeout):
        return HTTPException(status_code=504, detail="AI 응답 시간이 초과되었습니다")
    logger.exception("%s 실패", what)
    return HTTPException(status_code=502, detail="AI 응답 오류가 발생했습니다")


@router.post("/recipe-variant")
async def recipe_variant(req: VariantRequest):
    prompt = ai_service.build_variant_prompt(
        req.recipe_name, req.recipe_ingredients, req.manuals,
        req.owned, req.cart, req.imminent, req.mode, req.imminent_only,
    )
    try:
        text = await gemini_service.generate(prompt, json_mode=True, timeout=60)
    except Exception as e:
        raise _to_http_error(e, "레시피 변형")
    # 즐겨찾기 키가 이 텍스트로 만들어지므로 가공하지 않고 그대로 전달
    return {"text": text}


@router.post("/fridge-analysis")
async def fridge_analysis(req: AnalysisRequest):
    prompt = ai_service.build_analysis_prompt(req.ingredients, req.imminent)
    try:
        text = await gemini_service.generate(prompt, timeout=30)
    except Exception as e:
        raise _to_http_error(e, "냉장고 분석")
    if not text.strip():
        raise HTTPException(status_code=502, detail="AI 응답이 비어 있습니다")

    status, suggestion = ai_service.parse_analysis(text)
    return {"status": status, "suggestion": suggestion}