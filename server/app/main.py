from fastapi import FastAPI

from app.routers import kamis_router, recipe_router

app = FastAPI(title="냉장고 매니저 API")
app.include_router(kamis_router.router)
app.include_router(recipe_router.router)


@app.get("/health")
def health():
    return {"status": "ok"}