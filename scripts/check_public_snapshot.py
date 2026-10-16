#!/usr/bin/env python3
"""Conservative, non-disclosing screen for public-source candidates.

This is a CI safety net, NOT a full secret scanner, source audit, or
substitute for checking binaries and the history that will be published.
Only tracked files are inspected. The program never prints matching values.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

SENSITIVE_FILE = re.compile(
    r"(^|/)(?:\.env(?:\..*)?|id_(?:rsa|ed25519)|"
    r".*\.(?:pem|p12|pfx|jks|keystore|key|sqlite|db|dump|bak))$",
    re.IGNORECASE,
)

PLACEHOLDER_FILES = {".env.example", "key.properties.example"}

PATTERNS: dict[str, re.Pattern[str]] = {
    "private-key material": re.compile(
        r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
    ),
    "GitHub credential pattern": re.compile(
        r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,})"
    ),
    "AWS access-key pattern": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "live secret-key pattern": re.compile(
        r"\b(?:sk_live_|rk_live_)[A-Za-z0-9]{20,}\b"
    ),
    "Tailscale private address": re.compile(
        r"\b100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])"
        r"\.(?:\d{1,3})\.(?:\d{1,3})\b"
    ),
    "private tailnet DNS": re.compile(
        r"\b[A-Za-z0-9.-]+\.ts\.net\b", re.IGNORECASE
    ),
    "developer-specific home directory": re.compile(
        r"(?:/home/" + r"christos/|C:\\Users\\" + r"xrist\\)", re.IGNORECASE
    ),
}

def tracked_files() -> list[pathlib.Path]:
    names = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=ROOT
    ).split(b"\0")
    return [
        ROOT / bytes_name.decode("utf-8", errors="surrogateescape")
        for bytes_name in names
        if bytes_name
    ]


def main() -> int:
    issues: list[tuple[str, str]] = []
    binary_count = 0
    text_count = 0

    for path in tracked_files():
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()

        if (SENSITIVE_FILE.search(relative)
                and path.name not in PLACEHOLDER_FILES):
            issues.append((relative, "sensitive filename"))

        data = path.read_bytes()
        if b"\0" in data[:4096]:
            binary_count += 1
            continue

        try:
            content = data.decode("utf-8")
        except UnicodeDecodeError:
            binary_count += 1
            continue

        text_count += 1
        for category, pattern in PATTERNS.items():
            if pattern.search(content):
                issues.append((relative, category))

    print(
        f"Screened {text_count} tracked text files; "
        f"{binary_count} binary/non-UTF8 files require separate review."
    )
    if issues:
        print("Potential publication blockers (file and category only):")
        for filename, category in sorted(set(issues)):
            print(f"  {filename} — {category}")
        print("Do not publish until each item is reviewed and resolved.")
        return 1

    print("No configured high-confidence patterns found.")
    print(
        "PASS is not proof of security. Audit code, binaries, "
        "third-party rights and fresh public history separately."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
