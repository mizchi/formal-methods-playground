#!/usr/bin/env python3
"""Resolve every relative Markdown link in the repo, and every in-page anchor.

A fix without a lock rots again, which is the argument the book makes about
models and applies just as well to its own cross-references. Two links had
already drifted by the time this was written.

Anchors are resolved the way GitHub renders them: lowercase, strip anything
that is not a word character, space or hyphen, then spaces to hyphens.
"""
from __future__ import annotations

import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", "node_modules", "target", "result", ".lake", "_build"}
LINK = re.compile(r"\[[^\]^]*?\]\(\s*(<[^>]*>|[^)\s]+)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$", re.MULTILINE)
FENCE = re.compile(r"^[ \t]*(```|~~~).*?^[ \t]*\1[ \t]*$", re.MULTILINE | re.DOTALL)
CODE_SPAN = re.compile(r"(`+)(?:(?!\1).)*?\1", re.DOTALL)


def prose(text: str) -> str:
    """Drop fenced blocks and inline code so `arr[i](x)` is not read as a link."""
    text = FENCE.sub("", text)
    return CODE_SPAN.sub("", text)


def slug(text: str) -> str:
    text = re.sub(r"`|\*|_|\[|\]|\(|\)", "", text)
    text = unicodedata.normalize("NFC", text).lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    return re.sub(r"\s+", "-", text.strip())


def anchors(path: pathlib.Path) -> set[str]:
    found: set[str] = set()
    for _, title in HEADING.findall(FENCE.sub("", path.read_text(encoding="utf-8"))):
        base = slug(title)
        candidate, n = base, 1
        while candidate in found:
            candidate, n = f"{base}-{n}", n + 1
        found.add(candidate)
    return found


def markdown_files() -> list[pathlib.Path]:
    return sorted(
        p
        for p in ROOT.rglob("*.md")
        if not any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts)
    )


def main() -> int:
    anchor_cache: dict[pathlib.Path, set[str]] = {}
    broken: list[str] = []
    checked = 0

    for md in markdown_files():
        for raw in LINK.findall(prose(md.read_text(encoding="utf-8"))):
            target = raw[1:-1] if raw.startswith("<") else raw
            if target.startswith(("http://", "https://", "mailto:", "tel:")):
                continue
            path_part, _, anchor = target.partition("#")
            checked += 1
            rel = md.relative_to(ROOT)

            if path_part:
                dest = (md.parent / path_part).resolve()
                if not dest.exists():
                    broken.append(f"{rel}: {target} (no such file)")
                    continue
            else:
                dest = md.resolve()

            if anchor and dest.suffix == ".md":
                if dest not in anchor_cache:
                    anchor_cache[dest] = anchors(dest)
                if anchor.lower() not in anchor_cache[dest]:
                    broken.append(f"{rel}: {target} (no such heading)")

    if broken:
        print(f"== links: {len(broken)} broken of {checked} checked", file=sys.stderr)
        for item in broken:
            print(f"  {item}", file=sys.stderr)
        return 1

    print(f"== links: {checked} relative links resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
