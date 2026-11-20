"""
식약처 레시피 전체를 받아 app/data/recipes.json에 저장 (로컬에서 한 번 실행)
사용법 (server 폴더, venv 활성화): python tools/dump_recipes.py
"""
import json
import os
import sys
from pathlib import Path

import httpx
from dotenv import load_dotenv

load_dotenv()
KEY = os.getenv("FOOD_API_KEY", "").strip()
if not KEY:
    sys.exit("FOOD_API_KEY가 .env에 없습니다")

BASE = "https://openapi.foodsafetykorea.go.kr/api/{key}/COOKRCP01/json/{start}/{end}"
OUT = Path(__file__).resolve().parent.parent / "app" / "data" / "recipes.json"

rows, start, total = [], 1, None
with httpx.Client(timeout=60, follow_redirects=True) as client:
    while total is None or start <= total:
        end = start + 999
        res = client.get(BASE.format(key=KEY, start=start, end=end))
        if res.status_code != 200:
            sys.exit(f"응답 오류 {res.status_code} ({start}~{end})")
        body = res.json().get("COOKRCP01", {})
        result = body.get("RESULT", {})
        if result.get("CODE") not in (None, "INFO-000"):
            sys.exit(f"API 오류: {result.get('MSG')}")
        total = int(body.get("total_count", 0))
        page = body.get("row", []) or []
        rows.extend(page)
        print(f"{start}~{end}: {len(page)}개 (누적 {len(rows)}/{total})")
        if not page:
            break
        start = end + 1

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
print(f"저장 완료: {OUT} ({len(rows)}개, {OUT.stat().st_size / 1024 / 1024:.1f}MB)")