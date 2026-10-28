import logging

logging.basicConfig(level=logging.INFO)
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

from fastapi import FastAPI

from app.routers import ai_router, kamis_router, recipe_router

app = FastAPI(title="냉장고 매니저 API")
app.include_router(kamis_router.router)
app.include_router(recipe_router.router)
app.include_router(ai_router.router)

@app.get("/health")
def health():
    return {"status": "ok"}