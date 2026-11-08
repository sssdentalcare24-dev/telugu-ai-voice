"""FastAPI entry point: `uvicorn app.main:app --reload`."""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api.deps import AppContext
from .api.routes import audio, health, tts, voice
from .core.auth import Authenticator, TokenVerifier
from .core.config import Settings
from .core.errors import install_error_handlers
from .providers.catalog import load_catalog
from .providers.registry import ProviderRegistry, build_registry
from .services.repository import SqliteAudioRepository
from .services.storage import LocalAudioStorage

UPLOAD_PATHS = ("/api/audio/upload", "/api/voice/convert")


def create_app(
    settings: Settings | None = None,
    registry: ProviderRegistry | None = None,
    token_verifier: TokenVerifier | None = None,
) -> FastAPI:
    settings = settings or Settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        description="Telugu text-to-speech, voice conversion and audio history for తెలుగు AI Voice.",
        docs_url="/docs" if settings.app_env != "production" else None,
        redoc_url="/redoc" if settings.app_env != "production" else None,
    )
    app.state.ctx = AppContext(
        settings=settings,
        registry=registry or build_registry(settings),
        catalog=load_catalog(settings.voices_config_file),
        storage=LocalAudioStorage(settings.local_storage_dir),
        repo=SqliteAudioRepository(settings.sqlite_path),
        authenticator=Authenticator(settings, token_verifier),
    )

    install_error_handlers(app)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        # Any localhost port in development, so `flutter run -d chrome` just works.
        allow_origin_regex=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$" if settings.app_env != "production" else None,
        allow_credentials=False,
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Dev-User"],
        max_age=600,
    )

    upload_limit = settings.max_upload_bytes + 1024 * 1024  # multipart overhead allowance

    @app.middleware("http")
    async def guard_and_secure(request: Request, call_next):
        if request.method == "POST" and request.url.path in UPLOAD_PATHS:
            length = request.headers.get("content-length")
            if length and length.isdigit() and int(length) > upload_limit:
                return JSONResponse(
                    status_code=413,
                    content={
                        "error": {
                            "code": "FILE_TOO_LARGE",
                            "message": f"Audio files must be {settings.max_upload_mb} MB or smaller.",
                        }
                    },
                )
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("X-Frame-Options", "DENY")
        if settings.app_env == "production":
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        return response

    for module in (health, tts, voice, audio):
        app.include_router(module.router)

    return app


app = create_app()
