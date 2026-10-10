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
8. 양념(seasoning)은 다음 양념만 추가할것: 소금, 설탕, 간장, 식용유, 참기름, 후추, 고춧가루, 된장, 고추장, 식초, 다진마늘, 마요네즈, 케첩, 밥, 물, 김치.
9. 요리의 정체성을 유지하는 데 필요한 주재료(예: 고기, 해산물, 면 등)가 [냉장고 속 재료]에 존재하지 않는 경우, 역할이 유사한 대체 재료도 없다면 무리하게 레시피를 변형하지 말고 insufficient를 true로 설정하고 다른 필드는 비운채 tip 필드에 "OO 재료를 더해주시면 훌륭한 요리가 될 것 같아요!" 메시지를 적을것. 
10. [냉장고 속 재료]나 [담아놓기], 양념을 제외한 권장 재료나 요리를 더 맛있게 만드는 팁은 변형 레시피를 기준으로 tip 필드에 작성할 것. 만약 팁이 여러 개면 팁마다 숫자를 부여하고 줄바꿈(\n)으로 구분할 것. 작성할 팁이 없으면 tip은 null로 작성할 것.
11. servings는 기본 1인분 기준으로 작성.
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
당신은 냉장고를 분석해 사용자의 편의성을 돕는 슈퍼 프로페셔널 인텔리전트 AI입니다. 
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