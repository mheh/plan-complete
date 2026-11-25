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

## Quick start

1. **A model server.** Any fill-in-the-middle model behind `llama-server` (llama.cpp) works: Qwen2.5-Coder,
   Qwen3-Coder and similar. The defaults expect it on port 8012:

   ```sh
   llama-server -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF --port 8012
   ```

2. **The editor.**
   - VS Code: download `plan-complete-<platform>.vsix` from the
     [Releases](https://github.com/mheh/plan-complete/releases) page and run
     `code --install-extension plan-complete-<platform>.vsix`. The server is inside the extension.
   - Neovim: see [Neovim](#neovim-012-or-later) below.

3. **Opt a repository in.** Open it, click `Plan: off` in the status bar, and pick *Enable in this workspace*
   (Neovim: `:PlanCompleteEnable`; a terminal: `plan-complete enable`). This writes `.plan-complete.json` and a
   starter `PLAN.md`, and opens the plan.

Write a step into `PLAN.md`, open the file that it names, and type.

Nothing else needs a setting. The rest of this page is for when you want to change something.

## Install

### VS Code (1.91 or later)

The `.vsix` of your platform holds the server binary: `darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`,
`alpine-x64`, `alpine-arm64`, `win32-x64`. The plain `plan-complete.vsix` has no binary, for any other platform.

The extension looks for the server in this order:

1. the `planComplete.serverPath` setting,
2. the binary inside the extension,
3. `plan-complete` on `PATH`.

The status bar item shows the state, and a click opens the menu:

| Status bar | Meaning |
|---|---|
| `Plan: on` | Completions follow the plan. The tooltip names it. |
| `Plan: no model` | The repository is on, but the last request to the model server failed. The tooltip says why. |
| `Plan: off` | The tooltip gives the reason: `no .plan-complete.json`, `no PLAN.md`, `turned off`. |

The menu and the command palette (*Plan Complete: …*) have: *Enable in This Workspace*, *Toggle for This
Workspace*, *Open the Plan*, *Open the Repository Settings*, *Open the Global Settings*, *Restart Server*.
VS Code remembers the toggle for each workspace.

Turn off other inline-completion extensions (Copilot and others) for the workspace, or VS Code may show
theirs. `Option+\` (`Alt+\`) asks for a suggestion by hand. `Tab` accepts.

### Neovim (0.12 or later)

Get the binary from the Releases page (`plan-complete-<platform>.tar.gz`), or build it, and put it on `PATH`.

```lua
vim.opt.rtp:append("/full/path/to/plan-complete/editors/nvim")
require("plan_complete").setup({
  -- cmd = { "/full/path/to/plan-complete", "serve" },   -- default: plan-complete on PATH
  -- filetypes = { "swift", "python" },                  -- default: every file type
  -- settings = { model = "qwen2.5-coder" },             -- overrides the settings files
})
```

`Tab` accepts, `M-]` and `M-[` cycle. `:PlanCompleteEnable` opts the project in, `:PlanCompleteToggle` turns
it off or on for the session, `:PlanCompleteStatus` shows the state, and
`require("plan_complete").statusline()` gives `Plan: on`, `Plan: no model` or `Plan: off (reason)`.
See `editors/nvim/README.md`.

### Build from source

Swift 6 on macOS 14 or later, Linux, or Windows. CI builds and tests all three (Swift 6.2 and 6.4).

```sh
git clone https://github.com/mheh/plan-complete.git
cd plan-complete
swift build -c release
ln -s "$PWD/.build/release/plan-complete" /usr/local/bin/plan-complete

cd editors/vscode && npm install && npm run package   # a .vsix with no binary
```

### The command line

```sh
plan-complete enable [DIR]     # opt a repository in
plan-complete config [DIR]     # the settings in effect, and the files they come from
plan-complete probe Sources/Foo.swift:42:9             # one completion; LINE and COL are 1-based
plan-complete probe Sources/Foo.swift:42:9 --prompt    # print the exact prompt
plan-complete probe Sources/Foo.swift:42:9 --no-guide  # compare without the plan
```

`probe` prints `context: PLAN.md#<heading>` for the sections that it used. When the repository is not opted
in, `probe` prints `off: <reason>` and exits with 3. `--no-guide` runs anyway, with no plan.

## Settings

Three layers. Each one sets only the fields that it names, and the later one wins:

1. The global file, for your model server: `~/.config/plan-complete/config.json`
   (or `$XDG_CONFIG_HOME/plan-complete/config.json`; on Windows, `%APPDATA%\plan-complete\config.json`).
   *Plan Complete: Open the Global Settings* creates it.
2. `<repo>/.plan-complete.json`, for one repository. Its presence opts the repository in.
3. Editor overrides: VS Code `planComplete.settings`, Neovim `setup({ settings = … })`.

Both files are JSON with comments and trailing commas. The file that *Enable* writes lists every field at its
default, commented out. In VS Code the files have completion and hover text for every field. A change takes
effect when you save the file in the editor; after a change from outside, restart the server
(*Plan Complete: Restart Server*, or `:lsp restart`).

For example, a model behind a proxy on another machine, in the global file:

```jsonc
{
  "baseURL": "http://192.168.1.20:8080",
  "model": "qwen2.5-coder-7b",
}
```

| Field | Default | Meaning |
|---|---|---|
| `baseURL` | `http://127.0.0.1:8012` | Server root. A trailing `/v1` is fine. |
| `provider` | `llama-infill` | `llama-infill` (`/infill`, the server builds the prompt) or `openai-fim` (any `/v1/completions`, Qwen Coder prompt format) |
| `model` | `default` | Model name sent with each request. A proxy such as llama-swap uses it to pick the model. |
| `apiKey` | none | Sent as `Authorization: Bearer` |
| `guide` | `PLAN.md` | The plan: one Markdown file, or a folder whose `.md` files are all read. Repository file only. |
| `guideTokenBudget` | `1200` | Most plan tokens in one prompt |
| `maxTokens` / `maxLines` | `64` / `12` | Size of one completion |
| `prefixLines` / `suffixLines` | `80` / `40` | Lines of code before and after the cursor |
| `timeoutMs` / `debounceMs` | `4000` / `60` | Time limit of a model request; wait in the server before one |
| `useGuide` / `useScope` | `true` / `true` | Turn the plan, or the scope summary and the editor context, off |

`context` is what the editor gathers from the real language server for each request:

| Field | Default | Meaning |
|---|---|---|
| `context.signature` | `true` | The signature of the call at the cursor (VS Code) |
| `context.timeoutMs` | `100` | Longest wait for the language server |
| `context.tokenBudget` | `300` | Most tokens of editor context in one prompt |

`scoring` is the points that a plan section earns. It is subject to change between versions:

| Field | Default | A section earns it when |
|---|---|---|
| `scoring.glob` | `10` | its front-matter `files` match the edited file |
| `scoring.file` | `8` | it names the edited file |
| `scoring.symbol` | `4` | a front-matter symbol is near the cursor (each) |
| `scoring.codeSpan` | `2` | a name in a code span is near the cursor (each, three at most) |
| `scoring.heading` | `2` | a word of its heading is near the cursor |
| `scoring.words` | `3` | times the share of its words that are near the cursor |

## The plan

### Where it comes from

The server runs only in a repository that opts in:

1. `<repo>/.plan-complete.json` exists. *Enable* writes it; an empty `{}` is enough. With no file the server stays quiet.
2. The plan exists: `PLAN.md` at the repository root, or the file or folder that `guide` in
   `.plan-complete.json` names. A folder needs at least one `.md` file. With no plan the server stays quiet.
3. The workspace toggle is on (VS Code: the status bar menu; Neovim: `:PlanCompleteToggle`).

Quiet means every completion request returns at once, with no model call. The editor still starts the
server, so a plan written later turns it on within a second, with no restart.

Only `.plan-complete.json` in the repository can name the plan. `guide` in the global file or in the
editor settings is ignored, and a `guide` outside the repository (absolute, `~`, or `..`) falls back to
`PLAN.md`.

The server rereads the plan at most once a second, so the next suggestion after a save uses the new text.

The editor stores nothing: the plan is a plain file in your repository. Whatever writes it steers the
completions: you, Claude, or another agent.

### Writing it

Plain Markdown. No front-matter or special syntax. Text inside `<!-- -->` is not read, so notes to yourself
stay out of the prompt.

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
| `Plan: off (no .plan-complete.json)` | *Enable in This Workspace*, `:PlanCompleteEnable`, or `plan-complete enable` |
| `Plan: off (no PLAN.md)` | Write `PLAN.md`, or name the plan with `guide` in `.plan-complete.json` |
| `Plan: no model`, `no model server at …` | Nothing answers at `baseURL`: start llama-server, or set `baseURL` in the global settings |
| `Plan: no model`, `… has no /infill endpoint` | The server is not llama-server: set `"provider": "openai-fim"` |
| `Plan: no model`, `… did not answer in 4000 ms` | The model is still loading, or is too slow: wait, or raise `timeoutMs` |
| `the settings could not be read` | `plan-complete config` names the field that is wrong |
| `"plan-complete" is not on PATH` | Install the `.vsix` of your platform, or set `planComplete.serverPath` to the full path |
| No ghost text | Check the status bar; `Option+\`; the menu → *Show the log*; turn off other completion extensions |
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
