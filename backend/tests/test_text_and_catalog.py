from __future__ import annotations

import unicodedata
from pathlib import Path

import pytest

from app.core.config import Settings
from app.providers.catalog import load_catalog
from app.services.audio import sniff_format
from app.services.text import VIRAMA, contains_telugu, normalize_text, split_for_tts


def test_normalize_keeps_telugu_and_zwnj() -> None:
    raw = "  యాప్‌కు \t  స్వాగతం\r\n\n\n\nనమస్కారం\u0007 "
    assert normalize_text(raw) == "యాప్‌కు స్వాగతం\n\nనమస్కారం"


def test_normalize_is_nfc() -> None:
    decomposed = unicodedata.normalize("NFD", "ఈ")
    assert normalize_text(decomposed) == unicodedata.normalize("NFC", "ఈ")


def test_contains_telugu() -> None:
    assert contains_telugu("Hello తెలుగు")
    assert not contains_telugu("Hello 123")


def test_split_short_text_is_single_chunk() -> None:
    assert split_for_tts("నమస్కారం.") == ["నమస్కారం."]


def test_split_long_paragraph_respects_byte_budget_and_sentences() -> None:
    sentence = "మీరు ఎలా ఉన్నారు? "
    text = sentence * 200
    chunks = split_for_tts(text, max_bytes=300)
    assert len(chunks) > 1
    assert all(len(c.encode()) <= 300 for c in chunks)
    assert all(c.endswith("?") for c in chunks)  # split on sentence boundaries
    assert " ".join(chunks).split() == text.split()  # nothing lost


def test_split_single_huge_word_never_breaks_a_syllable() -> None:
    word = "క్ష్మి" * 200  # conjuncts joined with virama
    chunks = split_for_tts(word, max_bytes=50)
    assert "".join(chunks) == word
    for c in chunks:
        assert len(c.encode()) <= 50
        assert unicodedata.category(c[0])[0] != "M"
        assert not c.endswith(VIRAMA)


@pytest.mark.parametrize(
    "data,fmt",
    [
        (b"RIFF\x00\x00\x00\x00WAVEfmt ", "wav"),
        (b"ID3\x04\x00\x00\x00\x00\x00\x00\x00\x00", "mp3"),
        (b"\xff\xfb\x90\x00" + b"\x00" * 10, "mp3"),
        (b"OggS" + b"\x00" * 10, "ogg"),
        (b"fLaC" + b"\x00" * 10, "flac"),
        (b"\x00\x00\x00\x20ftypM4A \x00\x00", "m4a"),
        (b"<html><body>hi</body></html>", None),
        (b"MZ\x90\x00" + b"\x00" * 12, None),
    ],
)
def test_sniff_format(data: bytes, fmt: str | None) -> None:
    assert sniff_format(data) == fmt


def test_voice_catalog_loads_and_covers_both_genders() -> None:
    catalog = load_catalog(Settings(_env_file=None).voices_config_file)
    assert {v.gender for v in catalog.voices} == {"female", "male"}
    assert all(v.language_code == "te-IN" for v in catalog.voices)


def test_voice_catalog_rejects_duplicates(tmp_path: Path) -> None:
    f = tmp_path / "v.yaml"
    entry = "  - {id: dup-voice, provider: google, provider_voice: x, gender: male, display_name: X}\n"
    f.write_text("voices:\n" + entry + entry, encoding="utf-8")
    with pytest.raises(ValueError):
        load_catalog(f)
