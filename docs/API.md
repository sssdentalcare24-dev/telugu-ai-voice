# API reference

Base URL examples: `http://localhost:8000` (PC), `http://10.0.2.2:8000` (Android emulator).
Interactive docs: `http://localhost:8000/docs` (disabled in production).

## Authentication

| Server mode | Header the app sends |
|---|---|
| `AUTH_MODE=firebase` (production) | `Authorization: Bearer <Firebase ID token>` |
| `AUTH_MODE=dev` (local only, refused in production) | `X-Dev-User: <3–64 chars: letters, digits . _ ->` |

Public: `GET /api/health`, `GET /api/voices`, and signed file links. Everything else needs auth.

## Errors

Every error has the same shape:

```json
{ "error": { "code": "PROVIDER_NOT_CONFIGURED", "message": "Readable explanation", "details": {} } }
```

| HTTP | code | Meaning |
|---|---|---|
| 400 | `CONSENT_REQUIRED`, `EMPTY_FILE` | Consent box not ticked / empty upload |
| 401 | `UNAUTHENTICATED` | Missing or invalid sign-in |
| 403 | `LINK_EXPIRED` | Signed audio link invalid or expired |
| 404 | `NOT_FOUND` | Not found, or belongs to another user |
| 413 | `FILE_TOO_LARGE` | Over `MAX_UPLOAD_MB` |
| 415 | `UNSUPPORTED_FORMAT` | Bytes are not WAV/MP3/OGG/FLAC/M4A |
| 422 | `VALIDATION_ERROR`, `CORRUPT_AUDIO`, `AUDIO_TOO_LONG`, `TEXT_TOO_LONG`, `NOT_TELUGU`, `UNKNOWN_VOICE`, `PITCH_UNSUPPORTED`, `STYLE_UNSUPPORTED` | Input problems |
| 502 | `PROVIDER_ERROR` | The AI vendor call failed |
| 503 | `PROVIDER_NOT_CONFIGURED`, `LIVE_CONVERSION_UNAVAILABLE` | Feature has no working provider yet |

---

### GET /api/health
Service status and **honest feature availability** (the app drives its buttons from this).

```json
{
  "status": "ok", "version": "0.2.0", "environment": "development", "auth_mode": "dev",
  "capabilities": {
    "tts": { "available": false, "ready_providers": [],
             "providers": [{ "name": "google", "state": "not_implemented", "message": "…Stage 3.", "paid": true }] },
    "voice_conversion": { "available": false, "provider": { "name": "none", "state": "not_configured", "…": "…" } },
    "live_conversion":  { "available": false, "streaming": false, "provider": { "state": "unsupported", "…": "…" } },
    "storage": { "available": true, "backend": "local" },
    "history": { "available": true, "backend": "sqlite" }
  },
  "limits": { "max_upload_mb": 20, "max_audio_seconds": 300, "max_tts_chars": 5000,
              "allowed_formats": ["wav", "mp3", "ogg", "flac", "m4a"] }
}
```

### GET /api/voices
Voices from `config/voices.yaml` for enabled providers, each with `available: true|false`.

### POST /api/tts/generate  🔒
```json
{ "text": "నమస్కారం! మీరు ఎలా ఉన్నారు?", "voice_id": "google-te-female-hd",
  "speed": 1.0, "pitch": 0, "style": null, "title": null }
```
* `speed` 0.25–2.0 · `pitch` −20…+20 semitones (only voices with `supports_pitch`)
* Text is NFC-normalised, must contain Telugu, max `MAX_TTS_CHARS`.
* **201** → an *AudioItem* (below). **503** until a TTS provider is integrated (Stage 3).

### POST /api/voice/convert  🔒  (multipart/form-data)
| field | value |
|---|---|
| `direction` | `male_to_female` or `female_to_male` |
| `consent` | `true` (required) |
| `file` **or** `source_audio_id` | a new recording, or an uploaded original |

**201** → `{ "original": AudioItem, "converted": AudioItem }`. **503** until a provider is configured.

### POST /api/voice/live/session  🔒
`{ "direction": "male_to_female", "consent": true }` → **201**
`{ session_id, websocket_url, expires_at, sample_rate, encoding }` when a genuine streaming
engine exists; otherwise **503 `LIVE_CONVERSION_UNAVAILABLE`**.

### POST /api/audio/upload  🔒  (multipart/form-data)
`file` (WAV, MP3, OGG, FLAC, M4A), optional `title`. **201** → AudioItem (`kind: "original"`).

### GET /api/audio/history  🔒
Query: `limit` (1–100, default 50), `before` (= `next_cursor`), `kind` (`tts|original|converted`).
→ `{ "items": [AudioItem…], "next_cursor": "2026-11-08T03:41:22.123456+00:00" | null }`

### GET /api/audio/{id}  🔒
One AudioItem with a fresh signed `download_url`.

### GET /api/audio/{id}/file?exp=…&sig=…[&download=true]
Streams the file (supports HTTP Range for seeking). No auth header – the HMAC signature is the
permission and expires after `DOWNLOAD_URL_TTL_SECONDS`. `download=true` → save-as attachment.

### DELETE /api/audio/{id}  🔒
**204**. Removes the file and its history entry.

---

### AudioItem
```json
{
  "id": "3f9c…", "kind": "tts", "title": "నమస్కారం! మీరు ఎలా ఉన్నారు?",
  "format": "mp3", "mime_type": "audio/mpeg", "size_bytes": 48211, "duration_seconds": 3.1,
  "created_at": "2026-11-08T03:41:22.123456+00:00", "source_audio_id": null,
  "parameters": { "voice_id": "google-te-female-hd", "speed": 1.0, "pitch": 0 },
  "download_url": "/api/audio/3f9c…/file?exp=1762573882&sig=…",
  "download_url_expires_at": 1762573882
}
```
`download_url` is relative – prefix it with the API base URL.


## Personal voice cloning (`/api/clone`)

All endpoints need sign-in (Firebase ID token, or `X-Dev-User` in dev mode). Users only ever see their
own profiles and audio (other users' ids return 404).

| Method & path | Purpose |
|---|---|
| `GET /api/clone/providers` | Providers with `state`, `ready`, `paid`, `min_seconds`, `max_seconds`, `needs_transcript`, `languages`, `cross_lingual`, `supports_speed`; the 12 languages; limits |
| `POST /api/clone/profiles` | Step 1. JSON `{name, category: female\|male, recording_language, provider?, consent: {confirmed: true, relationship: self\|permission, speaker_name?, statement}}` → profile (`status: draft`). 400 `CONSENT_REQUIRED` without consent. Rate-limited. |
| `POST /api/clone/profiles/{id}/sample` | Step 2. Multipart `file` (WAV/MP3/OGG/FLAC/M4A) + `transcript` (required by IndicF5). Checks real format, size and the provider's min/max length. |
| `POST /api/clone/profiles/{id}/clone` | Step 3. Creates the voice at the provider, stores the provider voice id, makes a short preview. `warning` is set if only the preview failed. |
| `GET /api/clone/profiles` / `GET /api/clone/profiles/{id}` | My voice library (with signed links to sample and preview) |
| `DELETE /api/clone/profiles/{id}` | Deletes the profile, its sample and preview, and the voice at the provider |
| `POST /api/clone/tts` | JSON `{profile_id, text, language, speed}` → generation with signed audio link. Rate-limited. 422 `UNSUPPORTED_LANGUAGE` if the provider cannot speak it. |
| `GET /api/clone/history?profile_id=&limit=&before=` | Generation history, newest first |
| `DELETE /api/clone/history/{id}` | Deletes a generation and its audio |
| `GET /api/audio/{id}/file?exp=&sig=&format=mp3&download=true` | MP3 download of any WAV audio |

Errors use the usual envelope. Provider problems map to `PROVIDER_NOT_CONFIGURED` (503),
`PROVIDER_BUSY` (429/503), `PROVIDER_QUOTA` (402), `PROVIDER_TIMEOUT` (504), `PROVIDER_ERROR` (502);
rate limits to `RATE_LIMITED` (429, with `details.retry_after_seconds`).
