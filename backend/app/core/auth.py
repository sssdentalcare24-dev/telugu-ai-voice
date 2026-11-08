"""Authentication.

Production uses Firebase Authentication: the app signs the user in with the
Firebase SDK and sends `Authorization: Bearer <Firebase ID token>`; the server
verifies the token with firebase-admin.

Local development can use AUTH_MODE=dev, where the `X-Dev-User` header names
the user. The settings validator refuses dev mode when APP_ENV=production.
"""

from __future__ import annotations

import re
import threading
from dataclasses import dataclass
from typing import Callable

from .config import Settings
from .errors import ApiError

_DEV_USER_RE = re.compile(r"^[A-Za-z0-9_.\-]{3,64}$")


@dataclass(frozen=True)
class User:
    uid: str
    email: str | None = None
    auth_mode: str = "firebase"


TokenVerifier = Callable[[str], dict]


class Authenticator:
    def __init__(self, settings: Settings, verifier: TokenVerifier | None = None):
        self.settings = settings
        self._verifier = verifier
        self._lock = threading.Lock()

    # -- Firebase ---------------------------------------------------------------
    def _firebase_verifier(self) -> TokenVerifier:
        if self._verifier is not None:
            return self._verifier
        with self._lock:
            if self._verifier is None:
                import firebase_admin
                from firebase_admin import auth as fb_auth
                from firebase_admin import credentials

                try:
                    app = firebase_admin.get_app()
                except ValueError:
                    cred = (
                        credentials.Certificate(self.settings.firebase_credentials_file)
                        if self.settings.firebase_credentials_file
                        else credentials.ApplicationDefault()
                    )
                    options = {"projectId": self.settings.firebase_project_id} if self.settings.firebase_project_id else None
                    app = firebase_admin.initialize_app(cred, options)

                def verify(token: str) -> dict:
                    return fb_auth.verify_id_token(token, app=app)

                self._verifier = verify
        return self._verifier

    # -- Public -------------------------------------------------------------------
    def authenticate(self, authorization: str | None, dev_user: str | None) -> User:
        if self.settings.auth_mode == "dev":
            if not dev_user:
                raise ApiError(401, "UNAUTHENTICATED", "Missing X-Dev-User header (server is in dev auth mode).")
            if not _DEV_USER_RE.fullmatch(dev_user):
                raise ApiError(401, "UNAUTHENTICATED", "X-Dev-User must be 3-64 letters, digits, '.', '_' or '-'.")
            return User(uid=f"dev:{dev_user}", auth_mode="dev")

        if not authorization or not authorization.lower().startswith("bearer "):
            raise ApiError(401, "UNAUTHENTICATED", "Sign in required.")
        token = authorization[7:].strip()
        if not token:
            raise ApiError(401, "UNAUTHENTICATED", "Sign in required.")
        try:
            claims = self._firebase_verifier()(token)
        except ApiError:
            raise
        except Exception as exc:  # firebase_admin raises several error types
            raise ApiError(401, "UNAUTHENTICATED", "Your session is invalid or has expired. Please sign in again.") from exc
        uid = claims.get("uid") or claims.get("sub")
        if not uid:
            raise ApiError(401, "UNAUTHENTICATED", "Token has no user id.")
        return User(uid=str(uid), email=claims.get("email"), auth_mode="firebase")
