# plan-complete

Inline completions (ghost text) that follow a plan.

You, or an agent such as Claude, write a short guide in `docs/guide/*.md`. A small language server
picks the guide sections that fit the file and the cursor, adds what encloses the cursor (for example
the `init` declarations when you type `self.init(`), and asks a fill-in-the-middle model for the
completion. The server parses no language, so it works next to sourcekit-lsp, pyright, or any other
language server, in VS Code and Neovim.

```
docs/guide/*.md  ──▶  plan-complete serve  ──▶  llama-server /infill (or any /v1/completions)
 (you or Claude)       (picks guide + scope)      (Qwen Coder, other FIM models)
                              ▲
                       VS Code / Neovim
                    textDocument/inlineCompletion
```

## Requirements

- macOS 14 or later with Swift 6 (Xcode 16 or later). Linux is not tested.
- A fill-in-the-middle model behind an HTTP server:
  - `llama-server` (llama.cpp) with a coder model that has FIM tokens. Qwen2.5-Coder, Qwen3-Coder and
    similar models work. For example:
    `llama-server -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF --port 8012`
  - Or any OpenAI-style `/v1/completions` server with the `openai-fim` provider (Qwen prompt format).
- VS Code 1.91 or later, or Neovim 0.12 or later.

## Install

### 1. Build the server

```sh
git clone https://github.com/<owner>/plan-complete.git
cd plan-complete
swift build -c release
# optional: put it on PATH
ln -s "$PWD/.build/release/plan-complete" /usr/local/bin/plan-complete
```

### 2. Point it at your model

Create `.plan-complete.json` at the root of the project that you edit:

```json
{
  "baseURL": "http://127.0.0.1:8012",
  "provider": "llama-infill",
  "model": "qwen2.5-coder-1.5b"
}
```

| Field | Default | Meaning |
|---|---|---|
| `baseURL` | `http://127.0.0.1:8012` | Server root. A trailing `/v1` is fine. |
| `provider` | `llama-infill` | `llama-infill` (`/infill`, server builds the prompt) or `openai-fim` (`/v1/completions`) |
| `model` | `default` | Model name sent with each request (a proxy such as llama-swap uses it to pick the model) |
| `apiKey` | none | Sent as `Authorization: Bearer` |
| `guideDir` | `docs/guide` | Folder of guide files, relative to the project root |
| `guideTokenBudget` | `1200` | Most guide tokens in one prompt |
| `maxTokens` / `maxLines` | `64` / `12` | Size of one completion |
| `prefixLines` / `suffixLines` | `80` / `40` | Lines of code before and after the cursor |
| `timeoutMs` / `debounceMs` | `4000` / `60` | Request limit, server-side wait before a request |
| `useGuide` / `useScope` | `true` / `true` | Turn the guide or the scope summary off |

Check it with no editor:

```sh
cd your-project
plan-complete probe Sources/Foo.swift:42:9            # LINE and COL are 1-based
plan-complete probe Sources/Foo.swift:42:9 --prompt   # print the exact prompt
plan-complete probe Sources/Foo.swift:42:9 --no-guide # compare without the guide
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

Other settings: `planComplete.settings` overrides fields of `.plan-complete.json`, and
`planComplete.passSignatureHelp` sends the real language server's signature help at the cursor as context.

Turn off other inline-completion extensions (Copilot and others) for the workspace while you test, or
VS Code may show theirs. `Option+\` (`Alt+\`) asks for a suggestion by hand. `Tab` accepts.

### 3b. Neovim (0.12+)

```lua
vim.opt.rtp:append("/full/path/to/plan-complete/editors/nvim")
require("plan_complete").setup({
  cmd = { "/full/path/to/plan-complete/.build/release/plan-complete", "serve" },
  -- filetypes = { "swift", "python" },        -- default: every file type
  -- settings = { model = "qwen2.5-coder" },   -- overrides .plan-complete.json
})
```

`Tab` accepts, `M-]` and `M-[` cycle. See `editors/nvim/README.md`.

## The guide

### Where it comes from

1. The editor starts `plan-complete serve` with the opened folder as the project root.
2. The server reads `<root>/.plan-complete.json` if there is one.
3. It loads every `.md` file under `<root>/<guideDir>` (`docs/guide/` by default).
4. It checks the file times at most once a second. The next suggestion after a save uses the new text,
   with no restart.

The editor stores nothing: the guide is plain files in your repository. Whatever writes them steers
the completions: you, Claude, or another agent.

### Format

```markdown
---
files: ["Sources/Net/**", "*.swift"]
symbols: [ResponseCache, store, evictIfNeeded]
priority: 1
---
## ResponseCache
`actor ResponseCache` holds at most `capacity` items; the default capacity is 100.
`func store(_ data: Data, for key: URL) async` inserts, then calls `evictIfNeeded()`.
No force unwraps.
```

- Each `## ` section is one chunk. The front-matter applies to every chunk of the file.
- `files:` are globs relative to the project root. `*` stays inside one folder, `**` crosses folders, and
  a pattern with no `/` matches the file name anywhere.
- `symbols:` are names. A chunk scores when one of them is near the cursor.
- `priority:` is added to the score.
- A file with no `files:` and no `symbols:` applies everywhere, weakly: good for project rules.
- Keep it short: signatures, names, invariants, defaults. A small model copies exact text and ignores
  long explanations. About 1200 tokens of guide go into one prompt.

`probe` prints `context: docs/guide/x.md#Heading` for the chunks that it used.

### Editing it while you work

- **By hand:** open the guide in a split next to the code, change a signature or a rule, save. The next
  suggestion follows it.
- **With Claude Code in VS Code:** open Claude Code (the `anthropic.claude-code` extension, or `claude`
  in the built-in terminal) in the project and ask it, for example:

  > Update `docs/guide/cache.md`: the next step adds `func reset()` to ResponseCache, which empties
  > `items` and `order`. Keep it to signatures and rules, with `files:` and `symbols:` front-matter.

- **With Claude Code in Neovim:** the same with `claude` in `:terminal` or a tmux split at the project root.

### Keeping it in step with a plan

If Claude writes your plans, add a rule like this to the project's `CLAUDE.md`:

> When you write or change a plan in `docs/plans/`, also write `docs/guide/<plan>.md`: front-matter
> `files:` (globs of the files the step touches), `symbols:`, `priority:`. Body: one `## ` section for each
> step, with the exact signatures, names, and rules. No prose. Remove the sections of finished steps.

The plan keeps the reasoning for agents. The guide is the short version for the completion model.

## What to expect

- A suggestion takes about 1 s with a 9B model on a GPU; Neovim adds its own 200 ms wait.
- The guide steers the model, it does not control it. Short starts (`/// The `, `func `) follow the guide
  closely; once you have typed your own words, the model follows them.
- `self.init(`, `foo.bar(`: the server finds the declarations of the name in the current file, and stops the
  completion where the call closes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `spawn plan-complete ENOENT` | Set `planComplete.serverPath` to the full path, then *Restart Server* |
| No ghost text | `Option+\`; check *View → Output → Plan Complete*; turn off other completion extensions |
| Slow first suggestion | The model server is loading the model |
| Odd suggestion | `plan-complete probe FILE:LINE:COL --prompt` shows what the model saw |
| Detailed log | Start the editor with `PLAN_COMPLETE_LOG=/tmp/pc.log` in the environment |
| The file changed in many places on save | That is your formatter (`editor.formatOnSave`), not this extension |

## Try it on the sample

`examples/sample` has a Swift file, a Python file, and a guide. With a model server running:

```sh
cd examples/sample
../../.build/release/plan-complete probe Sources/Net/Cache.swift:13:19   # self.init( → capacity: 100)
../../.build/release/plan-complete probe Sources/Net/Cache.swift:16:10   # func → store(_:for:) from the guide
../../.build/release/plan-complete probe Sources/Net/Cache.swift:16:10 --no-guide
```

Or open `examples/sample` in VS Code and type at those spots.

## Development

```sh
swift test
node scripts/lsp-smoke.mjs .build/debug/plan-complete examples/sample Sources/Net/Cache.swift 12 18
PC_BIN=$PWD/.build/debug/plan-complete PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua examples/sample/Sources/Net/Cache.swift
cd editors/vscode && PC_BIN=$PWD/../../.build/debug/plan-complete node test/run.js ../../examples/sample/Sources/Net/Cache.swift 12 18
```

`PLAN.md` holds the plan, the status, and the decisions.

## License

MIT
