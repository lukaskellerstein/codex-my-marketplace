# codex-my-marketplace

A Codex plugin marketplace containing the same plugin families, skills, and agent content as `claude-my-marketplace`, packaged for Codex plugin manifests and marketplace metadata.

This marketplace bundles **8 plugins** covering business operations, developer workflows, office documents, infrastructure, media generation, design, web design, and AI company planning.

## Repository Layout

- `.agents/plugins/marketplace.json` defines the Codex marketplace catalog.
- `plugins/<plugin-name>/` contains each plugin implementation.
- `plugins/<plugin-name>/.codex-plugin/plugin.json` contains the Codex plugin manifest for that plugin.
- `plugins/<plugin-name>/.mcp.json` contains plugin MCP server definitions when required.

## Plugins

### [company-plugin](plugins/company-plugin)

Business operations workflows for Stripe payments and Zasilkovna shipping.

- Skills: `stripe`, `zasilkovna`

### [dev-tools-plugin](plugins/dev-tools-plugin)

Developer tooling for git workflows, dependency updates, dead-code analysis, spec synchronization, and documentation maintenance.

- Skills: `git-pr`, `dead-code`, `update-dependencies`, `sync-spec-kit`, `update-docs`, `update-feature-docs`, `update-readme`
- Agents: `dead-code-analyzer`, `sync-spec-kit-agent`

### [office-plugin](plugins/office-plugin)

Office document generation for PowerPoint, Word, and Excel deliverables.

- Skills: `pptx`, `docx`, `xlsx`

### [infra-plugin](plugins/infra-plugin)

Infrastructure management for Kubernetes, Istio, Helm, Terraform, Traefik, and auth-related workflows.

- Skills: `auth`, `helm`, `istio`, `kubernetes`, `terraform`, `traefik`

### [media-plugin](plugins/media-plugin)

AI-assisted media workflows for images, icons, music, speech, sourcing, SVG craft, charts, graphs, diagrams, and video generation.

- Skills: `image-generation`, `image-sourcing`, `video-generation`, `music-generation`, `speech-generation`, `icon-library`, `graph-generation`, `svg-mastery`
- Agents: `media-director`
- Commands: `media-assets`, `media-generate`

### [design-plugin](plugins/design-plugin)

Creative direction and design quality workflows for styleguides, aesthetics, media prompt craft, review, and design systems.

- Skills: `styleguide`, `frontend-aesthetics`, `media-prompt-craft`, `design-review`, `design-system`
- Agents: `design-director`
- Commands: `design`

### [web-design-plugin](plugins/web-design-plugin)

End-to-end website and webapp design workflow for Codex, from brief to implementation, with documentation, scaffold generation, page building, and visual iteration.

- Skills: `animation-system`, `page-architecture`, `css-architecture`, `variation`
- Agents: `design-doc-foundation`, `design-doc-animation`, `design-doc-data`, `design-doc-media`, `design-doc-pages`, `scaffold-builder`, `page-builder`, `assembler`, `variation-generator`, `visual-fixer-page`, `visual-fixer-app`
- Commands: `web-design`, `hook-test`
- Hooks: yes

### [paperclip-plugin](plugins/paperclip-plugin)

AI company planning workflows for Paperclip-style company design, work planning, and infrastructure planning.

- Skills: `company`, `work-planning`, `infrastructure-planning`
- Agents: `agent-creator`, `skill-creator`, `subagent-creator`

## Environment Variables

Plugin runtime environment variables are currently required for `company-plugin` and `media-plugin`.

### company-plugin

The `company-plugin` reads these variables from [`plugins/company-plugin/.mcp.json`](plugins/company-plugin/.mcp.json):

| Variable | Required | Purpose |
| --- | --- | --- |
| `STRIPE_SECRET_KEY` | Yes | Required by the Stripe MCP server for payments, subscriptions, invoicing, and related operations. |
| `ZASILKOVNA_API_KEY` | Skill-dependent | Used by the Zasilkovna skill when calling the shipping API from its helper scripts. |

### media-plugin

The `media-plugin` reads these variables from [`plugins/media-plugin/.mcp.json`](plugins/media-plugin/.mcp.json):

| Variable | Required | Purpose |
| --- | --- | --- |
| `GEMINI_API_KEY` | Yes | Required by the `media-mcp` server for image, video, and music generation workflows. |
| `ELEVENLABS_API_KEY` | Optional | Required when using ElevenLabs-backed speech and voice features. |
| `MEDIA_OUTPUT_DIR` | Recommended | Directory where generated or downloaded media files should be written. |

## Marketplace Metadata

The local marketplace entrypoint is:

`./.agents/plugins/marketplace.json`

Each plugin listed there resolves to `./plugins/<plugin-name>` and contains its own Codex manifest in:

`./plugins/<plugin-name>/.codex-plugin/plugin.json`

## Notes

- This repository now mirrors the Claude marketplace plugin set for Codex.
- The old `documentation-plugin` split has been retired in favor of the original Claude layout: office skills live in `office-plugin`, documentation update skills live in `dev-tools-plugin`, and graph/diagram media skills live in `media-plugin`.
