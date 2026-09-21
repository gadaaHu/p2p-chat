from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from . import models
from .database import engine
from .routes_register import router as auth_router
from .prekeys import router as prekeys_router
from .signaling import router as signaling_router

models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="P2P Chat Signaling Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/api/auth", tags=["Authentication"])
app.include_router(prekeys_router, prefix="/api", tags=["X3DH PreKeys"])
app.include_router(signaling_router, prefix="/api", tags=["Signaling & Messaging"])

@app.get("/")
def read_root():
    return {"message": "P2P Chat Signaling Server is running"}
