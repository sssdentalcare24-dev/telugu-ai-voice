from __future__ import annotations

import time

from fastapi.testclient import TestClient

from .conftest import ALICE, BOB, make_wav


def upload(client: TestClient, data: bytes, name: str = "నా రికార్డింగ్.wav", headers=ALICE):
    return client.post("/api/audio/upload", headers=headers, files={"file": (name, data, "audio/wav")})


def test_upload_valid_wav_and_fetch(client: TestClient) -> None:
    r = upload(client, make_wav(2.0))
    assert r.status_code == 201, r.text
    item = r.json()
    assert item["kind"] == "original"
    assert item["format"] == "wav"
    assert item["title"] == "నా రికార్డింగ్"
    assert 1.9 < item["duration_seconds"] < 2.1

    got = client.get(f"/api/audio/{item['id']}", headers=ALICE)
    assert got.status_code == 200

    f = client.get(got.json()["download_url"])
    assert f.status_code == 200
    assert f.headers["content-type"] == "audio/wav"
    assert f.content == make_wav(2.0)
    assert f.headers["content-disposition"].startswith("inline")
    dl = client.get(got.json()["download_url"] + "&download=true")
    assert dl.headers["content-disposition"].startswith("attachment")


def test_upload_rejects_fake_audio(client: TestClient) -> None:
    r = upload(client, b"this is not audio at all, just text", name="song.mp3")
    assert r.status_code == 415
    assert r.json()["error"]["code"] == "UNSUPPORTED_FORMAT"


def test_upload_rejects_corrupt_audio(client: TestClient) -> None:
    r = upload(client, b"RIFF\x00\x00\x00\x00WAVEgarbage-garbage-garbage")
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "CORRUPT_AUDIO"


def test_upload_rejects_empty_large_and_long(client: TestClient) -> None:
    assert upload(client, b"").json()["error"]["code"] == "EMPTY_FILE"
    big = upload(client, make_wav(70.0, rate=8000))  # ~1.1 MB > 1 MB test limit
    assert big.status_code == 413
    long = upload(client, make_wav(12.0, rate=8000))  # 12 s > 10 s test limit
    assert long.status_code == 422
    assert long.json()["error"]["code"] == "AUDIO_TOO_LONG"


def test_history_is_private_and_paginated(client: TestClient) -> None:
    ids = [upload(client, make_wav(0.5), name=f"clip{i}.wav").json()["id"] for i in range(3)]
    upload(client, make_wav(0.5), headers=BOB)

    page1 = client.get("/api/audio/history?limit=2", headers=ALICE).json()
    assert [i["id"] for i in page1["items"]] == ids[::-1][:2]
    assert page1["next_cursor"]
    page2 = client.get(f"/api/audio/history?limit=2&before={page1['next_cursor']}", headers=ALICE).json()
    assert [i["id"] for i in page2["items"]] == [ids[0]]
    assert page2["next_cursor"] is None

    bob_items = client.get("/api/audio/history", headers=BOB).json()["items"]
    assert len(bob_items) == 1
    # Bob cannot see or delete Alice's audio.
    assert client.get(f"/api/audio/{ids[0]}", headers=BOB).status_code == 404
    assert client.delete(f"/api/audio/{ids[0]}", headers=BOB).status_code == 404


def test_delete_removes_metadata_and_file(client: TestClient) -> None:
    item = upload(client, make_wav(0.5)).json()
    assert client.get(item["download_url"]).status_code == 200
    assert client.delete(f"/api/audio/{item['id']}", headers=ALICE).status_code == 204
    assert client.get(f"/api/audio/{item['id']}", headers=ALICE).status_code == 404
    assert client.get(item["download_url"]).status_code == 404


def test_signed_url_tamper_and_expiry(client: TestClient) -> None:
    item = upload(client, make_wav(0.5)).json()
    url = item["download_url"]
    tampered = url[:-1] + ("0" if url[-1] != "0" else "1")
    assert client.get(tampered).status_code == 403
    # Expired link (exp in the past, correctly signed)
    from app.core.signing import sign

    exp, sig = sign("test-secret-key-0123456789abcdef", item["id"], ttl_seconds=-10)
    r = client.get(f"/api/audio/{item['id']}/file?exp={exp}&sig={sig}")
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "LINK_EXPIRED"
    assert exp < time.time()


def test_oversized_content_length_rejected_early(client: TestClient) -> None:
    r = client.post(
        "/api/audio/upload",
        headers={**ALICE, "Content-Length": str(50 * 1024 * 1024), "Content-Type": "multipart/form-data; boundary=x"},
        content=b"--x--",
    )
    assert r.status_code == 413


def test_file_supports_range_requests_for_seeking(client: TestClient) -> None:
    item = upload(client, make_wav(1.0)).json()
    r = client.get(item["download_url"], headers={"Range": "bytes=0-99"})
    assert r.status_code == 206
    assert len(r.content) == 100
