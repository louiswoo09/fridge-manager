import logging

import cachecontrol
import google.auth.transport.requests
import requests
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.oauth2 import id_token

from app.config import settings

logger = logging.getLogger(__name__)

if not settings.firebase_project_id:
    raise RuntimeError("FIREBASE_PROJECT_ID가 .env에 설정되지 않았습니다")

_PROJECT_ID = settings.firebase_project_id
_ISSUER = f"https://securetoken.google.com/{_PROJECT_ID}"

# Google 공개키를 캐시해서 매 요청마다 내려받지 않게 함
_session = cachecontrol.CacheControl(requests.Session())
_google_request = google.auth.transport.requests.Request(session=_session)

_bearer = HTTPBearer(auto_error=False)


def get_current_uid(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    """요청의 Firebase ID 토큰을 확인하고 사용자 uid를 돌려줌"""
    if credentials is None:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다")

    try:
        claims = id_token.verify_firebase_token(
            credentials.credentials,
            _google_request,
            audience=_PROJECT_ID,        # 우리 프로젝트용 토큰인지
            clock_skew_in_seconds=10,    # 에뮬레이터 시계가 살짝 어긋나도 허용
        )
    except Exception as e:
        # 실패 이유만 로그로 (토큰 내용은 찍지 않음)
        logger.warning("ID 토큰 확인 실패: %s", e)
        raise HTTPException(status_code=401, detail="인증 정보가 유효하지 않습니다")

    if claims.get("iss") != _ISSUER or not claims.get("sub"):
        logger.warning("ID 토큰 발급자 불일치: %s", claims.get("iss"))
        raise HTTPException(status_code=401, detail="인증 정보가 유효하지 않습니다")

    return claims["sub"]   # Firebase uid