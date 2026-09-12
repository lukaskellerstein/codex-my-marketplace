#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
config_file="$repo_root/.codex/config.toml"
refresh_script="$script_dir/refresh-installed-plugins.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Required command not found: python3" >&2
  exit 1
fi

if [[ ! -f "$config_file" ]]; then
  echo "Codex project config not found: $config_file" >&2
  exit 1
fi

if [[ ! -x "$refresh_script" ]]; then
  echo "Plugin refresh script is missing or not executable: $refresh_script" >&2
  exit 1
fi

python3 - "$config_file" <<'PY'
import os
from pathlib import Path
import sys
import tempfile
import tomllib


config_path = Path(sys.argv[1])
original = config_path.read_text(encoding="utf-8")
lines = original.splitlines()


def upsert_rule(
    section_header: str,
    key: str,
    value: str,
    replaced_keys: tuple[str, ...] = (),
) -> None:
    desired_line = f'"{key}" = "{value}"'

    try:
        section_start = next(
            index for index, line in enumerate(lines) if line.strip() == section_header
        )
    except StopIteration:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend((section_header, desired_line))
        return

    section_end = len(lines)
    for index in range(section_start + 1, len(lines)):
        stripped = lines[index].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section_end = index
            break

    matching_indexes = []
    matching_keys = (key, *replaced_keys)
    quoted_keys = {
        quoted_key
        for matching_key in matching_keys
        for quoted_key in (f'"{matching_key}"', f"'{matching_key}'")
    }
    for index in range(section_start + 1, section_end):
        if "=" not in lines[index]:
            continue
        left_hand_side = lines[index].split("=", 1)[0].strip()
        if left_hand_side in quoted_keys:
            matching_indexes.append(index)

    if matching_indexes:
        lines[matching_indexes[0]] = desired_line
        for duplicate_index in reversed(matching_indexes[1:]):
            del lines[duplicate_index]
    else:
        lines.insert(section_start + 1, desired_line)


upsert_rule(
    "[permissions.marketplace-development.filesystem]",
    "~/.codex",
    "write",
    replaced_keys=("~/.codex/plugins/cache/codex-my-marketplace",),
)
upsert_rule(
    '[permissions.marketplace-development.filesystem.":workspace_roots"]',
    ".git",
    "write",
)

updated = "\n".join(lines) + "\n"
tomllib.loads(updated)

if updated == original:
    print(f"Codex permissions already configured: {config_path}")
    raise SystemExit(0)

file_mode = config_path.stat().st_mode & 0o777
temporary_path = None

try:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{config_path.name}.",
        dir=config_path.parent,
    )
    temporary_path = Path(temporary_name)
    os.fchmod(descriptor, file_mode)
    with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
        temporary_file.write(updated)
        temporary_file.flush()
        os.fsync(temporary_file.fileno())
    os.replace(temporary_path, config_path)
finally:
    if temporary_path is not None and temporary_path.exists():
        temporary_path.unlink()

print(f"Updated Codex permissions: {config_path}")
PY

echo "Refreshing installed plugins..."
"$refresh_script"

echo
echo "Done. Start a new Codex thread so the updated permission profile and plugins are loaded."
