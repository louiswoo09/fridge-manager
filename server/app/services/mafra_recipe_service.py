import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "mafra_recipes.json"
SOURCE = "농림수산식품교육문화정보원"


def _load() -> list[dict]:
    """서버 시작 시 한 번 읽음. 파일이 없으면(팀원 PC 등) 빈 목록"""
    if not DATA_PATH.exists():
        logger.warning("농정원 레시피 파일 없음: %s (식약처 레시피만 사용)", DATA_PATH)
        return []
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    for r in data:
        r["source"] = SOURCE
    logger.info("농정원 레시피 %d개 불러옴", len(data))
    return data


_RECIPES = _load()


def search(keyword: str, by: str) -> list[dict]:
    """식약처 검색과 같은 기준: 재료명 또는 요리명에 검색어가 들어 있으면 포함"""
    kw = keyword.strip()
    if not kw:
        return []
    if by == "name":
        return [r for r in _RECIPES if kw in r["RCP_NM"]]
    return [r for r in _RECIPES if any(kw in n for n in r["MAFRA_INGREDIENTS"])]