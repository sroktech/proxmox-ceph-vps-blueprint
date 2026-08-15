#!/usr/bin/env python3
"""
Apply one Mermaid init directive to every ```mermaid block in a Markdown tree.

Idempotent: running it twice changes nothing. Skips blocks that already carry
an %%{init ...}%% directive or a YAML `---` config header.

Usage:
    python3 mermaid_init.py docs --check     # report only, exit 1 if changes needed
    python3 mermaid_init.py docs             # rewrite in place
"""

import argparse
import pathlib
import re
import sys

DIRECTIVE = (
    '%%{init: {"flowchart": {"htmlLabels": true, "wrappingWidth": 400, '
    '"subGraphTitleMargin": {"top": 6, "bottom": 14}}}}%%'
)

# ```mermaid / ~~~~mermaid, optionally indented, optionally with attributes
FENCE_OPEN = re.compile(r'^(?P<indent>[ \t]*)(?P<fence>`{3,}|~{3,})[ \t]*mermaid\b', re.I)


def process(text: str) -> tuple[str, int]:
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    added = 0

    while i < len(lines):
        m = FENCE_OPEN.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue

        indent, fence = m.group("indent"), m.group("fence")
        out.append(lines[i])
        i += 1

        # find first non-blank line inside the block
        j = i
        while j < len(lines) and not lines[j].strip():
            j += 1

        closing = re.compile(rf'^[ \t]*{re.escape(fence[0])}{{{len(fence)},}}[ \t]*$')
        first = lines[j].strip() if j < len(lines) else ""
        needs = not (
            first.startswith("%%{init")
            or first == "---"                      # YAML frontmatter config
            or (j >= len(lines) or closing.match(lines[j]))  # empty block
        )

        if needs:
            out.append(indent + DIRECTIVE)
            added += 1

        # copy the rest of the block verbatim
        while i < len(lines) and not closing.match(lines[i]):
            out.append(lines[i])
            i += 1
        if i < len(lines):
            out.append(lines[i])
            i += 1

    result = "\n".join(out)
    if text.endswith("\n"):
        result += "\n"
    return result, added


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".", help="directory or file to process")
    ap.add_argument("--check", action="store_true", help="report only, do not write")
    args = ap.parse_args()

    root = pathlib.Path(args.root)
    files = [root] if root.is_file() else sorted(root.rglob("*.md"))

    total = 0
    for path in files:
        original = path.read_text(encoding="utf-8")
        updated, added = process(original)
        if added:
            total += added
            print(f"{'would patch' if args.check else 'patched'} {path} ({added} block{'s' if added > 1 else ''})")
            if not args.check:
                path.write_text(updated, encoding="utf-8")

    if not total:
        print("all mermaid blocks already have the directive")
    return 1 if (args.check and total) else 0


if __name__ == "__main__":
    sys.exit(main())
