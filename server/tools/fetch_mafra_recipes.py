"""
농정원 레시피 기본·재료·과정정보 전체를 받아서 tools/mafra_raw/ 에 저장
사용법 (server 폴더, venv 활성화):  python tools/fetch_mafra_recipes.py
"""
import json
import os
import sys
import time
from pathlib import Path

import httpx
from dotenv import load_dotenv

load_dotenv()
KEY = os.getenv("MAFRA_API_KEY", "").strip()
BASE = os.getenv("MAFRA_BASE_URL", "").strip().rstrip("/")
if not KEY or not BASE:
    sys.exit(".env에 MAFRA_API_KEY, MAFRA_BASE_URL을 넣어주세요")

GRIDS = {
    "basic": "Grid_20150827000000000226_1",        # 기본정보
    "ingredients": "Grid_20150827000000000227_1",  # 재료정보
    "steps": "Grid_20150827000000000228_1",        # 과정정보
}
PAGE = 1000
OUT_DIR = Path(__file__).parent / "mafra_raw"
OUT_DIR.mkdir(exist_ok=True)


def fetch_page(grid: str, start: int, end: int) -> dict:
    url = f"{BASE}/{KEY}/json/{grid}/{start}/{end}"
    res = httpx.get(url, timeout=30)
    if res.status_code != 200:
        # 주소에 키가 있어서 주소는 출력하지 않음
        raise RuntimeError(f"{grid} {start}~{end}: HTTP {res.status_code}")
    data = res.json()[grid]
    code = data.get("result", {}).get("code")
    if code != "INFO-000":
        raise RuntimeError(f"{grid} {start}~{end}: {data.get('result')}")
    return data


for name, grid in GRIDS.items():
    first = fetch_page(grid, 1, PAGE)
    total = int(first["totalCnt"])
    rows = list(first.get("row", []))
    print(f"{name}: 전체 {total}줄")

    start = PAGE + 1
    while start <= total:
        time.sleep(0.5)   # 서버 부담 줄이기
        page = fetch_page(grid, start, min(start + PAGE - 1, total))
        rows.extend(page.get("row", []))
        print(f"  {len(rows)}/{total}")
        start += PAGE

    path = OUT_DIR / f"{name}.json"
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  → {path} 저장 ({len(rows)}줄)")