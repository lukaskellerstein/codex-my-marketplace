# codex-my-marketplace

A Codex plugin marketplace containing reusable plugins, skills, agents, commands, and hooks for software delivery, design, documentation, media, and infrastructure work.

## Repository Layout

- `.agents/plugins/marketplace.json` defines the marketplace catalog for Codex.
- `plugins/<plugin-name>/` contains each plugin implementation.
- `plugins/<plugin-name>/.codex-plugin/plugin.json` contains the Codex plugin manifest for that plugin.

## Plugins

### [dev-tools-plugin](plugins/dev-tools-plugin)

General developer tooling for git workflows, dependency management, dead-code analysis, and spec synchronization.

- Skills: `git-pr`, `dead-code`, `update-dependencies`, `sync-spec-kit`
- Agents: `dead-code-analyzer`, `sync-spec-kit-agent`

### [documentation-plugin](plugins/documentation-plugin)

Documentation and Office document workflows for diagrams, graphs, and professional DOCX, PPTX, and XLSX output.

- Skills: `update-docs`, `update-feature-docs`, `update-readme`, `graph-generation`, `pptx`, `docx`, `xlsx`

### [infra-plugin](plugins/infra-plugin)

Infrastructure management for Kubernetes, Istio, Helm, Terraform, Traefik, and auth-related workflows.

- Skills: `auth`, `helm`, `istio`, `kubernetes`, `terraform`, `traefik`

### [media-plugin](plugins/media-plugin)

AI-assisted media workflows for images, icons, music, speech, sourcing, and video generation.

- Skills: `image-generation`, `image-sourcing`, `video-generation`, `music-generation`, `speech-generation`, `icon-library`
- Agents: `media-director`
- Commands: `media-assets`, `media-generate`

### [design-plugin](plugins/design-plugin)

Creative direction and design quality workflows for styleguides, aesthetics, media prompt craft, review, and design systems.

- Skills: `styleguide`, `frontend-aesthetics`, `media-prompt-craft`, `design-review`, `design-system`
- Agents: `design-director`
- Commands: `design`

### [web-design-plugin](plugins/web-design-plugin)

End-to-end website and webapp design workflow for Codex, from brief to implementation, with documentation, scaffold generation, parallel page building, and visual iteration.

- Skills: `animation-system`, `page-architecture`, `css-architecture`, `variation`
- Agents: `design-doc-foundation`, `design-doc-animation`, `design-doc-data`, `design-doc-media`, `design-doc-pages`, `scaffold-builder`, `page-builder`, `assembler`, `variation-generator`, `visual-fixer-page`, `visual-fixer-app`
- Commands: `web-design`, `hook-test`
- Hooks: yes

## Environment Variables

This repository currently defines plugin runtime environment variables only for `media-plugin`.

### dev-tools-plugin

No plugin-specific environment variables are currently required.

### documentation-plugin

No plugin-specific environment variables are currently required.

### infra-plugin

No plugin-specific environment variables are currently required.

### media-plugin

The `media-plugin` reads these variables from [`plugins/media-plugin/.mcp.json`](plugins/media-plugin/.mcp.json):

| Variable | Required | Purpose |
| --- | --- | --- |
| `GEMINI_API_KEY` | Yes | Required by the `media-mcp` server for image, video, and music generation workflows. |
| `ELEVENLABS_API_KEY` | Optional | Required when using ElevenLabs-backed speech and voice features. |
| `MEDIA_OUTPUT_DIR` | Recommended | Directory where generated or downloaded media files should be written. If unset, some workflows fall back to the current directory or return large base64 payloads instead of file paths. |

#### macOS and Linux

Temporary for the current terminal session:

```bash
export GEMINI_API_KEY="your-gemini-api-key"
export ELEVENLABS_API_KEY="your-elevenlabs-api-key"
export MEDIA_OUTPUT_DIR="$HOME/media-output"
```

Persistent for future `zsh` sessions:

```bash
echo 'export GEMINI_API_KEY="your-gemini-api-key"' >> ~/.zshrc
echo 'export ELEVENLABS_API_KEY="your-elevenlabs-api-key"' >> ~/.zshrc
echo 'export MEDIA_OUTPUT_DIR="$HOME/media-output"' >> ~/.zshrc
source ~/.zshrc
```

Persistent for future `bash` sessions:

```bash
echo 'export GEMINI_API_KEY="your-gemini-api-key"' >> ~/.bashrc
echo 'export ELEVENLABS_API_KEY="your-elevenlabs-api-key"' >> ~/.bashrc
echo 'export MEDIA_OUTPUT_DIR="$HOME/media-output"' >> ~/.bashrc
source ~/.bashrc
```

#### Windows PowerShell

Temporary for the current PowerShell session:

```powershell
$env:GEMINI_API_KEY = "your-gemini-api-key"
$env:ELEVENLABS_API_KEY = "your-elevenlabs-api-key"
$env:MEDIA_OUTPUT_DIR = "$HOME\media-output"
```

Persistent for future PowerShell sessions:

```powershell
[System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your-gemini-api-key", "User")
[System.Environment]::SetEnvironmentVariable("ELEVENLABS_API_KEY", "your-elevenlabs-api-key", "User")
[System.Environment]::SetEnvironmentVariable("MEDIA_OUTPUT_DIR", "$HOME\media-output", "User")
```

After setting persistent values, open a new terminal session.

#### Windows Command Prompt

Temporary for the current Command Prompt session:

```cmd
set GEMINI_API_KEY=your-gemini-api-key
set ELEVENLABS_API_KEY=your-elevenlabs-api-key
set MEDIA_OUTPUT_DIR=%USERPROFILE%\media-output
```

Persistent for future Command Prompt sessions:

```cmd
setx GEMINI_API_KEY "your-gemini-api-key"
setx ELEVENLABS_API_KEY "your-elevenlabs-api-key"
setx MEDIA_OUTPUT_DIR "%USERPROFILE%\media-output"
```

After `setx`, open a new terminal session before using the plugin.

### design-plugin

No plugin-specific environment variables are currently required.

### web-design-plugin

No plugin-specific environment variables are currently required.

## Marketplace Metadata

The local marketplace entrypoint is:

`./.agents/plugins/marketplace.json`

Each plugin listed there resolves to `./plugins/<plugin-name>` and contains its own Codex manifest in:

`./plugins/<plugin-name>/.codex-plugin/plugin.json`

## Notes

- This repository is the Codex adaptation of the original `claude-my-marketplace` content.
- Source prompts, skills, and orchestration files were carried over into the Codex plugin structure and indexed through local marketplace metadata.
