#!/usr/bin/env bash
# =============================================================================
# Post-Generation Validation Script for Paperclip Company Packages
# =============================================================================
# Validates a generated company package and reports errors/warnings.
# Run this after the AI agent finishes writing all files (Phase 5).
# The agent reads the output and fixes any ERRORs before proceeding.
#
# Usage:
#   bash post-generate.sh <company-root>
#
# Output format (one per line):
#   ERROR: <category>: <message>
#   WARN:  <category>: <message>
#   OK:    <category>: <message>
#   ---
#   RESULT: X errors, Y warnings
#
# Exit codes:
#   0 = no errors (warnings are OK)
#   1 = errors found
# =============================================================================

set -euo pipefail

# ---- Check dependencies ----
if ! command -v jq &>/dev/null; then
  echo "ERROR: setup: jq is required but not found. Install with: apt install jq / brew install jq"
  exit 1
fi

# ---- Parse arguments ----
if [ -z "${1:-}" ]; then
  echo "Usage: $0 <company-root>"
  exit 1
fi

COMPANY_ROOT="$(cd "$1" && pwd)"

ERRORS=0
WARNINGS=0
PASSED=0

error() { echo "ERROR: $1: $2"; ERRORS=$((ERRORS + 1)); }
warn()  { echo "WARN:  $1: $2"; WARNINGS=$((WARNINGS + 1)); }
ok()    { echo "OK:    $1: $2"; PASSED=$((PASSED + 1)); }

# =============================================================================
# Lookup Tables (from role-plugin-matrix.md)
# =============================================================================

is_gws_eligible() {
  # Match both abbreviations (CEO, CMO) and full titles (Chief Executive Officer)
  local role_normalized
  role_normalized=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[-_ ]//g')
  case "$role_normalized" in
    ceo|chiefexecutiveofficer) return 0 ;;
    cmo|chiefmarketingofficer) return 0 ;;
    coo|chiefoperatingofficer) return 0 ;;
    headofoperations) return 0 ;;
    contentcreator) return 0 ;;
    marketingspecialist) return 0 ;;
    productmanager) return 0 ;;
    customersupport) return 0 ;;
    *) return 1 ;;
  esac
}

# Map full titles to the canonical role key used in gws_skills_for_role
canonicalize_role() {
  local role_normalized
  role_normalized=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[-_ ]//g')
  case "$role_normalized" in
    ceo|chiefexecutiveofficer) echo "ceo" ;;
    cmo|chiefmarketingofficer) echo "cmo" ;;
    coo|chiefoperatingofficer) echo "coo" ;;
    headofoperations) echo "headofoperations" ;;
    contentcreator) echo "contentcreator" ;;
    marketingspecialist) echo "marketingspecialist" ;;
    productmanager) echo "productmanager" ;;
    customersupport) echo "customersupport" ;;
    *) echo "" ;;
  esac
}

# Role -> required GWS skills (from role-plugin-matrix.md lines 127-134)
gws_skills_for_role() {
  local role_normalized
  role_normalized=$(canonicalize_role "$1")
  case "$role_normalized" in
    ceo)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-calendar-insert gws-drive gws-docs gws-tasks gws-meet gws-shared persona-exec-assistant gws-workflow-meeting-prep gws-workflow-standup-report gws-workflow-weekly-digest"
      ;;
    cmo)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-drive gws-docs gws-sheets gws-forms gws-shared persona-content-creator persona-sales-ops"
      ;;
    coo)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-drive gws-docs gws-sheets gws-tasks gws-shared persona-project-manager"
      ;;
    headofoperations)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-drive gws-docs gws-sheets gws-tasks gws-shared persona-project-manager"
      ;;
    contentcreator)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-calendar gws-calendar-agenda gws-drive gws-drive-upload gws-docs gws-docs-write gws-sheets gws-shared persona-content-creator"
      ;;
    marketingspecialist)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-drive gws-sheets gws-sheets-append gws-forms gws-shared persona-sales-ops"
      ;;
    productmanager)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-triage gws-calendar gws-calendar-agenda gws-calendar-insert gws-drive gws-docs gws-sheets gws-tasks gws-shared persona-project-manager gws-workflow-meeting-prep"
      ;;
    customersupport)
      echo "gws-gmail gws-gmail-send gws-gmail-read gws-gmail-reply gws-gmail-reply-all gws-gmail-forward gws-gmail-triage gws-calendar gws-calendar-agenda gws-docs gws-sheets gws-shared persona-customer-support gws-workflow-email-to-task"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Built-in skills that should NOT be in frontmatter
BUILTIN_SKILLS="paperclip paperclip-create-agent para-memory-files"

# =============================================================================
# Helper: Extract YAML frontmatter from a markdown file
# =============================================================================

extract_frontmatter() {
  # Returns the YAML frontmatter (between --- markers) of a markdown file
  sed -n '1{/^---$/!q};1,/^---$/{/^---$/d;p}' "$1" 2>/dev/null
}

has_frontmatter_at_top() {
  local file="$1"
  [ -f "$file" ] || return 1
  [ "$(head -n 1 "$file" 2>/dev/null)" = "---" ] || return 1
  awk 'NR > 1 && /^---$/ { found = 1; exit } END { exit found ? 0 : 1 }' "$file" 2>/dev/null
}

count_body_lines_after_frontmatter() {
  local file="$1"
  awk '
    BEGIN { delimiters = 0; count = 0 }
    /^---$/ { delimiters++; next }
    delimiters >= 2 && $0 ~ /[^[:space:]]/ { count++ }
    END { print count }
  ' "$file" 2>/dev/null
}

extract_frontmatter_field() {
  # Extract a simple scalar field value from frontmatter
  local file="$1" field="$2"
  extract_frontmatter "$file" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/" || true
}

extract_skills_list() {
  # Extract the skills: list from YAML frontmatter (handles - item format)
  local file="$1"
  local in_skills=false
  extract_frontmatter "$file" | while IFS= read -r line; do
    if echo "$line" | grep -q "^skills:"; then
      in_skills=true
      # Handle inline array: skills: [a, b, c]
      if echo "$line" | grep -q '\['; then
        echo "$line" | sed 's/^skills:[[:space:]]*\[//;s/\]$//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//"
        in_skills=false
      fi
      continue
    fi
    if $in_skills; then
      if echo "$line" | grep -q "^[[:space:]]*-"; then
        echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//"
      elif echo "$line" | grep -q "^[a-zA-Z]"; then
        # Next field started, stop
        break
      fi
    fi
  done
}

count_goals() {
  # Count goals in COMPANY.md frontmatter
  local file="$1"
  local frontmatter
  frontmatter=$(extract_frontmatter "$file")

  # Check for inline array first
  if echo "$frontmatter" | grep -q "^goals:.*\["; then
    echo "$frontmatter" | grep "^goals:" | sed 's/^goals:[[:space:]]*\[//;s/\]$//' | tr ',' '\n' | grep -c '[^[:space:]]'
    return
  fi

  # Count - items after goals: until next field
  echo "$frontmatter" | sed -n '/^goals:/,/^[a-zA-Z]/p' | grep -c "^[[:space:]]*-"
}

# =============================================================================
# Category 1: Required top-level files
# =============================================================================

echo "=== Checking required files ==="

for f in COMPANY.md global/settings.json global/plugins.json .paperclip.yaml; do
  if [ -f "$COMPANY_ROOT/$f" ]; then
    ok "required-files" "$f exists"
  else
    error "required-files" "$f is missing"
  fi
done

for f in README.md LICENSE scripts/setup-secrets.sh; do
  if [ -f "$COMPANY_ROOT/$f" ]; then
    ok "required-files" "$f exists"
  else
    warn "required-files" "$f is missing"
  fi
done

# At least one project
if ls "$COMPANY_ROOT/projects"/*/PROJECT.md &>/dev/null; then
  project_count=$(ls "$COMPANY_ROOT/projects"/*/PROJECT.md 2>/dev/null | wc -l)
  ok "required-files" "$project_count project(s) found"
else
  error "required-files" "No projects found (need at least one projects/*/PROJECT.md)"
fi

# At least one agent
if [ ! -d "$COMPANY_ROOT/agents" ] || [ -z "$(ls "$COMPANY_ROOT/agents/" 2>/dev/null)" ]; then
  error "required-files" "No agents directory or no agents found"
  echo "---"
  echo "RESULT: $ERRORS errors, $WARNINGS warnings"
  exit 1
fi

# =============================================================================
# Category 2: Per-agent required files
# =============================================================================

echo ""
echo "=== Checking per-agent files ==="

AGENT_SLUGS=()
for agent_dir in "$COMPANY_ROOT/agents"/*/; do
  slug=$(basename "$agent_dir")
  AGENT_SLUGS+=("$slug")

  for f in AGENTS.md HEARTBEAT.md SOUL.md; do
    if [ -f "$agent_dir/$f" ]; then
      ok "agent-files" "$slug/$f exists"
    else
      error "agent-files" "$slug/$f is missing"
    fi
  done

  if [ -f "$agent_dir/TOOLS.md" ]; then
    ok "agent-files" "$slug/TOOLS.md exists"
  else
    warn "agent-files" "$slug/TOOLS.md is missing"
  fi

  if [ -f "$agent_dir/runtime/.codex/config.toml" ]; then
    ok "agent-files" "$slug/runtime/.codex/config.toml exists"
  else
    error "agent-files" "$slug/runtime/.codex/config.toml is missing"
  fi

  if [ -d "$agent_dir/runtime/.codex/agents" ]; then
    ok "agent-files" "$slug/runtime/.codex/agents exists"
  else
    error "agent-files" "$slug/runtime/.codex/agents is missing"
  fi
done

# =============================================================================
# Category 3: COMPANY.md frontmatter
# =============================================================================

echo ""
echo "=== Checking COMPANY.md frontmatter ==="

if [ -f "$COMPANY_ROOT/COMPANY.md" ]; then
  fm_schema=$(extract_frontmatter_field "$COMPANY_ROOT/COMPANY.md" "schema")
  fm_name=$(extract_frontmatter_field "$COMPANY_ROOT/COMPANY.md" "name")
  fm_slug=$(extract_frontmatter_field "$COMPANY_ROOT/COMPANY.md" "slug")
  fm_version=$(extract_frontmatter_field "$COMPANY_ROOT/COMPANY.md" "version")

  if [ "$fm_schema" = "agentcompanies/v1" ]; then
    ok "company-frontmatter" "schema is agentcompanies/v1"
  else
    error "company-frontmatter" "schema should be 'agentcompanies/v1', got '${fm_schema:-empty}'"
  fi

  if [ -n "$fm_name" ]; then
    ok "company-frontmatter" "name: $fm_name"
  else
    error "company-frontmatter" "name is missing"
  fi

  if [ -n "$fm_slug" ]; then
    ok "company-frontmatter" "slug: $fm_slug"
  else
    error "company-frontmatter" "slug is missing"
  fi

  if [ -n "$fm_version" ]; then
    ok "company-frontmatter" "version: $fm_version"
  else
    warn "company-frontmatter" "version is missing"
  fi

  goal_count=$(count_goals "$COMPANY_ROOT/COMPANY.md")
  if [ "$goal_count" -ge 2 ] && [ "$goal_count" -le 5 ]; then
    ok "company-frontmatter" "$goal_count goals found"
  elif [ "$goal_count" -eq 0 ]; then
    error "company-frontmatter" "No goals found (need 2-5)"
  else
    warn "company-frontmatter" "$goal_count goals found (recommended: 2-5)"
  fi
fi

# =============================================================================
# Category 3b: Goals directory validation
# =============================================================================

echo ""
echo "=== Checking goals directory ==="

if [ -d "$COMPANY_ROOT/goals" ]; then
  ok "goals" "goals/ directory exists"

  # Recursive goal validation
  validate_goal_dir() {
    local dir="$1"
    local depth="$2"
    local parent_path="$3"

    for goal_dir in "$dir"/*/; do
      [ ! -d "$goal_dir" ] && continue
      local goal_slug
      goal_slug=$(basename "$goal_dir")
      local goal_path="${parent_path}${goal_slug}"
      local goal_file="${goal_dir}GOAL.md"

      if [ ! -f "$goal_file" ]; then
        error "goals" "$goal_path: missing GOAL.md"
        continue
      fi

      # Check title exists in frontmatter
      local title
      title=$(extract_frontmatter_field "$goal_file" "title")
      if [ -n "$title" ]; then
        ok "goals" "$goal_path: has title"
      else
        error "goals" "$goal_path: missing 'title' in frontmatter"
      fi

      # Check ownerAgentSlug reference
      local owner
      owner=$(extract_frontmatter_field "$goal_file" "ownerAgentSlug")
      if [ -n "$owner" ]; then
        if [ -d "$COMPANY_ROOT/agents/$owner" ]; then
          ok "goals" "$goal_path: ownerAgentSlug '$owner' matches agent"
        else
          error "goals" "$goal_path: ownerAgentSlug '$owner' does not match any agent in agents/"
        fi
      fi

      # Check projectSlugs references
      local frontmatter
      frontmatter=$(extract_frontmatter "$goal_file")
      local project_line
      project_line=$(echo "$frontmatter" | grep "^projectSlugs:" || true)
      if [ -n "$project_line" ]; then
        # Parse inline array [slug1, slug2]
        local slugs
        slugs=$(echo "$project_line" | sed 's/^projectSlugs:[[:space:]]*\[//;s/\]$//' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        while IFS= read -r ps; do
          [ -z "$ps" ] && continue
          if [ -d "$COMPANY_ROOT/projects/$ps" ]; then
            ok "goals" "$goal_path: projectSlug '$ps' matches project"
          else
            warn "goals" "$goal_path: projectSlug '$ps' does not match any project in projects/"
          fi
        done <<< "$slugs"
      fi

      # Check nesting depth
      if [ "$depth" -gt 4 ]; then
        error "goals" "$goal_path: exceeds max nesting depth of 4"
      fi

      # Recurse into subgoal directories
      validate_goal_dir "$goal_dir" $((depth + 1)) "${goal_path}/"
    done
  }

  validate_goal_dir "$COMPANY_ROOT/goals" 1 "goals/"

  # Count top-level goals
  local_goal_count=$(find "$COMPANY_ROOT/goals" -maxdepth 2 -name "GOAL.md" | wc -l)
  top_level_goals=$(find "$COMPANY_ROOT/goals" -mindepth 1 -maxdepth 1 -type d | wc -l)
  if [ "$top_level_goals" -ge 2 ] && [ "$top_level_goals" -le 5 ]; then
    ok "goals" "$top_level_goals top-level goals in goals/ directory"
  elif [ "$top_level_goals" -eq 0 ]; then
    error "goals" "goals/ directory is empty (need 2-5 top-level goals)"
  else
    warn "goals" "$top_level_goals top-level goals in goals/ directory (recommended: 2-5)"
  fi
else
  warn "goals" "goals/ directory not found (optional but recommended for rich goal hierarchy)"
fi

# =============================================================================
# Category 4: Agent frontmatter
# =============================================================================

echo ""
echo "=== Checking agent frontmatter ==="

# Build a map of agent slug -> role title for later use
declare -A AGENT_ROLES

for slug in "${AGENT_SLUGS[@]}"; do
  agents_md="$COMPANY_ROOT/agents/$slug/AGENTS.md"
  [ ! -f "$agents_md" ] && continue

  fm_name=$(extract_frontmatter_field "$agents_md" "name")
  fm_title=$(extract_frontmatter_field "$agents_md" "title")
  fm_reports=$(extract_frontmatter "$agents_md" | grep "^reportsTo:" | head -1)

  if has_frontmatter_at_top "$agents_md"; then
    ok "agent-frontmatter" "$slug: frontmatter is at top of AGENTS.md"
  else
    error "agent-frontmatter" "$slug: AGENTS.md does not start with valid top-of-file frontmatter"
  fi

  AGENT_ROLES[$slug]="${fm_title:-$fm_name}"

  if [ -n "$fm_name" ]; then
    ok "agent-frontmatter" "$slug: name='$fm_name'"
  else
    error "agent-frontmatter" "$slug: name is missing in AGENTS.md"
  fi

  if [ -n "$fm_title" ]; then
    ok "agent-frontmatter" "$slug: title='$fm_title'"
  else
    error "agent-frontmatter" "$slug: title is missing in AGENTS.md"
  fi

  if [ -n "$fm_reports" ]; then
    ok "agent-frontmatter" "$slug: reportsTo is present"
  else
    error "agent-frontmatter" "$slug: reportsTo is missing in AGENTS.md (use 'null' for CEO)"
  fi
done

# =============================================================================
# Category 4b: Per-agent Codex runtime defaults
# =============================================================================

echo ""
echo "=== Checking per-agent runtime defaults ==="

for slug in "${AGENT_SLUGS[@]}"; do
  config_toml="$COMPANY_ROOT/agents/$slug/runtime/.codex/config.toml"
  [ ! -f "$config_toml" ] && continue

  if grep -q '^approval_policy[[:space:]]*=' "$config_toml"; then
    ok "runtime-defaults" "$slug: config.toml defines approval_policy"
  else
    error "runtime-defaults" "$slug: config.toml is missing approval_policy"
  fi

  if grep -q '^sandbox_mode[[:space:]]*=' "$config_toml"; then
    ok "runtime-defaults" "$slug: config.toml defines sandbox_mode"
  else
    error "runtime-defaults" "$slug: config.toml is missing sandbox_mode"
  fi
done

# =============================================================================
# Category 5: reportsTo references
# =============================================================================

echo ""
echo "=== Checking reportsTo references ==="

for slug in "${AGENT_SLUGS[@]}"; do
  agents_md="$COMPANY_ROOT/agents/$slug/AGENTS.md"
  [ ! -f "$agents_md" ] && continue

  reports_to=$(extract_frontmatter_field "$agents_md" "reportsTo")
  if [ -n "$reports_to" ] && [ "$reports_to" != "null" ] && [ "$reports_to" != "~" ]; then
    found=false
    for other in "${AGENT_SLUGS[@]}"; do
      if [ "$other" = "$reports_to" ]; then
        found=true
        break
      fi
    done
    if $found; then
      ok "reportsTo" "$slug reports to $reports_to (exists)"
    else
      warn "reportsTo" "$slug reports to '$reports_to' but that agent doesn't exist"
    fi
  fi
done

# =============================================================================
# Category 6: Global plugin install config
# =============================================================================

echo ""
echo "=== Checking global plugin config ==="

if [ -f "$COMPANY_ROOT/global/plugins.json" ]; then
  if jq empty "$COMPANY_ROOT/global/plugins.json" 2>/dev/null; then
    ok "global-plugins" "global/plugins.json is valid JSON"
    global_plugins=$(jq -r '.plugins[]?.name // empty' "$COMPANY_ROOT/global/plugins.json" 2>/dev/null)
    for plugin_key in $global_plugins; do
      if echo "$plugin_key" | grep -qE '^[a-z-]+-plugin@codex-my-marketplace$'; then
        ok "global-plugins" "plugin '$plugin_key' has valid format"
      else
        error "global-plugins" "invalid plugin format '$plugin_key' (expected: {name}-plugin@codex-my-marketplace)"
      fi
    done
  else
    error "global-plugins" "global/plugins.json is not valid JSON"
  fi
fi

# =============================================================================
# Category 7: GWS skill consistency
# =============================================================================

echo ""
echo "=== Checking GWS skill consistency ==="

for slug in "${AGENT_SLUGS[@]}"; do
  role="${AGENT_ROLES[$slug]:-}"
  [ -z "$role" ] && continue

  agents_md="$COMPANY_ROOT/agents/$slug/AGENTS.md"

  if is_gws_eligible "$role"; then
    if [ -f "$agents_md" ]; then
      agent_skills=$(extract_skills_list "$agents_md" | tr '\n' ' ')
      required_gws_skills=$(gws_skills_for_role "$role")

      if [ -n "$required_gws_skills" ]; then
        for gws_skill in $required_gws_skills; do
          if echo " $agent_skills " | grep -q " $gws_skill "; then
            ok "gws-skills" "$slug: has $gws_skill in frontmatter"
          else
            error "gws-skills" "$slug ($role): missing GWS skill '$gws_skill' in AGENTS.md skills: frontmatter"
          fi
        done
      fi
    fi
  else
    true
  fi
done

# =============================================================================
# Category 8: Skill file resolution
# =============================================================================

echo ""
echo "=== Checking skill file resolution ==="

for slug in "${AGENT_SLUGS[@]}"; do
  agents_md="$COMPANY_ROOT/agents/$slug/AGENTS.md"
  [ ! -f "$agents_md" ] && continue

  agent_skills=$(extract_skills_list "$agents_md")
  for skill in $agent_skills; do
    [ -z "$skill" ] && continue

    # Check for built-in skills that shouldn't be listed
    for builtin in $BUILTIN_SKILLS; do
      if [ "$skill" = "$builtin" ]; then
        warn "skill-builtin" "$slug: '$skill' is a built-in skill and should not be in frontmatter"
      fi
    done

    # Check skill directory exists
    if [ -f "$COMPANY_ROOT/skills/$skill/SKILL.md" ]; then
      ok "skill-files" "$slug: skills/$skill/SKILL.md exists"

      skill_file="$COMPANY_ROOT/skills/$skill/SKILL.md"
      skill_fm_name=$(extract_frontmatter_field "$skill_file" "name")
      skill_fm_desc=$(extract_frontmatter_field "$skill_file" "description")
      skill_body_lines=$(count_body_lines_after_frontmatter "$skill_file")

      if has_frontmatter_at_top "$skill_file"; then
        ok "skill-format" "$skill: frontmatter is at top of SKILL.md"
      else
        error "skill-format" "$skill: SKILL.md does not start with valid top-of-file frontmatter"
      fi

      if [ "$skill_fm_name" = "$skill" ]; then
        ok "skill-format" "$skill: frontmatter name matches directory"
      else
        error "skill-format" "$skill: frontmatter name should be '$skill', got '${skill_fm_name:-empty}'"
      fi

      if [ -n "$skill_fm_desc" ]; then
        ok "skill-format" "$skill: has description in frontmatter"
      else
        error "skill-format" "$skill: missing description in frontmatter"
      fi

      if [ "$skill_body_lines" -gt 0 ]; then
        ok "skill-format" "$skill: has markdown body"
      else
        error "skill-format" "$skill: SKILL.md has no body content after frontmatter"
      fi
    else
      error "skill-files" "$slug: skills/$skill/SKILL.md is missing (skill '$skill' listed in frontmatter but no SKILL.md found)"
    fi
  done
done

# =============================================================================
# Category 9: Project structure
# =============================================================================

echo ""
echo "=== Checking project structure ==="

if [ -d "$COMPANY_ROOT/projects" ]; then
  for project_md in "$COMPANY_ROOT/projects"/*/PROJECT.md; do
    [ ! -f "$project_md" ] && continue
    project_slug=$(basename "$(dirname "$project_md")")

    fm_name=$(extract_frontmatter_field "$project_md" "name")
    fm_slug=$(extract_frontmatter_field "$project_md" "slug")
    fm_owner=$(extract_frontmatter_field "$project_md" "owner")

    if [ -n "$fm_name" ]; then
      ok "project-structure" "$project_slug: has name"
    else
      error "project-structure" "$project_slug: PROJECT.md missing 'name' in frontmatter"
    fi

    if [ -n "$fm_slug" ]; then
      ok "project-structure" "$project_slug: has slug"
    else
      error "project-structure" "$project_slug: PROJECT.md missing 'slug' in frontmatter"
    fi

    if [ -n "$fm_owner" ]; then
      ok "project-structure" "$project_slug: has owner ($fm_owner)"
    else
      error "project-structure" "$project_slug: PROJECT.md missing 'owner' in frontmatter"
    fi
  done
fi

# =============================================================================
# Category 10: Task structure
# =============================================================================

echo ""
echo "=== Checking task structure ==="

# Tasks under projects
for task_md in "$COMPANY_ROOT/projects"/*/tasks/*/TASK.md; do
  [ ! -f "$task_md" ] && continue
  task_path="${task_md#$COMPANY_ROOT/}"

  fm_project=$(extract_frontmatter_field "$task_md" "project")
  fm_assignee=$(extract_frontmatter_field "$task_md" "assignee")
  fm_priority=$(extract_frontmatter_field "$task_md" "priority")

  if [ -n "$fm_project" ]; then
    ok "task-structure" "$task_path: has project"
  else
    error "task-structure" "$task_path: missing 'project' in frontmatter"
  fi

  if [ -n "$fm_assignee" ]; then
    ok "task-structure" "$task_path: has assignee ($fm_assignee)"
  else
    error "task-structure" "$task_path: missing 'assignee' in frontmatter"
  fi

  if [ -n "$fm_priority" ]; then
    if echo "$fm_priority" | grep -qE '^(critical|high|medium|low)$'; then
      ok "task-structure" "$task_path: has valid priority ($fm_priority)"
    else
      error "task-structure" "$task_path: invalid priority '$fm_priority' — must be critical, high, medium, or low"
    fi
  else
    error "task-structure" "$task_path: missing 'priority' in frontmatter (use critical, high, medium, or low)"
  fi
done

# Check task ordering prefixes (NN- convention) and global uniqueness
ALL_TASK_NUMBERS=""

for task_dir in "$COMPANY_ROOT/projects"/*/tasks/*/; do
  [ ! -d "$task_dir" ] && continue
  dir_name=$(basename "$task_dir")
  task_path="${task_dir#$COMPANY_ROOT/}"
  if echo "$dir_name" | grep -qE '^[0-9]{2}-'; then
    task_num=$(echo "$dir_name" | grep -oE '^[0-9]{2}')
    ALL_TASK_NUMBERS="$ALL_TASK_NUMBERS $task_num:$task_path"
    ok "task-ordering" "$task_path uses NN- ordering prefix ($task_num)"
  else
    error "task-ordering" "$task_path missing NN- ordering prefix (e.g., 01-$dir_name). Tasks import in alphabetical order — use numeric prefixes to control sequence."
  fi
done

for task_dir in "$COMPANY_ROOT/tasks"/*/; do
  [ ! -d "$task_dir" ] && continue
  dir_name=$(basename "$task_dir")
  task_path="${task_dir#$COMPANY_ROOT/}"
  if echo "$dir_name" | grep -qE '^[0-9]{2}-'; then
    task_num=$(echo "$dir_name" | grep -oE '^[0-9]{2}')
    ALL_TASK_NUMBERS="$ALL_TASK_NUMBERS $task_num:$task_path"
    ok "task-ordering" "$task_path uses NN- ordering prefix ($task_num)"
  else
    error "task-ordering" "$task_path missing NN- ordering prefix (e.g., 01-$dir_name)"
  fi
done

# Check for duplicate task numbers (must be globally unique across entire package)
if [ -n "$ALL_TASK_NUMBERS" ]; then
  seen_numbers=""
  for entry in $ALL_TASK_NUMBERS; do
    num="${entry%%:*}"
    path="${entry#*:}"
    if echo " $seen_numbers " | grep -q " $num "; then
      error "task-ordering" "Duplicate task number $num at $path — numbering must be globally unique across the entire package"
    else
      seen_numbers="$seen_numbers $num"
    fi
  done

  # Check for gaps in the sequence
  sorted_nums=$(echo "$ALL_TASK_NUMBERS" | tr ' ' '\n' | grep -oE '^[0-9]+' | sort -n | uniq)
  expected=1
  for num in $sorted_nums; do
    actual=$((10#$num))
    if [ "$actual" -ne "$expected" ]; then
      warn "task-ordering" "Gap in task numbering: expected $expected but next is $actual"
      expected=$((actual + 1))
    else
      expected=$((expected + 1))
    fi
  done
fi

# Top-level tasks should NOT have project field, and must have valid priority
for task_md in "$COMPANY_ROOT/tasks"/*/TASK.md; do
  [ ! -f "$task_md" ] && continue
  task_path="${task_md#$COMPANY_ROOT/}"

  fm_project=$(extract_frontmatter_field "$task_md" "project")
  if [ -n "$fm_project" ]; then
    warn "task-structure" "$task_path: top-level task has 'project' field (should be under projects/ instead)"
  fi

  fm_priority=$(extract_frontmatter_field "$task_md" "priority")
  if [ -n "$fm_priority" ]; then
    if echo "$fm_priority" | grep -qE '^(critical|high|medium|low)$'; then
      ok "task-structure" "$task_path: has valid priority ($fm_priority)"
    else
      error "task-structure" "$task_path: invalid priority '$fm_priority' — must be critical, high, medium, or low"
    fi
  else
    error "task-structure" "$task_path: missing 'priority' in frontmatter (use critical, high, medium, or low)"
  fi
done

# =============================================================================
# Category 11: Codex config consistency
# =============================================================================

echo ""
echo "=== Checking Codex config consistency ==="

for slug in "${AGENT_SLUGS[@]}"; do
  config_toml="$COMPANY_ROOT/agents/$slug/runtime/.codex/config.toml"
  [ ! -f "$config_toml" ] && continue

  if grep -q '^\[mcp_servers\.' "$config_toml"; then
    ok "codex-config" "$slug: config.toml defines one or more MCP servers"
  else
    ok "codex-config" "$slug: config.toml has no MCP server definitions"
  fi
done

# =============================================================================
# Category 12: Subagent validation
# =============================================================================

echo ""
echo "=== Checking subagents ==="

for slug in "${AGENT_SLUGS[@]}"; do
  sa_dir="$COMPANY_ROOT/agents/$slug/runtime/.codex/agents"
  [ ! -d "$sa_dir" ] && continue

  for sa_file in "$sa_dir"/*.toml; do
    [ ! -f "$sa_file" ] && continue
    sa_name=$(basename "$sa_file" .toml)

    sa_declared_name=$(grep -E '^name[[:space:]]*=' "$sa_file" | head -1 | sed 's/^name[[:space:]]*=[[:space:]]*//' | sed 's/^"//;s/"$//' || true)
    sa_declared_desc=$(grep -E '^description[[:space:]]*=' "$sa_file" | head -1 | sed 's/^description[[:space:]]*=[[:space:]]*//' | sed 's/^"//;s/"$//' || true)

    if [ -n "$sa_declared_name" ]; then
      ok "subagents" "$slug/$sa_name: has name"
    else
      error "subagents" "$slug/$sa_name: missing name in TOML"
    fi

    if [ -n "$sa_declared_desc" ]; then
      ok "subagents" "$slug/$sa_name: has description"
    else
      error "subagents" "$slug/$sa_name: missing description in TOML (Codex uses this to decide when to delegate)"
    fi

    if grep -q '^developer_instructions[[:space:]]*=[[:space:]]*"""' "$sa_file"; then
      ok "subagents" "$slug/$sa_name: has developer_instructions block"
    else
      error "subagents" "$slug/$sa_name: missing developer_instructions block"
    fi

    if grep -q '^model[[:space:]]*=' "$sa_file"; then
      ok "subagents" "$slug/$sa_name: has model"
    else
      warn "subagents" "$slug/$sa_name: missing model (Codex may fall back to defaults)"
    fi
  done
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "---"
echo "RESULT: $ERRORS errors, $WARNINGS warnings"

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "Fix the ERROR items above and re-run this script."
  exit 1
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo ""
    echo "No errors found. $WARNINGS warnings to review (optional)."
  else
    echo ""
    echo "All checks passed."
  fi
  exit 0
fi
