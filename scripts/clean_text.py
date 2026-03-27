#!/usr/bin/env python3
"""
clean_text.py — Strip code, markdown artifacts, and non-prose content from
assistant responses so the result reads naturally via TTS.

Usage:
    echo "some markdown text" | python3 clean_text.py
    python3 clean_text.py < input.txt
"""

import re
import sys


def remove_fenced_code_blocks(text: str) -> str:
    return re.sub(r"```[\s\S]*?```", "", text)


EXT_SPEECH = {
    ".ts": " T S", ".tsx": " T S X", ".js": " J S", ".jsx": " J S X",
    ".py": " python", ".json": " JSON", ".md": " markdown",
    ".html": " H T M L", ".css": " C S S", ".sh": " shell",
    ".sql": " S Q L", ".yml": " YAML", ".yaml": " YAML",
    ".env": " env", ".txt": " text", ".csv": " C S V",
    ".pdf": " P D F", ".png": " P N G", ".jpg": " J P G",
    ".svg": " S V G", ".xml": " X M L", ".rs": " rust",
    ".go": " go", ".rb": " ruby", ".onnx": " O N N X",
}


def _humanize_identifier(name: str, with_ext: bool = True) -> str:
    """Turn a single identifier (filename, variable, class) into words."""
    ext_spoken = ""
    if with_ext:
        for ext, speech in EXT_SPEECH.items():
            if name.endswith(ext):
                name = name[: -len(ext)]
                ext_spoken = speech
                break

    # camelCase / PascalCase boundaries
    name = re.sub(r"([a-z])([A-Z])", r"\1 \2", name)
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", name)
    name = name.replace("-", " ").replace("_", " ")
    name = re.sub(r"\s+", " ", name).strip()
    return name + ext_spoken


def humanize_code_token(token: str) -> str:
    """Convert a code token (path, function call, identifier) to speakable text."""
    token = token.strip()
    if not token:
        return token

    token = re.sub(r"\(\)$", "", token)

    if "/" in token:
        parts = [_humanize_identifier(p) for p in token.split("/") if p]
        return " ".join(parts)

    has_ext = any(token.endswith(ext) for ext in EXT_SPEECH)
    if "." in token and not has_ext:
        parts = [_humanize_identifier(p, with_ext=False) for p in token.split(".")]
        return " ".join(parts)

    return _humanize_identifier(token)


def remove_inline_code(text: str) -> str:
    return re.sub(r"`([^`\n]+)`", lambda m: humanize_code_token(m.group(1)), text)


def remove_markdown_images(text: str) -> str:
    return re.sub(r"!\[([^\]]*)\]\([^)]+\)", "", text)


def convert_markdown_links(text: str) -> str:
    """Keep link text, drop URL."""
    return re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)


def convert_headers(text: str) -> str:
    """Convert markdown headers to plain text with a period for TTS pause."""
    return re.sub(r"^#{1,6}\s+(.+)$", r"\1.", text, flags=re.MULTILINE)


def convert_tables_to_prose(text: str) -> str:
    """Convert markdown tables to linearized prose sentences."""
    table_pattern = re.compile(
        r"((?:^\|.+\|[ \t]*\n){2,})", flags=re.MULTILINE
    )

    def _table_to_prose(match: re.Match) -> str:
        block = match.group(1).strip()
        rows = [r.strip() for r in block.split("\n") if r.strip()]

        if len(rows) < 2:
            return block

        def parse_row(row: str) -> list[str]:
            cells = row.split("|")
            # strip leading/trailing empty cells from outer pipes
            if cells and cells[0].strip() == "":
                cells = cells[1:]
            if cells and cells[-1].strip() == "":
                cells = cells[:-1]
            return [c.strip() for c in cells]

        headers = parse_row(rows[0])

        # Skip the separator row (e.g. |---|---|)
        separator_re = re.compile(r"^[\s|:-]+$")
        data_rows = [
            parse_row(r) for r in rows[1:] if not separator_re.match(r)
        ]

        if not data_rows:
            return block

        lines = []
        for cells in data_rows:
            parts = []
            for i, cell in enumerate(cells):
                if not cell or cell.strip("-") == "":
                    continue
                if i < len(headers) and headers[i]:
                    parts.append(f"{headers[i]}: {cell}")
                else:
                    parts.append(cell)
            if parts:
                lines.append("; ".join(parts) + ".")

        return "\n".join(lines)

    return table_pattern.sub(_table_to_prose, text)


def remove_code_like_lines(text: str) -> str:
    """Remove lines that look like code rather than prose."""
    code_prefixes = (
        "import ",
        "from ",
        "const ",
        "let ",
        "var ",
        "function ",
        "class ",
        "export ",
        "SELECT ",
        "INSERT ",
        "UPDATE ",
        "DELETE ",
        "CREATE ",
        "curl ",
        "wget ",
        "npm ",
        "pip ",
        "yarn ",
        "docker ",
        "kubectl ",
        "git ",
        "cd ",
        "mkdir ",
        "cp ",
        "mv ",
        "rm ",
        "chmod ",
        "brew ",
        "sudo ",
        "echo ",
        "cat ",
        "#!/",
        "//",
        "/*",
    )

    symbol_chars = set("{}();=><[]|&^~\\@#$%")

    result = []
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped:
            result.append("")
            continue

        if any(stripped.startswith(p) for p in code_prefixes):
            continue

        # High symbol density = likely code
        if len(stripped) > 10:
            symbol_count = sum(1 for c in stripped if c in symbol_chars)
            if symbol_count / len(stripped) > 0.15:
                continue

        result.append(line)

    return "\n".join(result)


def remove_bullet_markers(text: str) -> str:
    """Clean bullet/list markers but keep the text."""
    text = re.sub(r"^(\s*)-\s+", r"\1", text, flags=re.MULTILINE)
    text = re.sub(r"^(\s*)\*\s+", r"\1", text, flags=re.MULTILINE)
    text = re.sub(r"^(\s*)\d+\.\s+", r"\1", text, flags=re.MULTILINE)
    return text


def remove_bold_italic_markers(text: str) -> str:
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]+)\*", r"\1", text)
    text = re.sub(r"__([^_]+)__", r"\1", text)
    text = re.sub(r"_([^_]+)_", r"\1", text)
    return text


def humanize_remaining_paths(text: str) -> str:
    """Catch bare file paths and code identifiers that weren't inside backticks."""
    ext_pattern = "|".join(re.escape(e) for e in EXT_SPEECH)
    path_re = re.compile(
        r"(?<!\w)(?:[a-zA-Z0-9_.@-]+/)+[a-zA-Z0-9_.-]+(?:" + ext_pattern + r")"
    )
    text = path_re.sub(lambda m: humanize_code_token(m.group(0)), text)

    camel_re = re.compile(r"(?<!\w)[a-z]+(?:[A-Z][a-z]+){2,}(?:\(\))?(?!\w)")
    text = camel_re.sub(lambda m: humanize_code_token(m.group(0)), text)

    return text


def collapse_whitespace(text: str) -> str:
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = re.sub(r"[ \t]+", " ", text)
    lines = [line.strip() for line in text.split("\n")]
    return "\n".join(lines).strip()


def estimate_duration_seconds(text: str, speed: float = 1.0) -> float:
    """Rough estimate: ~15 chars/second at 1.0x speed."""
    return len(text) / 15.0 / speed


def clean(text: str) -> str:
    text = remove_fenced_code_blocks(text)
    text = convert_tables_to_prose(text)
    text = remove_markdown_images(text)
    text = convert_markdown_links(text)
    text = convert_headers(text)
    text = remove_inline_code(text)
    text = remove_code_like_lines(text)
    text = remove_bold_italic_markers(text)
    text = remove_bullet_markers(text)
    text = humanize_remaining_paths(text)
    text = collapse_whitespace(text)
    return text


def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)

    cleaned = clean(raw)
    if not cleaned:
        print("No speakable text found.", file=sys.stderr)
        sys.exit(0)

    duration = estimate_duration_seconds(cleaned)
    print(
        f"Estimated duration: {duration:.0f}s (~{duration/60:.1f} min)",
        file=sys.stderr,
    )

    print(cleaned)


if __name__ == "__main__":
    main()
