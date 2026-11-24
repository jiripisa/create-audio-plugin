#!/usr/bin/env python3
"""Derive the permanent identity of an audio plugin from its directory name.

Usage: identity.py <dir-path> [--taken Brml,Fanf] [--no-auval] [--owner <login>]

Prints JSON: APP_NAME, APP, APP_LOWER, APP_C, APP_UPPER, BUNDLE_ID, AU_SUBTYPE, OWNER.
Exits 2 with a message on stderr when the name has no ASCII letter left.

APP is the name with diacritics stripped, split into words on anything that is not an ASCII
letter or digit, each word capitalised on its first letter and joined ("Tape Loop 2" -> "TapeLoop2").

AU_SUBTYPE is a 4-char code of ASCII letters/digits with an uppercase first letter. AU subtypes
are case-sensitive OSTypes, so "taken" comparisons are case-sensitive. The code is the first
candidate in this deterministic order that is not taken:
  1. The first four characters of APP (a shorter APP is repeated cyclically in lowercase: "Ab" -> "Abab").
  2. The first letter followed by three more characters taken, in order, from a pool made of
     the remaining consonants of APP, then its other remaining letters, then its digits
     ("Strunobijec" with "Stru" taken -> "Strn"). The 3-element selections of the pool are tried
     in lexicographic order of their positions. A pool shorter than three is extended by
     cycling APP.
  3. The first letter followed by a three-digit number 000..999.
Taken codes = --taken, the built-in list below, and (unless --no-auval) the subtypes reported
by `auval -a`.
"""
import argparse
import itertools
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

BUILT_IN_TAKEN = {"Brml", "Fanf", "Didg"}
VOWELS = set("aeiouAEIOU")


def to_ascii(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def derive_app(name: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", to_ascii(name))
    return "".join(w[0].upper() + w[1:] for w in words)


def cyclic(text: str, length: int) -> str:
    return (text * length)[:length]


def candidates(app: str):
    first, rest = app[0].upper(), app[1:]
    yield first + (app[1:4] if len(app) >= 4 else cyclic(app.lower(), 4)[1:])
    consonants = [c for c in rest if c.isalpha() and c not in VOWELS]
    others = [c for c in rest if c.isalpha() and c in VOWELS]
    digits = [c for c in rest if c.isdigit()]
    pool = consonants + others + digits
    if len(pool) < 3:
        pool += list(cyclic(app.lower(), 3 - len(pool)))
    for combo in itertools.combinations(pool, 3):
        yield first + "".join(combo)
    for n in range(1000):
        yield f"{first}{n:03d}"


def auval_subtypes() -> set:
    try:
        out = subprocess.run(["auval", "-a"], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError) as e:
        print(f"warning: could not run auval ({e}); installed components not checked", file=sys.stderr)
        return set()
    found = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and len(parts[0]) == 4 and len(parts[1]) == 4:
            found.add(parts[1])
    return found


def github_login() -> str:
    try:
        result = subprocess.run(["gh", "api", "user", "--jq", ".login"],
                                capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        sys.exit(f"error: could not run gh ({e}); pass --owner")
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit("error: `gh api user` failed; pass --owner")
    return result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory")
    parser.add_argument("--taken", default="", help="comma-separated AU subtypes already in use")
    parser.add_argument("--no-auval", action="store_true", help="do not ask auval for installed subtypes")
    parser.add_argument("--owner", help="GitHub login (default: gh api user)")
    args = parser.parse_args()

    name = Path(args.directory).resolve().name
    app = derive_app(name)
    if not re.search(r"[A-Za-z]", app):
        print(f"error: directory name {name!r} has no ASCII letter", file=sys.stderr)
        sys.exit(2)

    taken = set(BUILT_IN_TAKEN) | {t for t in args.taken.split(",") if t}
    if not args.no_auval:
        taken |= auval_subtypes()
    subtype = next(c for c in candidates(app) if c not in taken)

    json.dump({
        "APP_NAME": name,
        "APP": app,
        "APP_LOWER": app.lower(),
        "APP_C": app.lower(),
        "APP_UPPER": app.upper(),
        "BUNDLE_ID": f"io.jp4.{app.lower()}",
        "AU_SUBTYPE": subtype,
        "OWNER": args.owner or github_login(),
    }, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main()
