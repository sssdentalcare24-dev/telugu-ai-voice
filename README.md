# తెలుగు AI Voice – Telugu Voice Studio

Telugu text-to-speech, male ↔ female voice conversion and a live voice changer.
One Flutter codebase for the **Android app** and the **web app / PWA**, with a **Python FastAPI** backend.

> **Build status: Stages 1 and 2 complete.** The full app UI, navigation and the backend
> (every endpoint, sign-in checks, validation, upload, history, secure downloads) work now.
> The AI voices themselves need paid API credentials and are added in Stages 3–6.
> The app reads feature status from the server and keeps a button disabled, with the reason
> shown, until its feature really works.

## What works today vs. what needs credentials

| Feature | Status now | What it needs |
|---|---|---|
| App UI: Home, Text-to-Voice, M→F, F→M, Live, History, Settings | ✅ Working (light + dark) | – |
| Telugu fonts + in-app Telugu keyboard | ✅ Working | – |
| Upload audio (WAV/MP3/OGG/FLAC/M4A), checks on size, format and length | ✅ Working | – |
| Audio history: list, filter, open, download, delete | ✅ Working (local server) | – |
| Secure, expiring download links; per-user privacy | ✅ Working | – |
| Server sign-in check (Firebase ID tokens) | ✅ Backend done | **Firebase project** (app sign-in screen: Stage 3) |
| Telugu female/male TTS | ⏳ Stage 3 – button disabled | **Google Cloud TTS** and/or **Azure Speech** key (paid) |
| Male→female / female→male conversion | ⏳ Stages 4–5 – button disabled | **Speech-to-speech API key** (paid) |
| Microphone recording | ⏳ Stage 4 | – |
| Live voice changer | ⏳ Stage 6 – shown as *Unavailable* | **Streaming conversion engine** (GPU server or vendor) |
| Share sheet, Cloud Storage/Firestore history | ⏳ Stage 7 | Firebase project |

---

## 1. Run the backend (Windows PowerShell)

Needs Python 3.11+.

```powershell
cd telugu-ai-voice\backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
copy .env.example .env          # AUTH_MODE=dev for local testing
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open <http://localhost:8000/docs> for the interactive API, or <http://localhost:8000/api/health>.

Run the tests:

```powershell
python -m pytest
```

(macOS/Linux: `python3 -m venv .venv && source .venv/bin/activate`, `cp .env.example .env`.)

## 2. Run the Flutter app

Needs the Flutter SDK (stable channel) and Android Studio with an emulator.

```powershell
cd telugu-ai-voice\app
flutter create --platforms=android,web --org com.teluguaivoice --project-name telugu_ai_voice .   # adds android/ (keeps existing files)
flutter pub get
dart run tool\setup_android.dart      # mic + internet permissions, app name, debug HTTP
flutter analyze
flutter test
```

Run it:

```powershell
flutter run -d chrome --web-port 5000       # web app
flutter run                                  # Android emulator (uses http://10.0.2.2:8000)
```

On a **real phone**, connect it to the same Wi-Fi as your PC, then in the app open
**Settings → Server** and enter `http://<your PC's IP>:8000` (find it with `ipconfig`).
Allow port 8000 through Windows Firewall if asked.

To point a build at a server from the start:
`flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`

## 3. Build the Android APK

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
# output: build\app\outputs\flutter-apk\app-release.apk
```

Release builds only allow **HTTPS** servers. For testing against your PC over plain HTTP,
build a debug APK instead: `flutter build apk --debug`.
Play Store signing (upload keystore) is set up in Stage 8.

## 4. Build and deploy the web app / PWA

```powershell
flutter build web --release --dart-define=API_BASE_URL=/
```

`API_BASE_URL=/` means "same domain as the web page". With Docker this is wired for you:

```powershell
cd telugu-ai-voice
docker compose up --build        # web on http://localhost:8080, API proxied at /api
```

For a public site, serve over HTTPS (Cloud Run, Firebase Hosting + Cloud Run, or any host with nginx).
Browsers offer **Install app** once the site is on HTTPS (manifest and icons are included).

## 5. Configuration

All settings live in `backend/.env` – see [`backend/.env.example`](backend/.env.example).
Voices are listed in [`backend/config/voices.yaml`](backend/config/voices.yaml) and can be changed without code.
**Never put keys in the Flutter app**; the app only knows the server address.

For production set `APP_ENV=production`, `AUTH_MODE=firebase` and a random 32+ character
`SECRET_KEY` – the server refuses to start with dev sign-in or the default key in production.

## Docs

* [Architecture](docs/ARCHITECTURE.md) – components, provider system, security, live-conversion design, folder layout, stages
* [API reference](docs/API.md)

## Licences

Fonts: Noto Sans and Noto Sans Telugu, SIL Open Font License 1.1 (`app/assets/fonts/OFL.txt`).
