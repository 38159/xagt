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

**`xagt` — the interactive session, which acts.** What you type is *carried
out*, not merely answered: the session has the same tools the executor does,
bounded to the directory you started it in.

```
> the tests in internal/api are failing, fix them

  turn 1: grep({"pattern":"func Test","path":"internal/api"})
    ↳ 12ms · internal/api/serve_test.go:14: func TestServeDrains (+6 lines)
  turn 1: shell({"command":"go test ./internal/api/"})
    ↳ 4.1s · FAIL github.com/x/internal/api 4.084s (+22 lines)
  checkpoint: pre-run state stashed as 30d099c1b3b7
  turn 1: edit_file({"path":"internal/api/serve.go", …})
    ↳ 3ms · replaced 1 occurrence(s) in /home/me/x/internal/api/serve.go

● Fixed: serve() closed the listener before draining. Tests pass.
```

Every call is narrated on both sides — what was attempted, then what came
back and how long it took — so a produced file's location is on screen
whether or not the model repeats it, and a slow step never looks like a hung
one. Paths in those lines are clickable in terminals that support OSC 8
links.

A question is still just answered — the model calls no tools when it needs
none — and `/ask` guarantees it; `/tools off` (or `--no-tools`) turns acting
off for the session. Every action lands in an audit log under `.xagt/`, and a
git checkpoint is taken before the first change of each turn, so anything it
did can be undone.

**`xagt run` — the autonomous executor.** One task in, executed to completion
with tools (files, shell, MCP servers, skills, long-term memory) and no
approval prompts; autonomy is bounded by scope (`--yolo read|workspace|full`),
a turn/time budget and an audit log, with optional cross-check gates
(`--plan-check`, `--final-review`). The executor can fan work out to
parallel subagents (the `agents_run` tool): each gets the same tools and
workspace with its own smaller budget, and cannot delegate further. The same executor is exposed by
`xagt serve` as an OpenAI-compatible HTTP API plus an async task API, and by
`xagt mcp-server` as an MCP tool (`run_task`) for other agents.

**Multimodal.** Attach images, videos and audio for analysis — each media
prompt is routed automatically to the first configured agent that declares
the matching capability (`vision` / `video` / `audio`) — and generate
images, videos and speech with `xagt gen`.

```sh
xagt                            # interactive session — tools run unasked
xagt --repl                     # same session, tool actions ask y/n first
xagt --continue                 # reopen the most recent saved conversation
xagt "Is it safe to share one http.Client across goroutines?"
git diff | xagt "Review this change for bugs."
xagt "what does this diagram show? @architecture.png"   # image analysis
xagt "summarise what happens in @demo.mp4"              # video analysis
xagt "transcribe @standup.mp3, list action items"       # audio analysis
xagt gen image "a red panda reading a book, watercolor" # text-to-image
xagt gen video "waves rolling onto a beach at dusk"     # text-to-video
xagt gen speech --voice Cherry "Welcome to the meeting" # text-to-speech
xagt --cross-review "..."       # two agents cross-check each other
xagt run --yolo workspace "..." # autonomous executor, no approvals
xagt run --repl "..."           # same, but every tool action asks y/n first
xagt update                     # self-update to the latest release
```

The interactive session keeps the conversation as context, saves it under
`~/.xagt/sessions` (continue any with `/resume`), streams token counts live
and takes slash commands (Tab completes them): `/help` `/status` `/cost`
`/ask` `/tools` `/agent` `/model` `/effort` `/mcp` `/skills` `/run` `/init`
`/diff` `/review` `/resume` `/attach` `/paste` `/compact` `/clear` `/exit`
(`--continue` / `--resume ID` reopen a saved conversation from the command
line). Multi-line clipboard pastes insert lines instead of submitting
(bracketed paste), `@path` in a message inlines that file, `/attach`
queues files for the next message (`--attach PATH` for one-shot prompts),
and `/paste` captures the OS clipboard (a screenshot is delegated to a
vision agent for analysis immediately). Attachments cover plain text,
`.docx` (built in) and `.pdf` (via `pdftotext` when installed), plus media:

* **Images** (`.png` `.jpg` `.jpeg` `.gif` `.webp` `.bmp`, ≤ 10 MB) go to
  an agent with `vision = true`.
* **Videos** (`.mp4` `.mov` `.avi` `.mkv` `.webm`) go whole (≤ 50 MB) to an
  agent with `video = true`; without one — or over the cap — xagt samples
  up to 8 frames with ffmpeg (auto-installed on first need) and sends them
  to any vision agent instead, and says so.
* **Audio** (`.mp3` `.wav` `.m4a` `.aac` `.flac` `.ogg` `.opus`, ≤ 10 MB)
  goes to an agent with `audio = true` (an omni model).

Declare a capable agent once and it is used automatically whenever matching
media is attached; an explicitly selected agent that lacks the flag refuses
the prompt with a clear error instead of being silently rerouted. The
session banner lists what each kind of work will reach, so the routing is
visible before anything is attached:

```
xagt v0.0.16 — qwen/qwen3.7-max
text   qwen/qwen3.7-max · qwen-vl/qwen3-vl-plus · qwen-omni/qwen3-omni-flash
image  qwen-vl/qwen3-vl-plus · qwen-omni/qwen3-omni-flash
video  qwen-vl/qwen3-vl-plus
audio  qwen-omni/qwen3-omni-flash
gen    img wan2.2-t2i-flash · vid wan2.2-t2v-plus · tts qwen3-tts-flash
```

```toml
[[agent]]
name     = "qwen-vl"           # image + video analysis
provider = "qwen"
apikey   = "sk-..."
model    = "qwen3-vl-plus"
priority = "secondary"
vision   = true
video    = true

[[agent]]
name     = "qwen-omni"         # audio (+ image/video) analysis
provider = "qwen"
apikey   = "sk-..."
model    = "qwen3-omni-flash"
priority = "secondary"
vision   = true
video    = true
audio    = true
```

**What the agent can do.** Read (`read_file` with numbered lines,
`list_dir`, `glob` with `**`, `grep` over file contents), write
(`write_file`, `edit_file` singly or as an atomic batch, `mkdir`,
`move_file`, `delete_file`), deliver (`download_file`, which saves a finished
file to your download folder), run (`shell`, with `background=true` plus
`shell_output` / `shell_kill` for servers and watchers), plan
(`update_plan`, shown in the terminal as it changes), delegate
(`agents_run`), remember (`memory_*`, `skill`) and anything an MCP server
adds.

Reads and writes are confined to the working directory. `--read-root PATH`
(or `[tools] read_roots`) widens reading when a project legitimately needs a
sibling checkout; `--yolo full` lifts the boundary entirely and is meant for
a container. The one exception is `download_file`: it writes to your download
folder and nowhere else, under a name that must be a single file name, never
overwriting — and the file it delivers is read under the same boundary as
everything else.

**Two capabilities stay closed until asked for**, because the authority you
delegate covers what *you* asked for — not instructions that arrive inside a
web page or a README the agent was told to read:

```sh
xagt --allow-net       # web_fetch, web_search
xagt --allow-computer  # screenshot, read_image, clipboard, open a file, notify
```

`[web]` and `[computer]` tables enable them permanently; `--allow-computer`
adds mouse and keyboard control only when the `input` group is named
explicitly. A screenshot is saved and then described by a `vision = true`
agent, since a tool result is text. Browser automation is configuration
rather than code — point an `[[mcp]]` block at Playwright MCP.

**`xagt gen` — media generation.** Text-to-image, text-to-video and
text-to-speech through DashScope's native generation endpoints, using the
same config: the first `qwen` / `qwen-cn` agent's `apikey` (or
`--agent NAME`). Image and video jobs are asynchronous on the platform —
xagt submits the task, narrates progress and downloads the result when it
finishes (result URLs expire within a day, so the file on disk is the
deliverable).

```sh
xagt gen image  "a lighthouse in a storm"            # default wan2.2-t2i-flash
xagt gen image  --model qwen-image --size 1328*1328 -n 2 "…"
xagt gen video  "time-lapse of clouds over mountains" # default wan2.2-t2v-plus
xagt gen speech --voice Cherry "Hello from xagt"      # default qwen3-tts-flash
```

Generation models are separate from chat models — the agent's `model` field
is not used by `xagt gen`; pick one with `--model`.

**Produced files arrive like downloads.** A file xagt makes *for you* goes to
your operating system's download folder rather than whatever directory the
session started in — `~/Downloads` on macOS and Windows, the freedesktop
`XDG_DOWNLOAD_DIR` on Linux — and opens in the default application, the way a
browser download does. That covers `xagt gen` output and anything the agent
hands over with the `download_file` tool (a picture, a chart, an export;
project files still go into the working directory with `write_file`).

An existing file is never replaced: a second `rabbit.svg` becomes
`rabbit-1.svg`, since that folder is full of files you are about to open. The
saved path always prints on stdout — as a clickable link at a terminal, and as
a bare path when the output is piped, so `xagt gen image "…" | xargs open`
still works.

```toml
[downloads]
# dir  = "~/Downloads"   # default: the OS folder; XAGT_DOWNLOAD_DIR overrides
open = true              # open each file the agent delivers
```

`--out` sends a generated file elsewhere and `--no-open` leaves it closed.
`[downloads] open` applies to the agent's own deliveries and additionally
requires OS control (`--allow-computer` or `[computer]`): saving a file you
asked for is delivery, but handing a model-authored file to the desktop's
default handler is the machine capability, and it is gated like one.

The prompt is a readline-style editor over the whole message, however many
lines it runs to and however wide the terminal: a sentence longer than the
screen wraps into the rows it needs and stays editable there, with no
continuation marker added to what you typed. Enter sends; Enter with any
modifier — Shift, Ctrl or Alt, on terminals that can report one — plus
Ctrl+J and a trailing backslash start a new line. Arrows move the cursor,
Up/Down step between the message's own lines before reaching for the
history, Ctrl+A/E and Home/End jump to line start/end, Alt+B/F and
Ctrl/Alt+arrows move by words, Ctrl+W/K/U delete word/to-end/to-start,
Ctrl+R reverse-searches past prompts, ESC ESC rewinds the last exchange for
editing, Shift+Tab toggles the approval mode, Ctrl+L clears the screen, and
Tab completes `/commands` and `@paths`. `!CMD` runs a shell command and
queues its output as context; `#NOTE` writes to the project's long-term
memory; `?` shows the command list.

The session quits only via `/exit`, Ctrl+C or Ctrl+Z — ESC never quits,
and a bare `exit`/`quit` asks "did you mean /exit? [y/N]" locally first —
y quits, n sends the word to the model as an ordinary prompt. A bare `xagt` runs `/run` and `/init` tool actions without
asking (the skip-permissions default); start with `--repl` to approve each
action with y/n. While a submission runs it shows a progress line naming the
step in flight, with elapsed time and tokens received so far. It stays up for
the whole turn, so the stretches between output are visibly alive:

```
⠹ shell… (3m 9s · ↓ 7.5k tokens)
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
curl -o- https://raw.githubusercontent.com/38159/xagt/main/install.sh | XAGT_VERSION=v0.0.16 bash
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
version with `$env:XAGT_VERSION = 'v0.0.16'` before running; change the
location with `$env:XAGT_DIR`.

Verify:

```sh
xagt --version   # → xagt v0.0.16
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
