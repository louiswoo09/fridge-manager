import os
from dotenv import load_dotenv

load_dotenv()  # server/.env 를 찾아서 환경변수로 읽음


class Settings:
    kamis_cert_key: str = os.getenv("KAMIS_CERT_KEY", "")
    kamis_cert_id: str = os.getenv("KAMIS_CERT_ID", "")
    food_api_key: str = os.getenv("FOOD_API_KEY", "")
    gemini_api_key: str = os.getenv("GEMINI_API_KEY", "")
    gemini_model: str = os.getenv("GEMINI_MODEL", "gemini-3.1-flash-lite")


settings = Settings()