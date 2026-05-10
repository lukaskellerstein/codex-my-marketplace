# Runtime Configuration Reference

Runtime config is split into two scopes: global (all agents) and per-agent.

Codex resolves state in layers: the Codex home (`~/.codex` or `/paperclip/.codex` in Docker) holds shared auth, config, and installed skills/plugins, while the per-agent workspace can contain a local `.codex/config.toml` and `.codex/agents/*.toml` that apply when Codex runs in that workspace.

## Global Config (`global/`)

Processed once at container startup by the Docker entrypoint. Affects all agents.

### `global/config.toml`

Shared Codex bootstrap defaults copied into `/paperclip/.codex/config.toml` at container startup.

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

### `global/plugins.json`

Marketplace and plugin installation. Installs binaries globally so any agent can enable them.

```json
{
  "marketplaces": [
    {
      "source": "lukaskellerstein/codex-my-marketplace",
      "scope": "user"
    }
  ],
  "plugins": [
    { "name": "dev-tools-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "office-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "infra-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "media-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "design-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "web-design-plugin@codex-my-marketplace", "scope": "user" },
    { "name": "company-plugin@codex-my-marketplace", "scope": "user" }
  ]
}
```

Only include plugins that at least one agent will use.

## Per-Agent Config (`agents/{slug}/runtime/.codex/`)

### `runtime/.codex/config.toml`

Codex runtime defaults for the individual agent workspace.

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
 
[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest"]
```

Use this file for Codex-native workspace behavior:
- approval mode
- sandbox mode
- workspace-local MCP server definitions
- other Codex settings that should apply when the agent's CWD is the workspace root

### `runtime/.codex/agents/*.toml` (Subagents)

Codex subagent definitions. Discovered from the active Codex runtime state.

Source: `agents/{slug}/runtime/.codex/agents/*.toml`
Deployed to: `<workspace>/.codex/agents/*.toml`

```toml
name = "code-reviewer"
description = "Reviews code for quality and security. Never modifies code."

model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "read-only"

developer_instructions = """
You are a senior code reviewer. Report findings with file paths and line numbers.
"""
```

Use subagents for quick in-session tasks (review, test, search). Use Paperclip task delegation for tracked, cross-agent work.

## Available Plugins (marketplace)

| Plugin | What it provides | MCP servers |
|--------|-----------------|-------------|
| `dev-tools-plugin` | Git workflows, dead-code analysis, dependency updates, docs generation | — |
| `office-plugin` | PPTX presentations, DOCX documents, XLSX spreadsheets | — |
| `infra-plugin` | Kubernetes/GKE, Istio, Helm, Terraform, Traefik, auth | — |
| `media-plugin` | AI image/video/music/speech generation, stock photos, SVG icons, charts, diagrams | media-mcp, ElevenLabs, Mermaid Chart, Playwright |
| `design-plugin` | Creative direction, styleguides, aesthetic strategy, design review | — |
| `web-design-plugin` | End-to-end website/webapp design, visual testing. Depends on: design-plugin, media-plugin | Playwright |
| `company-plugin` | Shipping (Zasilkovna, DHL), payments (Stripe) | DHL API Assistant, Stripe |

Plugin installation and agent env inputs are Paperclip-specific fidelity and belong in `.paperclip.yaml`, not in the Codex-native workspace files.
