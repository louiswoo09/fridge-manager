import asyncio
import logging
import time

import httpx

from app.config import settings

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
RETRY_DELAYS = [2, 3]   # 5xx / 429 오류 일 때 2초 쉬고 한번, 3초 쉬고 한번 더 시도(총 3번 시도)

logger = logging.getLogger(__name__)


class GeminiTimeout(Exception):
    pass


class GeminiError(Exception):
    def __init__(self, status: int | None, message: str):
        super().__init__(message)
        self.status = status


def _extract_text(data: dict) -> str:
    candidates = data.get("candidates") or []
    if not candidates:
        return ""
    parts = (candidates[0].get("content") or {}).get("parts") or []
    if not parts:
        return ""
    return str(parts[0].get("text") or "")


async def _generate_with_model(
    model: str,
    prompt: str,
    *,
    json_mode: bool = False,
    timeout: float = 30,
    image: tuple[str, str] | None = None,
    thinking_level: str | None = None,
) -> str:
    """지정한 모델 하나로 호출 (5xx/429면 RETRY_DELAYS만큼 재시도)"""
    if not settings.gemini_api_key:
        raise GeminiError(None, "GEMINI_API_KEY가 .env에 설정되지 않았습니다")

    parts: list[dict] = []
    if image:
        mime_type, data = image
        parts.append({"inline_data": {"mime_type": mime_type, "data": data}})
    parts.append({"text": prompt})

    body: dict = {"contents": [{"parts": parts}]}
    config: dict = {}
    if json_mode:
        config["responseMimeType"] = "application/json"
    # (c) thinkingLevel은 Gemini 3 계열만 지원 → 다른 계열이면 빼고 보냄 (400 에러 방지)
    if thinking_level and model.startswith("gemini-3"):
        config["thinkingConfig"] = {"thinkingLevel": thinking_level}
    if config:
        body["generationConfig"] = config

    url = GEMINI_URL.format(model=model)
    # 키를 URL(?key=) 대신 헤더로 → 에러 로그에 키가 찍히지 않음
    headers = {"x-goog-api-key": settings.gemini_api_key}

    last_status: int | None = None
    async with httpx.AsyncClient(timeout=timeout) as client:
        for attempt in range(len(RETRY_DELAYS) + 1):
            start = time.perf_counter()
            try:
                res = await client.post(url, json=body, headers=headers)
            except httpx.TimeoutException as e:
                raise GeminiTimeout() from e
            elapsed = time.perf_counter() - start

            if res.status_code == 200:
                data = res.json()
                usage = data.get("usageMetadata") or {}
                logger.info(
                    "Gemini 응답 %.1f초 (model=%s, 입력 %s, 생각 %s, 출력 %s 토큰)",
                    elapsed,
                    model,
                    usage.get("promptTokenCount"),
                    usage.get("thoughtsTokenCount", 0),
                    usage.get("candidatesTokenCount"),
                )
                return _extract_text(data)

            last_status = res.status_code
            logger.warning(
                "Gemini 실패 (model=%s, status=%s, attempt=%s): %s",
                model, res.status_code, attempt + 1, res.text[:300],
            )
            retryable = res.status_code >= 500 or res.status_code == 429
            if retryable and attempt < len(RETRY_DELAYS):
                await asyncio.sleep(RETRY_DELAYS[attempt])
                continue
            break

    raise GeminiError(last_status, f"Gemini 응답 오류 ({last_status})")


# (d) 라우터들이 부르는 함수: 기본 모델 → 혼잡하면 예비 모델
async def generate(
    prompt: str,
    *,
    json_mode: bool = False,
    timeout: float = 30,
    image: tuple[str, str] | None = None,
    thinking_level: str | None = None,
) -> str:
    """기본 모델로 시도하고, 혼잡(503)·사용량 초과(429)면 예비 모델로 한 번 더"""
    kwargs = dict(
        json_mode=json_mode,
        timeout=timeout,
        image=image,
        thinking_level=thinking_level,
    )
    try:
        return await _generate_with_model(settings.gemini_model, prompt, **kwargs)
    except GeminiError as e:
        fallback = settings.gemini_fallback_model
        if e.status in (429, 503) and fallback and fallback != settings.gemini_model:
            logger.warning(
                "Gemini 혼잡 (status=%s) → 예비 모델 %s로 재시도", e.status, fallback
            )
            return await _generate_with_model(fallback, prompt, **kwargs)
        raise