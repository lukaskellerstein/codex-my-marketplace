# Company Package Structure

A company package follows the Agent Companies specification (`agentcompanies/v1`).

```
{company-slug}/
├── COMPANY.md                          # Company definition (name, goals, metadata)
├── goals/                              # Rich goal hierarchy (optional, overrides COMPANY.md goals)
│   └── {goal-slug}/
│       ├── GOAL.md                     # Goal definition (frontmatter + description body)
│       └── {subgoal-slug}/
│           └── GOAL.md                 # Subgoal (nested folder = child goal)
├── agents/
│   └── {agent-slug}/
│       ├── AGENTS.md                   # Agent identity, role, instructions (mandatory)
│       ├── HEARTBEAT.md                # Heartbeat execution protocol
│       ├── SOUL.md                     # Personality and voice
│       ├── TOOLS.md                    # Agent tool reference — plugins, MCP servers, usage guidelines
│       └── runtime/                    # Per-agent Codex runtime config
│           ├── settings.json           # Permissions, enabledPlugins, env vars
│           ├── mcp.json                # MCP server definitions
│           └── agents/                 # Codex subagent definitions
│               └── *.md
├── projects/
│   └── {project-slug}/
│       ├── PROJECT.md                  # Project definition
│       └── tasks/
│           └── {NN-task-slug}/TASK.md  # Starter task (NN = 01, 02, ... for ordering)
├── tasks/
│   └── {NN-task-slug}/TASK.md          # Company-level starter tasks (NN prefix for ordering)
├── skills/
│   └── {skill-slug}/SKILL.md           # Shared skills (one per skill referenced in any AGENTS.md)
├── scripts/
│   └── setup-secrets.sh                # Post-import script to create company secrets via API
├── global/                             # Shared runtime config (all agents)
│   ├── settings.json                   # Global Codex bootstrap settings (baseline)
│   └── plugins.json                    # Marketplace and plugin installation
├── .paperclip.yaml                     # Vendor extension (adapter, budget, env)
├── README.md                           # Setup guide and org overview
└── LICENSE                             # MIT default
```

## Spec Reference

Full spec: `docs/companies/companies-spec.md`
Web: https://agentcompanies.io/specification

## Frontmatter Examples

### COMPANY.md

**Goals are mandatory (2-5).** Each must be specific and measurable. Never omit goals.

Goals are the top of the Paperclip work hierarchy: **Goal → Projects → Issues**. On import, each goal string becomes a `company`-level goal object with status `active`. Projects link to goals, and issues inherit `goalId` from their project — so all work traces back to these objectives.

```yaml
name: Company Name
description: What this company does
slug: company-slug
schema: agentcompanies/v1
version: 1.0.0
goals:
  - Launch MVP product with core features and user onboarding
  - Acquire first 50 paying customers within 90 days
  - Establish automated CI/CD pipeline with test coverage above 80%
  - Build content marketing engine producing 2+ blog posts per week
```

### goals/ directory (optional)

When present, the `goals/` directory provides a rich goal hierarchy with subgoals, ownership, and project linkage. It overrides the simple `goals: string[]` in COMPANY.md.

Each goal is a folder containing a `GOAL.md` file. Subgoals are nested subfolders within their parent goal's folder. This mirrors the pattern used by agents, projects, and tasks.

**Example structure:**
```
goals/
├── launch-mvp/
│   ├── GOAL.md
│   ├── build-auth/
│   │   └── GOAL.md
│   └── build-onboarding/
│       └── GOAL.md
└── acquire-customers/
    └── GOAL.md
```

**GOAL.md format:**
```markdown
---
title: Launch MVP product with core features
level: company
status: active
ownerAgentSlug: cto
projectSlugs: [mvp-backend, mvp-frontend]
---

Ship authentication, onboarding, and core workflow. Success criteria: a functional product that users can sign up for and use daily.
```

**Subgoal GOAL.md** (at `goals/launch-mvp/build-auth/GOAL.md`):
```markdown
---
title: Build authentication system
level: team
ownerAgentSlug: backend-lead
projectSlugs: [mvp-backend]
---

Implement email/password and OAuth login, session management, and RBAC.
```

**Field rules:**
- Slug is derived from the folder name (not in frontmatter)
- `title` — required
- `level` — one of: `company`, `team`, `agent`, `task`. Optional, auto-assigned by folder depth (root = company, depth 1 = team, depth 2 = agent, depth 3+ = task)
- `status` — one of: `planned`, `active`, `achieved`, `cancelled`. Optional, defaults to `active`
- `ownerAgentSlug` — optional, references an agent slug from the package
- `projectSlugs` — optional, references project slugs from the package
- Body contains the goal description (rich markdown allowed)
- Subgoals are subfolders, max 4 levels of nesting

### AGENTS.md

```yaml
name: CEO
title: Chief Executive Officer
reportsTo: null
skills:
  - strategy-review
  - delegation-playbook
```

Body contains the agent's instructions.

**Skill resolution rule:** Every skill in `skills:` must have a matching `skills/<shortname>/SKILL.md` in the package. Do NOT list Paperclip built-in skills (`paperclip`, `paperclip-create-agent`, `para-memory-files`) — they are available automatically at runtime and listing them causes import warnings.

### PROJECT.md

```yaml
name: Project Name
description: What this project delivers
slug: project-slug
owner: agent-slug
```

### TASK.md

```yaml
name: Task Name
assignee: agent-slug
project: project-slug
```

Body contains the task description.

## Deployment Summary

| Source (in package) | Destination (in container) | Scope |
|---|---|---|
| `global/settings.json` | `/paperclip/.codex/config.toml` or bootstrap defaults | All agents |
| `global/plugins.json` | `/docker-init/codex/plugins.json` | All agents |
| `agents/{slug}/runtime/settings.json` | Agent runtime plugin/permission config | One agent |
| `agents/{slug}/runtime/mcp.json` | `<workspace>/.mcp.json` | One agent |
| `agents/{slug}/runtime/agents/*.md` | Codex subagent definitions | One agent |

Where `<workspace>` is `/paperclip/instances/default/workspaces/{agentId}/`.

## Global Config Setup

The `global/` files are NOT imported via the company import API. They must be placed in the Paperclip repo and mounted into the Docker container:

1. Copy `global/settings.json` and `global/plugins.json` into `.company/codex/` in the Paperclip repo root
2. Rebuild/restart the container (the volume mount is already configured in docker-compose.yml)
