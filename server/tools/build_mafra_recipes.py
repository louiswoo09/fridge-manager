"""
농정원 레시피(기본·재료·과정)를 합쳐서 식약처 레시피와 같은 형식의 JSON으로 저장
사용법 (server 폴더):  python tools/build_mafra_recipes.py
입력: tools/mafra_raw/basic.json, ingredients.json, steps.json (fetch_mafra_recipes.py로 받은 것)
출력: app/data/mafra_recipes.json
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "mafra_raw"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT.parent / "app" / "data" / "mafra_recipes.json"

MAX_STEPS = 20          # 식약처 형식은 MANUAL01 ~ MANUAL20
TYPE_ORDER = {"주재료": 0, "부재료": 1, "양념": 2}


def read_json(name: str) -> list[dict]:
    path = RAW / f"{name}.json"
    if not path.exists():
        raise SystemExit(f"{path} 가 없습니다. 먼저 fetch_mafra_recipes.py 를 실행하세요")
    return json.loads(path.read_text(encoding="utf-8"))


def clean(s) -> str:
    return " ".join(str(s or "").split())


# ── 기본정보
basic = {}
for row in read_json("basic"):
    name = clean(row.get("RECIPE_NM_KO"))
    if not name:
        continue
    basic[clean(row.get("RECIPE_ID"))] = {
        "name": name, "summary": clean(row.get("SUMRY")), "nation": clean(row.get("NATION_NM")),
        "type": clean(row.get("TY_NM")), "time": clean(row.get("COOKING_TIME")),
        "calorie": clean(row.get("CALORIE")), "qnt": clean(row.get("QNT")),
        "level": clean(row.get("LEVEL_NM")),
    }

# ── 과정정보
steps = defaultdict(list)
for row in read_json("steps"):
    desc = clean(row.get("COOKING_DC"))
    if not desc:
        continue
    try:
        no = int(row.get("COOKING_NO"))
    except (TypeError, ValueError):
        continue
    steps[clean(row.get("RECIPE_ID"))].append((no, desc, clean(row.get("STEP_TIP"))))

# ── 재료정보 (API JSON)
ingredients = defaultdict(list)
for row in read_json("ingredients"):
    name = clean(row.get("IRDNT_NM"))
    if not name:
        continue
    ingredients[clean(row.get("RECIPE_ID"))].append((
        TYPE_ORDER.get(clean(row.get("IRDNT_TY_NM")), 9),
        int(row.get("IRDNT_SN") or 0), name, clean(row.get("IRDNT_CPCTY")),
    ))

recipes, skipped = [], 0
for rid, b in basic.items():
    ings = sorted(ingredients.get(rid, []))
    sts = sorted(steps.get(rid, []))
    if not ings or not sts:
        skipped += 1          # 재료나 조리 과정이 없으면 상세 화면·AI 변형이 안 돼서 제외
        continue

    item = {
        "RCP_SEQ": f"mafra_{rid}",                 # 식약처 번호와 겹치지 않게
        "RCP_NM": b["name"],
        "RCP_PAT2": b["type"],                     # 요리 종류 (밥, 국 등)
        "INFO_ENG": b["calorie"].replace("Kcal", "").strip(),
        "RCP_PARTS_DTLS": ", ".join(f"{n} {c}".strip() for _, _, n, c in ings),
        "ATT_FILE_NO_MAIN": "",                    # 농정원 데이터엔 사진이 없음
        "ATT_FILE_NO_MK": "",
        # 농정원 전용 정보 (앱에서 쓰고 싶으면 사용)
        "MAFRA_SUMMARY": b["summary"], "MAFRA_NATION": b["nation"],
        "MAFRA_TIME": b["time"], "MAFRA_QNT": b["qnt"], "MAFRA_LEVEL": b["level"],
        "MAFRA_INGREDIENTS": [n for _, _, n, _ in ings],   # 서버 재료 검색용
    }
    for i, (_, desc, tip) in enumerate(sts[:MAX_STEPS], start=1):
        text = f"{i}. {desc}" + (f" (팁: {tip})" if tip else "")
        item[f"MANUAL{i:02d}"] = text
        item[f"MANUAL_IMG{i:02d}"] = ""
    recipes.append(item)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(recipes, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"레시피 {len(recipes)}개 저장 → {OUT}  (재료·과정 없어서 제외 {skipped}개)")