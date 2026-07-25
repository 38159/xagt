# xagt

A CLI agent that fronts any number of **OpenAI-compatible LLM APIs** — OpenAI,
Qwen (DashScope compatible mode), a local gateway — defined in one TOML config
file.

## Overview

**Default mode — failover.** The `primary` agent answers; a `secondary` agent
is only asked when every agent before it failed.

```
prompt ──▶ primary answers ──(only on failure)──▶ secondary answers
```

**`--cross-review` mode.** Two agents answer the same prompt, each reviews the
other's answer, and one arbitrates the disagreements into a final consolidated
answer.

```
prompt ──┬──▶ agent A answers ──▶ agent B reviews A ──┐
         │                                            ├──▶ arbiter verdict
         └──▶ agent B answers ──▶ agent A reviews B ──┘
```

**`xagt run` — the autonomous executor.** One task in, executed to completion
with tools (files, shell, MCP servers, skills, long-term memory) and no
approval prompts; autonomy is bounded by scope (`--yolo read|workspace|full`),
a turn/time budget and an audit log, with optional cross-check gates
(`--plan-check`, `--final-review`). The executor can fan work out to
parallel subagents (the `agents_run` tool): each gets the same tools and
workspace with its own smaller budget, and cannot delegate further. The same executor is exposed by
`xagt serve` as an OpenAI-compatible HTTP API plus an async task API, and by
`xagt mcp-server` as an MCP tool (`run_task`) for other agents.

```sh
xagt                            # interactive session — tools run unasked
xagt --repl                     # same session, tool actions ask y/n first
xagt --continue                 # reopen the most recent saved conversation
xagt "Is it safe to share one http.Client across goroutines?"
git diff | xagt "Review this change for bugs."
xagt --cross-review "..."       # two agents cross-check each other
xagt run --yolo workspace "..." # autonomous executor, no approvals
xagt run --repl "..."           # same, but every tool action asks y/n first
xagt update                     # self-update to the latest release
```

The interactive session keeps the conversation as context, saves it under
`~/.xagt/sessions` (continue any with `/resume`), streams token counts live
and takes slash commands (Tab completes them): `/help` `/status` `/cost`
`/agent` `/model` `/effort` `/mcp` `/skills` `/run` `/init` `/diff`
`/review` `/resume` `/attach` `/paste` `/compact` `/clear` `/exit`
(`--continue` / `--resume ID` reopen a saved conversation from the command
line). Multi-line clipboard pastes insert lines instead of submitting
(bracketed paste), `@path` in a message inlines that file, `/attach`
queues files for the next message (`--attach PATH` for one-shot prompts),
and `/paste` captures the OS clipboard. Attachments cover plain text,
`.docx` (built in) and `.pdf` (via `pdftotext` when installed). Images
(`.png` `.jpg` `.gif` `.webp` `.bmp`) are sent to a vision-capable agent —
declare one and it is used automatically whenever an image is attached:

```toml
[[agent]]
name     = "qwen-vl"
provider = "qwen"
apikey   = "sk-..."
model    = "qwen3-vl-plus"
priority = "secondary"
vision   = true
```

The prompt is a readline-style editor: arrows move the cursor, Ctrl+A/E
jump to line start/end, Alt+B/F move by words, Ctrl+W/K/U delete
word/to-end/to-start, Up/Down recall past prompts, Ctrl+R
reverse-searches them, ESC ESC rewinds the last exchange for editing,
Shift+Tab toggles the approval mode, Ctrl+L clears the screen, a trailing
backslash continues the line, and Tab completes `/commands` and `@paths`.
`!CMD` runs a shell command and queues its output as context; `#NOTE`
writes to the project's long-term memory; `?` shows the command list.

The session quits only via `/exit`, Ctrl+C or Ctrl+Z — ESC never quits,
and a bare `exit`/`quit` asks "did you mean /exit? [y/N]" locally instead
of going to the model. A bare `xagt` runs `/run` and `/init` tool actions without
asking (the skip-permissions default); start with `--repl` to approve each
action with y/n. While a submission runs it shows a progress line — spinner,
elapsed time, and tokens received so far:

```
⠹ running… (3m 9s · ↓ 7.5k tokens)
```

## Install

### Linux / macOS (amd64, arm64)

```sh
curl -o- https://raw.githubusercontent.com/38159/xagt/main/install.sh | bash
```

The installer picks the **latest release tag**, installs its prebuilt binary
to `~/.xagt/bin/xagt`, seeds a config template at `~/.xagt/xagt.toml` (an
existing file is never touched), and adds `PATH` / `XAGT_CONFIG` lines to your
shell profile.

To pin a specific version:

```sh
curl -o- https://raw.githubusercontent.com/38159/xagt/main/install.sh | XAGT_VERSION=v0.0.3 bash
```

Set `XAGT_DIR=/opt/xagt` to change the install location.

### Windows (amd64, arm64)

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/38159/xagt/main/install.ps1 | iex
```

The installer puts `xagt.exe` in `%USERPROFILE%\.xagt\bin`, seeds a config
template at `%USERPROFILE%\.xagt\xagt.toml`, and adds the bin directory and
`XAGT_CONFIG` to your user environment (open a new terminal afterwards). Pin a
version with `$env:XAGT_VERSION = 'v0.0.3'` before running; change the
location with `$env:XAGT_DIR`.

Verify:

```sh
xagt --version   # → xagt v0.0.3
```

## Update / uninstall

An installed xagt updates itself:

```sh
xagt update      # check the latest tag, swap the binary atomically
```

Re-running `install.sh` also works — when xagt is already installed it shows
the current version and asks **[u]pdate / [r]emove / [q]uit** on the terminal.
An update lands wherever the binary already lives (system-wide installs
included); removal deletes only the binary and keeps the config. Without a
terminal, updating is the default.

## Configure

`~/.xagt/xagt.toml` (or the file `XAGT_CONFIG` points at) holds one
`[[agent]]` table per OpenAI-compatible endpoint:

```toml
timeout = 300              # per-call timeout, seconds (XAGT_TIMEOUT_SEC overrides)

[[agent]]
name     = "my-gpt"
provider = "openai"        # openai / qwen / qwen-cn fill in apiurl automatically
apikey   = "sk-..."
model    = "gpt-4.1"
priority = "primary"

[[agent]]
name     = "qwen"
provider = "qwen"
apikey   = "sk-..."
model    = "qwen3.7-plus"
priority = "secondary"     # only asked when the primary failed
```

The file holds API keys — keep it mode `600`. It is read on every run, so
edits need no reload.

## Versions

This repository is a **binary-only distribution channel**. Releases are git
tags (`v0.0.1`, `v0.0.2`, …); each tag carries the prebuilt binaries —
`dist/xagt-{linux,darwin}-{amd64,arm64}.tar.gz` and
`dist/xagt-windows-{amd64,arm64}.zip`. `main` holds only this page,
`install.sh` and `install.ps1`.
