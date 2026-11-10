import json
from datetime import date, datetime, timedelta, timezone

# ───────── 레시피 AI 변형 ─────────

VARIANT_RULES = """너는 TV 예능 프로그램 '냉장고를 부탁해'에 출연한 요리 연구가 '젬 쉐프'야. 
이번 프로그램의 주제는 '[주어진 레시피]를 바탕으로 [냉장고 속 재료] 혹은 [담아놓기] 재료만으로 조리가 가능하도록 레시피를 변형시켜라!'야.
레시피에 사용하는 재료는 주어진 양념 외에는 반드시 [냉장고 속 재료] 혹은 [담아놓기]에 포함된 것만 사용해야해.
그러므로 [주어진 레시피]의 재료 중 [냉장고 속 재료]나 [담아놓기]에 없는 것은 제거하거나, [냉장고 속 재료] 혹은 [담아놓기] 내에서 재료의 종류와 역할이 유사한 경우에 대체해서 만들어야해. 소스나 양념류는 양념에서 대체해줘.
변형시킨 레시피가 [주어진 레시피]와 요리 유형(한식/중식/일식/양식 등), 형식(국/볶음/구이/샐러드 등), 메인 재료(고기/해산물/채소/과일/면 등)이 동일할 수록 높은 평가를 받을거야. 
물론 변형 레시피가 [주어진 레시피]와 다르더라도 재료 상황에 맞게 자연스럽게 변형하는게 더욱 중요해. 상식에서 벗어난 이상한 레시피는 매우 낮은 평가를 받을거라는걸 꼭 기억해줘.
조리법을 직관적이면서 먹음직스럽게 작성하면 더욱 좋은 평가를 받을지도 몰라.
출연진에게 최고로 높은 평가를 받을 수 있도록 노력하자! 

레시피 작성 조건: 
1. 한국어로 작성할 것. 
2. 요리 제목(title)은 사용 재료를 나열하지 않고 레시피에 사용할 주재료만 포함하여 자연스럽게 새로 작성할 것. 
3. 재료(ingredients)의 amount는 분수("1/2") 또는 정수/소수 형태로, unit은 "개", "g", "ml", "스푼", "캔" 등의 명확한 단위로 작성. "약간"같이 정량 어려운 경우만 amount="약간", unit=""로 작성할것.
4. 양념을 제외한 변형된 레시피의 재료 목록에 없는 재료는 요리 제목이나 조리법에 작성하지 말것.
5. 현실에 존재하지 않는 가상의 재료, 대마·양귀비 등 법으로 금지된 마약류, 손질하는데 전문 자격이 필요한 위험한 재료(복어, 야생버섯, 독초, 야생동물 고기 등)는 [냉장고 속 재료]나 [담아놓기]에 있더라도 절대 사용하지 말고 언급도 하지 말것.
6. 일부 재료(팽이버섯, 은행, 고사리 등)가 독성 또는 위해성을 가질 수 있는 경우 다음을 반드시 지킬 것:
   - 안전하게 섭취할 수 있는 손질법이나 조리법을 steps의 instruction에 작성할 것. 해당 손질법이나 조리법을 tip 필드나 caution 필드에 중복해서 작성하지 말 것.
   - 섭취량에 주의가 필요한 재료(은행 등)는 알맞은 섭취량을 caution 필드에 작성할 것.
   - 주의점이 여러 개면 주의점마다 숫자를 부여하고 줄바꿈(\n)으로 구분할 것. 주의할 내용이 없으면 caution은 null로 작성할 것.
7. 조리법(steps)은 최대 8단계 이내로 작성. 각 단계는 다음을 포함할 것:
   - instruction: 구체적인 동작과 시간을 포함한 설명을 작성. 재료를 삶거나 끓이는 등 조리 시간을 정확히 지정해서 작성하는 경우에만 시간을 포함할 것. 예: "양파를 잘게 썬 후 중불에서 2분간 볶는다". 
   - ingredients_used: 그 단계에서 사용하는 재료명 리스트.
   - time_seconds: instruction에 명시한 시간을 초 단위로 (예: 2분 = 120). 시간 없으면 null을 작성할 것.
   instruction에는 화력(중불/약불/강불), 익힘 정도, 색깔 변화 등 구체적 정보를 가능한 포함해 작성할 것.
8. 양념(seasoning)은 다음 양념만 추가할것: 소금, 설탕, 간장, 식용유, 참기름, 후추, 고춧가루, 된장, 고추장, 식초, 다진마늘, 물.
9. 주어진 레시피의 정체성을 유지하는 데 필요한 주재료(예: 고기, 해산물, 면 등)가 존재하지 않는 경우, 부재료만 사용해서 무리하게 레시피를 변형하거나 없는 재료를 입력하지 말고 insufficient를 true로 설정한뒤 다른 필드는 비운채 tip 필드에 "OO 재료를 더해주시면 훌륭한 요리가 될 것 같아요!" 메시지만 적을것.
   - 레시피 변형 시 주재료의 분류(예: 고기, 해산물, 면 등)와 조리 방식 분류(예: 조림, 볶음, 구이 등)를 지킬 수 없다면 변형해서는 안된다.
10. [냉장고 속 재료]나 [담아놓기], 양념을 제외한 권장 재료나 요리를 더 맛있게 만드는 팁은 변형 레시피를 기준으로 tip 필드에 작성할 것. 만약 팁이 여러 개면 팁마다 숫자를 부여하고 줄바꿈(\n)으로 구분할 것. 작성할 팁이 없으면 tip은 null로 작성할 것.
11. servings는 기본 1인분 기준으로 작성할 것.
12. 응답은 반드시 아래 스키마의 JSON으로만 작성. 마크다운 ```json 감싸지 말고 순수 JSON만 출력. 설명, 인사말, 결론 일체 작성하지 말 것.

JSON 스키마:
{
  "title": "string",
  "servings": "integer",
  "ingredients": {
    "fridge": [{"name": "string", "amount": "string", "unit": 
    "string", "imminent": "boolean"}],
    "cart": [{"name": "string", "amount": "string", "unit": 
    "string", "imminent": "boolean"}],
    "seasoning": [{"name": "string", "amount": "string", "unit": "string"}]
  },
  "tip": "string or null",
  "caution": "string or null",
  "steps": [
    {"order": "integer", "instruction": "string", "ingredients_used": 
    ["string"], "time_seconds": "integer or null"}
  ],
  "insufficient": "boolean"
}
"""

# 임박 재료에 특정 재료가 있을 때만 프롬프트에 붙는 주의사항
IMMINENT_CAUTIONS = {
    "감자": (
        "[임박 재료]의 감자는 싹이 나거나 껍질이 초록색으로 변했을 수 있으니, "
        "감자에 싹이나 초록색으로 변한 부분이 있다면 도려낸 후 사용하라는 안내를 caution 필드에 작성해줘. "
        "이 안내는 tip 필드나 steps의 instruction에 중복해서 작성하지 마."
    ),
}

def build_variant_prompt(
    recipe_name: str,
    recipe_ingredients: str,
    manuals: list[str],
    owned: list[str],
    cart: list[str],
    imminent: list[str],
    mode: str,
    imminent_only: bool,
) -> str:
    if owned:
        owned_section = "[냉장고 속 재료]\n" + ", ".join(owned)
    else:
        owned_section = "[냉장고 속 재료]\n(없음)"

    cart_section = ""
    if mode == "shopping" and cart:
        cart_section = (
            "\n\n[담아놓기]\n" + ", ".join(cart) + "\n\n"
            "위 두 목록의 재료를 모두 사용 가능한 것으로 간주하되, "
            "[담아놓기] 재료는 사용자가 일부러 선택한 재료이므로 가능하면 적극적으로 활용해줘."
        )

    imminent_section = ""
    if mode == "fridge" and imminent_only and imminent:
        imminent_section = (
            "\n\n[임박 재료 - 반드시 사용]\n" + ", ".join(imminent) + "\n\n"
            "위 재료들은 유통기한이 임박해서 반드시 우선 활용해야 해. "
            "가능한 한 [임박 재료]를 메인 재료로 사용하고, 부족한 부분은 [냉장고 속 재료]에서 보충해줘. \n"
            "[임박 재료]에 해당하는 재료는 응답 JSON에서 imminent 필드를 true로 설정해줘."
        )

        # 임박 재료별 추가 주의사항 (실제로 임박 목록에 있을 때만 프롬프트에 포함)
        for keyword, notice in IMMINENT_CAUTIONS.items():
            if any(keyword in name for name in imminent):
                imminent_section += "\n" + notice

    return (
        VARIANT_RULES
        + "\n[주어진 레시피 제목]\n" + recipe_name
        + "\n[주어진 레시피 재료]\n" + recipe_ingredients
        + "\n[주어진 레시피 조리법]\n" + "\n".join(manuals)
        + "\n\n" + owned_section + cart_section + imminent_section + "\n"
    )

# ───────── 냉장고 분석 카드 ─────────

def build_analysis_prompt(ingredients: list[str], imminent: list[str]) -> str:
    imminent_text = ", ".join(imminent) if imminent else "없음"
    return f"""
당신은 냉장고를 분석해 사용자의 편의성을 돕는 슈퍼 프로rce_typ페셔널 인텔리전트 AI입니다. 
사용자의 냉장고 속 보유 식재료를 보고 간단히 분석해주세요.

[보유 식재료]
{", ".join(ingredients)}

[임박 재료 (3일 이내)]
{imminent_text}

<규칙>
1. 설명, 인사말, 추가 텍스트는 절대 작성하지 마세요.
2. 각 줄은 18자 이내로 짧게 작성하세요.
3. 반드시 다음 형식으로만 응답하세요. 
'
재료 균형: <영양 균형이나 식재료 비중을 쉼표로 구분하여 작성하세요. 예: "단백질 부족, 채소 풍부">
추천 요리: <어떤 요리 유형이 적합한지 재료 이름을 붙이지 말고 반드시 요리 고유 명사로만 쉼표로 구분하여 작성하세요. 예: "닭볶음탕, 파스타, 부대찌개">
'
"""


def parse_analysis(text: str) -> tuple[str, str]:
    status = ""
    suggestion = ""
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith("재료 균형:"):
            status = line.removeprefix("재료 균형:").strip()
        elif line.startswith("추천 요리:"):
            suggestion = line.removeprefix("추천 요리:").strip()
    return status or "분석 정보 없음", suggestion or "추천 없음"

# ───────── 식재료 사진 / 영수증 인식 ─────────

RECOGNIZE_PROMPT = """너는 식재료 인식 전문가야. 사진을 보고 냉장고에 등록할 식재료 목록을 JSON으로만 답해.

[사진 종류 판단]
- 식재료(채소, 과일, 고기, 해산물, 유제품, 가공식품 등)가 찍힌 사진이면 source_type은 "ingredients"
- 마트나 시장 영수증이면 source_type은 "receipt"
- 식재료 사진과 영수증이 섞여 있으면 source_type은 "mixed"
- 모두 관련 없는 사진이면 source_type은 "none", items는 빈 배열

[여러 장인 경우]
- 사진이 여러 장이면 모든 사진을 함께 보고 하나의 목록으로 합칠 것.
- 여러 사진에 동일한 재료가 각도만 바뀐채 찍혀있다고 판단되면 해당 재료의 개수는 그 재료가 가장 많이 보이는 사진 한 장 기준으로 셀 것.
- 영수증이 여러 장이면 모든 영수증의 품목을 합칠 것. 같은 영수증을 나눠 찍어서 같은 줄이 두 번 보이면 한 번만 셀 것.
- 식재료와 관련 없는 사진이 섞여 있으면 그 사진은 무시할 것.

[식재료 사진 규칙]
1. 사진에서 확실히 보이는 식재료만 작성할 것. 보이지 않는 재료를 추측해서 만들지 말 것.
2. 같은 재료가 여러 개면 하나로 합치고 quantity에 개수를 적을 것.
3. 포장된 제품은 상품명이 아니라 일반적인 재료명으로 작성할 것. (예: "OO농장 무항생제 계란" → "계란")
4. 완성된 요리, 반찬, 포장 음식은 재료로 나누지 말고 음식 이름 그대로 하나의 품목으로 작성하고, category는 "기타"로 할 것.

[영수증 규칙]
1. 식재료와 식품만 작성하고, 봉투, 세제, 생활용품, 할인 표시, 합계 같은 줄은 제외할 것.
2. 상품명에서 브랜드, 원산지, 중량 표기를 빼고 일반적인 재료명으로 작성할 것. (예: "국산깐마늘500g" → "깐마늘")
3. 영수증의 수량을 quantity로 쓰되, 상품명에 중량이나 용량이 있으면 그 값과 단위를 사용할 것. (예: "돼지앞다리 600g" 1개 → quantity 600, unit "g")
4. 글자가 흐려서 읽을 수 없는 품목은 제외할 것.

[공통 규칙]
- name: 한국어 일반 재료명, 15자 이내
- category: 채소, 육류, 유제품, 과일, 해산물, 기타 중 하나
- unit: 개, g, ml, L, 팩 중 하나. 개수로 세는 재료는 "개"
- quantity: 정수
- storage: 냉장, 냉동, 실온 중 그 재료를 보통 보관하는 방법
- 대마, 양귀비 등 마약류나 독버섯처럼 먹으면 위험한 것은 작성하지 말 것.
- 응답은 아래 JSON 형식으로만 작성하고 설명은 쓰지 말 것.
- expiration_date: 포장이나 라벨에 소비기한, 유통기한, "~까지" 날짜가 보이면 그 날짜를 "YYYY-MM-DD"로 작성할 것. 연도가 없으면 [오늘 날짜] 이후 가장 가까운 날짜로 연도를 정할 것. 제조일, 포장일, 생산일은 소비기한이 아니므로 쓰지 말 것. 날짜가 보이지 않거나 확실하지 않으면 null.
- 영수증에 적힌 날짜는 구매일이므로 영수증 품목의 expiration_date는 항상 null.

{"source_type": "ingredients", "items": [{"name": "우유", "category": "유제품", "quantity": 1, "unit": "개", "storage": "냉장", "expiration_date": "2026-11-15"}, {"name": "양파", "category": "채소", "quantity": 3, "unit": "개", "storage": "실온", "expiration_date": null}]}
"""

KST = timezone(timedelta(hours=9))


def _today_kst() -> date:
    return datetime.now(KST).date()


def build_recognize_prompt() -> str:
    """연도 없는 날짜(예: 11.15까지)를 판단할 수 있게 오늘 날짜를 붙임"""
    return RECOGNIZE_PROMPT + f"\n[오늘 날짜]\n{_today_kst().isoformat()}\n"

CATEGORIES = {"채소", "육류", "유제품", "과일", "해산물", "기타"}
UNITS = {"개", "g", "ml", "L", "팩"}
STORAGES = {"냉장", "냉동", "실온"}

# 앱에 없는 단위를 앱 단위로 바꿈: 단위 → (바꿀 단위, 곱할 값)
UNIT_ALIASES = {
    "kg": ("g", 1000), "킬로그램": ("g", 1000), "그램": ("g", 1),
    "mL": ("ml", 1), "ML": ("ml", 1), "l": ("L", 1), "리터": ("L", 1),
    "봉": ("팩", 1), "봉지": ("팩", 1), "묶음": ("팩", 1), "단": ("팩", 1),
    "병": ("개", 1), "캔": ("개", 1), "마리": ("개", 1), "모": ("개", 1),
    "송이": ("개", 1), "알": ("개", 1),
}

MAX_RECOGNIZED_ITEMS = 30
BANNED_KEYWORDS = ("대마", "양귀비", "마약", "아편", "필로폰", "환각")


def is_banned(name: str) -> bool:
    return any(b in name for b in BANNED_KEYWORDS)


def _to_number(value) -> float:
    try:
        return float(str(value).replace(",", "").strip())
    except (TypeError, ValueError):
        return 1.0

def _parse_expiration(value) -> str | None:
    """YYYY-MM-DD만 받고, 말이 안 되는 날짜(2000년 이전, 10년 넘게 먼 날짜)는 버림
    이미 지난 날짜는 남겨둠 (앱에서 '이미 지난 날짜'로 표시)"""
    if not value:
        return None
    try:
        d = date.fromisoformat(str(value).strip())
    except ValueError:
        return None
    if d.year < 2000 or d > _today_kst() + timedelta(days=365 * 30):
        return None
    return d.isoformat()    

def parse_recognition(text: str) -> dict:
    """Gemini 응답을 앱이 그대로 쓸 수 있는 값으로 정리"""
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {"source_type": "none", "items": []}
    if not isinstance(data, dict):
        return {"source_type": "none", "items": []}

    source = data.get("source_type")
    if source not in ("ingredients", "receipt", "mixed", "none"):
        source = "none"

    raw_items = data.get("items")
    if not isinstance(raw_items, list):
        raw_items = []

    merged: dict[tuple[str, str, str | None], dict] = {}
    for raw in raw_items[:MAX_RECOGNIZED_ITEMS]:
        if not isinstance(raw, dict):
            continue

        name = str(raw.get("name") or "").strip()[:30]
        if not name or is_banned(name):
            continue

        category = raw.get("category") if raw.get("category") in CATEGORIES else "기타"
        storage = raw.get("storage") if raw.get("storage") in STORAGES else "냉장"

        unit = str(raw.get("unit") or "개").strip()
        qty = _to_number(raw.get("quantity"))
        if unit not in UNITS:
            unit, factor = UNIT_ALIASES.get(unit, ("개", 1))
            qty *= factor
        # 앱 수량은 정수라 1.5L 같은 값은 ml로
        if unit == "L" and qty != int(qty):
            unit, qty = "ml", qty * 1000
        quantity = max(1, round(qty))
        expiration = _parse_expiration(raw.get("expiration_date"))

        # 소비기한이 다르면 다른 항목 (같은 우유라도 날짜가 다르면 따로)
        key = (name, unit, expiration)
        if key in merged:
            merged[key]["quantity"] += quantity
        else:
            merged[key] = {
                "name": name,
                "category": category,
                "quantity": quantity,
                "unit": unit,
                "storage": storage,
                "expiration_date": expiration,
            }

    return {"source_type": source, "items": list(merged.values())}

