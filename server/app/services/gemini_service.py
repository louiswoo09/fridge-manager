import asyncio
import logging

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


async def generate(prompt: str, *, json_mode: bool = False, timeout: float = 30) -> str:
    if not settings.gemini_api_key:
        raise GeminiError(None, "GEMINI_API_KEY가 .env에 설정되지 않았습니다")

    body: dict = {"contents": [{"parts": [{"text": prompt}]}]}
    if json_mode:
        body["generationConfig"] = {"responseMimeType": "application/json"}

    url = GEMINI_URL.format(model=settings.gemini_model)
    # 키를 URL(?key=) 대신 헤더로 → 에러 로그에 키가 찍히지 않음
    headers = {"x-goog-api-key": settings.gemini_api_key}

    last_status: int | None = None
    async with httpx.AsyncClient(timeout=timeout) as client:
        for attempt in range(len(RETRY_DELAYS) + 1):
            try:
                res = await client.post(url, json=body, headers=headers)
            except httpx.TimeoutException as e:
                raise GeminiTimeout() from e

            if res.status_code == 200:
                return _extract_text(res.json())

            last_status = res.status_code
            logger.warning(
                "Gemini 실패 (status=%s, attempt=%s): %s",
                res.status_code, attempt + 1, res.text[:300],
            )
            retryable = res.status_code >= 500 or res.status_code == 429
            if retryable and attempt < len(RETRY_DELAYS):
                await asyncio.sleep(RETRY_DELAYS[attempt])
                continue
            break

    raise GeminiError(last_status, f"Gemini 응답 오류 ({last_status})")