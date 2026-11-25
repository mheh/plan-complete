# plan-complete

Inline completions (ghost text) that follow your plan.

Write the plan in a plain `PLAN.md` at the root of the repository, by hand or with an agent such as
Claude. A small language server picks the sections of the plan that fit the file and the cursor, adds
what encloses the cursor (for example the `init` declarations when you type `self.init(`), and asks a
fill-in-the-middle model for the completion. The server parses no language, so it works next to
sourcekit-lsp, pyright, or any other language server, in VS Code and Neovim.

```
PLAN.md  ──▶  plan-complete serve  ──▶  llama-server /infill (or any /v1/completions)
(you or Claude)  (picks plan sections + scope)   (Qwen Coder, other FIM models)
                         ▲
                  VS Code / Neovim
               textDocument/inlineCompletion
```

## Requirements

- Swift 6 on macOS 14 or later, Linux, or Windows. CI builds and tests all three (Swift 6.2 and 6.4).
- A fill-in-the-middle model behind an HTTP server:
  - `llama-server` (llama.cpp) with a coder model that has FIM tokens. Qwen2.5-Coder, Qwen3-Coder and
    similar models work. For example:
    `llama-server -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF --port 8012`
  - Or any OpenAI-style `/v1/completions` server with the `openai-fim` provider (Qwen prompt format).
- VS Code 1.91 or later, or Neovim 0.12 or later.

## Install

### 1. Build the server

```sh
git clone https://github.com/mheh/plan-complete.git
cd plan-complete
swift build -c release
# optional: put it on PATH
ln -s "$PWD/.build/release/plan-complete" /usr/local/bin/plan-complete
```

### 2. Point it at your model, once, and opt a repository in

`~/.config/plan-complete/config.json` (or `$XDG_CONFIG_HOME/plan-complete/config.json`;
on Windows, `%APPDATA%\plan-complete\config.json`):

```json
{
  "baseURL": "http://127.0.0.1:8012",
  "model": "qwen2.5-coder-1.5b"
}
```

With a llama-server on `127.0.0.1:8012` you can skip this file: those are the defaults.

Then, in each repository where you want completions:

```sh
echo '{}' > .plan-complete.json   # opt in; the plan is PLAN.md
```

### 3a. VS Code

Download `plan-complete-<version>.vsix` from the GitHub Releases page, or build it:

```sh
cd editors/vscode && npm install && npm run package
```

Then:

```sh
code --install-extension plan-complete-0.1.0.vsix
```

In your user settings (`Cmd+Shift+P` → *Preferences: Open User Settings (JSON)*):

```json
"planComplete.serverPath": "/full/path/to/plan-complete/.build/release/plan-complete"
```

`serverPath` can stay `plan-complete` when the binary is on `PATH` (VS Code started from the Dock may
not see your shell's `PATH`, so a full path is safer). After a change, run *Plan Complete: Restart Server*.

Turn off other inline-completion extensions (Copilot and others) for the workspace while you test, or
VS Code may show theirs. `Option+\` (`Alt+\`) asks for a suggestion by hand. `Tab` accepts.

The status bar shows `Plan: on` or `Plan: off`, with the reason in its tooltip (`no .plan-complete.json`,
`no PLAN.md`, `turned off`). Click it, or run *Plan Complete: Toggle for This Workspace*, to turn it
off or on for this workspace; VS Code remembers the choice.

### 3b. Neovim (0.12+)

```lua
vim.opt.rtp:append("/full/path/to/plan-complete/editors/nvim")
require("plan_complete").setup({
  cmd = { "/full/path/to/plan-complete/.build/release/plan-complete", "serve" },
  -- filetypes = { "swift", "python" },        -- default: every file type
  -- settings = { model = "qwen2.5-coder" },   -- overrides the config files
})
```

`Tab` accepts, `M-]` and `M-[` cycle. `:PlanCompleteToggle` turns it off or on for the session,
`:PlanCompleteStatus` shows the state, and `require("plan_complete").statusline()` gives `Plan: on` or
`Plan: off (reason)` for your statusline. See `editors/nvim/README.md`.

### 4. Check it with no editor

```sh
cd your-project
plan-complete probe Sources/Foo.swift:42:9            # LINE and COL are 1-based
plan-complete probe Sources/Foo.swift:42:9 --prompt   # print the exact prompt
plan-complete probe Sources/Foo.swift:42:9 --no-guide # compare without the plan
```

`probe` prints `context: PLAN.md#<heading>` for the sections that it used.
When the repository is not opted in, `probe` prints `off: <reason>` and exits with 3. `--no-guide` runs
anyway, with no plan, to compare.
## Settings

Three layers. Each one sets only the fields that it names:

1. `~/.config/plan-complete/config.json`: global, for your model server.
2. `<repo>/.plan-complete.json`: one repository, for example another plan location.
3. Editor overrides: VS Code `planComplete.settings`, Neovim `setup({ settings = … })`.

`.plan-complete.json` is the server's file, not a VS Code settings file, and its presence opts the
repository in. The VS Code settings are only `planComplete.serverPath` (where the binary is),
`planComplete.settings` (the overrides), and `planComplete.passSignatureHelp` (send the real language
server's signature help at the cursor).

| Field | Default | Meaning |
|---|---|---|
| `baseURL` | `http://127.0.0.1:8012` | Server root. A trailing `/v1` is fine. |
| `provider` | `llama-infill` | `llama-infill` (`/infill`, server builds the prompt) or `openai-fim` (`/v1/completions`) |
| `model` | `default` | Model name sent with each request (a proxy such as llama-swap uses it to pick the model) |
| `apiKey` | none | Sent as `Authorization: Bearer` |
| `guide` | `PLAN.md` | The plan: one Markdown file, or a folder whose `.md` files are all read. Repo file only |
| `guideTokenBudget` | `1200` | Most plan tokens in one prompt |
| `maxTokens` / `maxLines` | `64` / `12` | Size of one completion |
| `prefixLines` / `suffixLines` | `80` / `40` | Lines of code before and after the cursor |
| `timeoutMs` / `debounceMs` | `4000` / `60` | Request limit, server-side wait before a request |
| `useGuide` / `useScope` | `true` / `true` | Turn the plan or the scope summary off |

## The plan

### Where it comes from

The server runs only in a repository that opts in:

1. `<repo>/.plan-complete.json` exists. `{}` is enough. With no file the server stays quiet.
2. The plan exists: `PLAN.md` at the repository root, or the file or folder that `guide` in
   `.plan-complete.json` names. A folder needs at least one `.md` file. With no plan the server stays quiet.
3. The workspace toggle is on (VS Code: click the status bar item; Neovim: `:PlanCompleteToggle`).

Quiet means every completion request returns at once, with no model call. The editor still starts the
server, so a plan written later turns it on within a second, with no restart.

Only `.plan-complete.json` in the repository can name the plan. `guide` in the global file or in the
editor settings is ignored, and a `guide` outside the repository (absolute, `~`, or `..`) falls back to
`PLAN.md`.

The server rereads the plan at most once a second, so the next suggestion after a save uses the new text.

The editor stores nothing: the plan is a plain file in your repository. Whatever writes it steers the
completions: you, Claude, or another agent.

### Writing it

Plain Markdown. No front-matter or special syntax:

```markdown
# Response cache

## Step 1: ResponseCache in Sources/Net/Cache.swift

`actor ResponseCache` holds at most `capacity` items; the default capacity is 100.

- `func store(_ data: Data, for key: URL) async` inserts, then calls `evictIfNeeded()`.
- `private func evictIfNeeded()` removes the oldest key in `order` while `items.count > capacity`.
- No force unwraps.
```

How sections are picked:

- Each `## ` or `### ` section is one chunk.
- A section that names the file you edit (`Sources/Net/Cache.swift`, or just `Cache.swift`) ranks first.
- Names in `code spans` count when they are near the cursor.
- Other shared words count a little. Sections with no tie to the file or the cursor are left out while
  any section matches.
- About 1200 tokens of plan go into one prompt.

What helps most: exact signatures, names, defaults, and rules, in code spans, under a heading that
names the file. A small model copies exact text and ignores long explanations.

Optional, for a large plan: a YAML front-matter block at the top of a file applies to all its sections.

```markdown
---
files: ["Sources/Net/**"]
symbols: [ResponseCache, store]
priority: 1
---
```

### Editing it while you work

- **By hand:** open `PLAN.md` in a split next to the code, change a signature or a rule, save. The next
  suggestion follows it.
- **With Claude Code in VS Code:** open Claude Code (the `anthropic.claude-code` extension, or `claude`
  in the built-in terminal) in the project and ask it, for example:

  > Update PLAN.md: the next step adds `func reset()` to ResponseCache in Sources/Net/Cache.swift, which
  > empties `items` and `order`. One `## ` section that names the file, with the exact signatures.

- **With Claude Code in Neovim:** the same with `claude` in `:terminal` or a tmux split at the project root.

## What to expect

- A suggestion takes about 1 s with a 9B model on a GPU; Neovim adds its own 200 ms wait.
- The plan steers the model, it does not control it. Short starts (`/// The `, `func `) follow the plan
  closely; once you have typed your own words, the model follows them.
- `self.init(`, `foo.bar(`: the server finds the declarations of the name in the current file, and stops the
  completion where the call closes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `spawn plan-complete ENOENT` | Set `planComplete.serverPath` to the full path, then *Restart Server* |
| `Plan: off (no .plan-complete.json)` | `echo '{}' > .plan-complete.json` at the repository root |
| `Plan: off (no PLAN.md)` | Write `PLAN.md`, or name the plan with `guide` in `.plan-complete.json` |
| No ghost text | Check the status bar; `Option+\`; *View → Output → Plan Complete*; turn off other completion extensions |
| `Could not connect to the server` | Nothing at `baseURL`: start llama-server, or set `baseURL` in the global config |
| Slow first suggestion | The model server is loading the model |
| Odd suggestion | `plan-complete probe FILE:LINE:COL --prompt` shows what the model saw |
| Detailed log | Start the editor with `PLAN_COMPLETE_LOG=/tmp/pc.log` in the environment |
| The file changed in many places on save | That is your formatter (`editor.formatOnSave`), not this extension |

## Try it on the sample

`examples/sample` has a Swift file, a Python file, a `PLAN.md`, and a `.plan-complete.json`. With a model server running:

```sh
cd examples/sample
../../.build/release/plan-complete probe Sources/Net/Cache.swift:13:19   # self.init( → capacity: 100)
../../.build/release/plan-complete probe Sources/Net/Cache.swift:16:10   # func → store(_:for:) from the plan
../../.build/release/plan-complete probe Sources/Net/Cache.swift:16:10 --no-guide
../../.build/release/plan-complete probe tools/cache.py:7:14             # self. → items[key] = value …
```

Or open `examples/sample` in VS Code and type at those spots.

## Development

```sh
swift test
node scripts/lsp-smoke.mjs .build/debug/plan-complete examples/sample Sources/Net/Cache.swift 12 18
PC_BIN=$PWD/.build/debug/plan-complete PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua examples/sample/Sources/Net/Cache.swift
cd editors/vscode && PC_BIN=$PWD/../../.build/debug/plan-complete node test/run.js ../../examples/sample/Sources/Net/Cache.swift 12 18
```

`PLAN.md` holds the development plan of this repository, and is also its guide.

## License

MIT
