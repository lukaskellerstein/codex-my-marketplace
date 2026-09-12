#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/refresh-installed-plugins.sh [--dry-run]

Refresh every plugin currently installed from this local marketplace:
  1. add a new Codex cachebuster to the plugin version
  2. reinstall the plugin from the marketplace

Options:
  --dry-run  Show which plugins would be refreshed without changing anything.
  -h, --help Show this help text.
EOF
}

dry_run=false

while (($# > 0)); do
  case "$1" in
    --dry-run)
      dry_run=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command_name in codex jq python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
marketplace_file="$repo_root/.agents/plugins/marketplace.json"

codex_root="${CODEX_HOME:-${HOME}/.codex}"
plugin_creator_root="${PLUGIN_CREATOR_SKILL_ROOT:-$codex_root/skills/.system/plugin-creator}"
read_marketplace_name="$plugin_creator_root/scripts/read_marketplace_name.py"
update_cachebuster="$plugin_creator_root/scripts/update_plugin_cachebuster.py"

if [[ ! -f "$marketplace_file" ]]; then
  echo "Marketplace file not found: $marketplace_file" >&2
  exit 1
fi

for helper_path in "$read_marketplace_name" "$update_cachebuster"; do
  if [[ ! -f "$helper_path" ]]; then
    echo "Plugin Creator helper not found: $helper_path" >&2
    echo "Set PLUGIN_CREATOR_SKILL_ROOT to the installed plugin-creator skill directory." >&2
    exit 1
  fi
done

marketplace_name="$(
  python3 "$read_marketplace_name" --marketplace-path "$marketplace_file"
)"

plugin_list_file="$(mktemp "${TMPDIR:-/tmp}/codex-plugin-list.XXXXXX")"
installed_plugins_file="$(mktemp "${TMPDIR:-/tmp}/codex-installed-plugins.XXXXXX")"

cleanup() {
  rm -f "$plugin_list_file" "$installed_plugins_file"
}
trap cleanup EXIT

codex plugin list --json >"$plugin_list_file"

jq -r --arg marketplace "$marketplace_name" '
  .installed[]
  | select(.marketplaceName == $marketplace and .installed == true)
  | [
      .name,
      (.source.source // ""),
      (.source.path // ""),
      (.marketplaceSource.sourceType // ""),
      (.marketplaceSource.source // "")
    ]
  | @tsv
' "$plugin_list_file" >"$installed_plugins_file"

plugin_count="$(wc -l <"$installed_plugins_file" | tr -d '[:space:]')"

if [[ "$plugin_count" == "0" ]]; then
  echo "No installed plugins found for marketplace '$marketplace_name'."
  exit 0
fi

# Validate the complete working set before changing any manifest.
while IFS=$'\t' read -r plugin_name source_type source_path marketplace_source_type marketplace_source; do
  if [[ ! "$plugin_name" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ ]]; then
    echo "Invalid plugin name returned by Codex: $plugin_name" >&2
    exit 1
  fi

  if [[ "$source_type" != "local" || "$marketplace_source_type" != "local" ]]; then
    echo "Plugin '$plugin_name' is not installed from a local marketplace source." >&2
    exit 1
  fi

  if [[ ! -d "$source_path" || ! -d "$marketplace_source" ]]; then
    echo "Local source path is missing for plugin '$plugin_name'." >&2
    exit 1
  fi

  canonical_source="$(cd "$source_path" && pwd -P)"
  canonical_marketplace="$(cd "$marketplace_source" && pwd -P)"
  expected_source="$repo_root/plugins/$plugin_name"

  if [[ "$canonical_marketplace" != "$repo_root" ]]; then
    echo "Marketplace '$marketplace_name' points to a different checkout:" >&2
    echo "  $canonical_marketplace" >&2
    echo "Expected:" >&2
    echo "  $repo_root" >&2
    exit 1
  fi

  if [[ "$canonical_source" != "$expected_source" ]]; then
    echo "Unexpected source for plugin '$plugin_name':" >&2
    echo "  $canonical_source" >&2
    echo "Expected:" >&2
    echo "  $expected_source" >&2
    exit 1
  fi

  if [[ ! -f "$canonical_source/.codex-plugin/plugin.json" ]]; then
    echo "Plugin manifest not found for '$plugin_name'." >&2
    exit 1
  fi
done <"$installed_plugins_file"

echo "Found $plugin_count installed plugin(s) in '$marketplace_name'."

current_index=0
while IFS=$'\t' read -r plugin_name _source_type source_path _marketplace_source_type _marketplace_source; do
  current_index=$((current_index + 1))

  if [[ "$dry_run" == true ]]; then
    echo "[$current_index/$plugin_count] Would refresh $plugin_name from $source_path"
    continue
  fi

  echo "[$current_index/$plugin_count] Updating cachebuster for $plugin_name"
  python3 "$update_cachebuster" "$source_path"

  echo "[$current_index/$plugin_count] Reinstalling $plugin_name@$marketplace_name"
  codex plugin add "$plugin_name@$marketplace_name"
done <"$installed_plugins_file"

if [[ "$dry_run" == true ]]; then
  echo "Dry run complete. No plugin manifests or installations were changed."
else
  echo "Refreshed all installed plugins from '$marketplace_name'."
  echo "Start a new Codex thread to load the updated skills and tools."
fi
