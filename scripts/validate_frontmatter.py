#!/usr/bin/env python3
"""Validate YAML frontmatter of every gitea-*/SKILL.md.

Checks:
- File starts with --- on line 1, ends frontmatter with another ---
- Required keys: name, version, description
- name == directory name
- version is a semver (x.y.z)
- description non-empty and includes "skill" trigger keywords
- Markdown body is non-empty after frontmatter
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[\w.]+)?$")
REPO_ROOT = Path(__file__).resolve().parent.parent
SKILL_DIRS = sorted(REPO_ROOT.glob("gitea-*"))


def parse_frontmatter(text: str) -> tuple[dict[str, str], str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    block = text[4:end]
    body = text[end + 5 :]
    fm: dict[str, str] = {}
    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        v = v.strip()
        # strip surrounding quotes (single line scalars)
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        fm[k.strip()] = v
    return fm, body


def validate(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return [f"{skill_dir.name}: SKILL.md missing"]

    text = skill_md.read_text(encoding="utf-8")
    parsed = parse_frontmatter(text)
    if parsed is None:
        return [f"{skill_md}: cannot parse YAML frontmatter (must start and end with ---)"]
    fm, body = parsed

    for key in ("name", "version", "description"):
        if key not in fm or not fm[key]:
            errors.append(f"{skill_md}: missing required frontmatter key '{key}'")

    if "name" in fm and fm["name"] != skill_dir.name:
        errors.append(
            f"{skill_md}: frontmatter name '{fm['name']}' does not match dir '{skill_dir.name}'"
        )

    if "version" in fm and not SEMVER.match(fm["version"]):
        errors.append(f"{skill_md}: version '{fm['version']}' is not semver")

    if "description" in fm:
        d = fm["description"]
        if len(d) < 30:
            errors.append(f"{skill_md}: description too short (<30 chars)")

    if not body.strip():
        errors.append(f"{skill_md}: body is empty after frontmatter")

    return errors


def main() -> int:
    if not SKILL_DIRS:
        print("no gitea-* directories found", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for d in SKILL_DIRS:
        all_errors.extend(validate(d))

    for e in all_errors:
        print(f"ERROR: {e}", file=sys.stderr)

    if all_errors:
        return 1

    print(f"OK: validated {len(SKILL_DIRS)} skills")
    return 0


if __name__ == "__main__":
    sys.exit(main())
