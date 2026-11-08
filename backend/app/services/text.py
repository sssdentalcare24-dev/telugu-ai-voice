"""Telugu text handling: Unicode normalisation and splitting long paragraphs
into provider-sized chunks without breaking a Telugu syllable apart."""

from __future__ import annotations

import re
import unicodedata

TELUGU_RANGE = (0x0C00, 0x0C7F)
VIRAMA = "్"
# ZWNJ / ZWJ change how Telugu conjuncts render, so they are preserved.
_KEEP_FORMAT_CHARS = {"‌", "‍"}
_SENTENCE_END = re.compile(r"(?<=[.!?।॥\n])\s+")
_SPACES = re.compile(r"[ \t ]+")


def contains_telugu(text: str) -> bool:
    return any(TELUGU_RANGE[0] <= ord(ch) <= TELUGU_RANGE[1] for ch in text)


def normalize_text(text: str) -> str:
    """NFC-normalise, drop control characters, tidy whitespace."""
    text = unicodedata.normalize("NFC", text)
    cleaned = []
    for ch in text:
        if ch in "\n\t" or ch in _KEEP_FORMAT_CHARS:
            cleaned.append(ch)
        elif unicodedata.category(ch) in ("Cc", "Cf", "Cs", "Co"):
            continue
        else:
            cleaned.append(ch)
    text = "".join(cleaned).replace("\r", "")
    lines = [_SPACES.sub(" ", line).strip() for line in text.split("\n")]
    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _nbytes(s: str) -> int:
    return len(s.encode("utf-8"))


def _hard_split(word: str, max_bytes: int) -> list[str]:
    """Split one oversized token on a safe boundary (never before a combining
    mark and never right after a virama)."""
    parts: list[str] = []
    current = ""
    for ch in word:
        if current and _nbytes(current + ch) > max_bytes:
            idx = len(current)
            # Never start the next piece with a combining mark (vowel sign, anusvara...)
            # and never end this piece on a virama (it joins the next consonant).
            if unicodedata.category(ch)[0] == "M" or current[-1] == VIRAMA:
                idx -= 1
                while idx > 0 and (
                    unicodedata.category(current[idx])[0] == "M" or current[idx - 1] == VIRAMA
                ):
                    idx -= 1
            if idx <= 0:
                idx = len(current)  # pathological input: cut anyway
            parts.append(current[:idx])
            current = current[idx:]
        current += ch
    if current:
        parts.append(current)
    return parts


def split_for_tts(text: str, max_bytes: int = 4800) -> list[str]:
    """Split text into chunks of at most `max_bytes` UTF-8 bytes, preferring
    sentence boundaries, then word boundaries."""
    text = text.strip()
    if not text:
        return []
    if _nbytes(text) <= max_bytes:
        return [text]

    chunks: list[str] = []
    current = ""

    def flush() -> None:
        nonlocal current
        if current.strip():
            chunks.append(current.strip())
        current = ""

    for sentence in _SENTENCE_END.split(text):
        sentence = sentence.strip()
        if not sentence:
            continue
        candidate = f"{current} {sentence}".strip() if current else sentence
        if _nbytes(candidate) <= max_bytes:
            current = candidate
            continue
        flush()
        if _nbytes(sentence) <= max_bytes:
            current = sentence
            continue
        for word in sentence.split(" "):
            candidate = f"{current} {word}".strip() if current else word
            if _nbytes(candidate) <= max_bytes:
                current = candidate
                continue
            flush()
            if _nbytes(word) <= max_bytes:
                current = word
            else:
                pieces = _hard_split(word, max_bytes)
                chunks.extend(pieces[:-1])
                current = pieces[-1]
    flush()
    return chunks
