# Plan-guided autocomplete

You or an agent such as Claude write a guide (Markdown files with front-matter). A small,
language-neutral language server picks the guide chunks that fit the cursor, adds what encloses the
cursor, and sends them with the prefix and suffix of the buffer to a fill-in-the-middle model.
Editors show the result as ghost text through `textDocument/inlineCompletion`.

## STATUS

- Done: Phases 0–4 (scaffold, core and probe, LSP server, Neovim, VS Code). 36 tests pass
  (30 core, 6 LSP). Each editor has an end-to-end check that triggers, accepts, and reads the buffer.
- Done after Phase 4, from a trial in a large Swift project:
  - Comment lines: no restated typed text, no double space, one line only, a two-line suffix, and one
    retry with no suffix when the first answer is empty (the model often ends a started comment at once).
  - Trailing spaces of the typed line leave the prompt; a repeated word (`public var ` + `var x`) is dropped.
  - The VS Code client shows a clear message when the binary is missing.
  - `probe --raw` prints the raw model text.
- Next, open:
  1. Compare guide selection with the llama.vim way (the guide open in a buffer, recent chunks in `input_extra`).
  2. Phase 5, Xcode: choose between the two options below.
  3. Release: GitHub Actions that attach the `.vsix` and a macOS binary to a tag; the extension finds or
     downloads the binary itself.
- Restart from here: read this block, then the item marked next.

## Measured

On a 9B Qwen-format coder model on one consumer GPU (llama-server, about 100 tok/s out, 2000 tok/s prompt):

- About 0.8–0.9 s server time per completion; Neovim adds its own 200 ms debounce.
- `examples/sample`: `self.init(` → `capacity: 100)` (the guide's default; without the guide the model
  writes `1000`). `func ` → the guide's `store(_:for:)` with `evictIfNeeded()`; without the guide the model
  writes a `get(key:)` with a force unwrap.
- In a large Swift project: `/// The ` above an accessor gave the guide's doc line word for word;
  `public func ` gave the guide's helper with its port note and body.
- The guide steers, it does not control: once the user types their own words, the model follows them.
- A model proxy that holds one model at a time (llama-swap) unloads the completion model when another
  client asks for a different one; the next completion then waits for the load.

## Facts checked

- llama-server `/infill` takes `input_prefix`, `input_suffix`, `input_extra: [{filename, text}]`, and builds the
  Qwen repo prompt: `<|repo_name|>`, then `<|file_sep|>filename\ntext` for each extra, then
  `<|file_sep|>path\n<|fim_prefix|>…<|fim_suffix|>…<|fim_middle|>`. llama-swap passes `/infill` through.
- Neovim 0.12 has `vim.lsp.inline_completion` (`enable`, `get`, `select`), a 200 ms debounce, and applies an
  accepted item on the next loop tick.
- `vscode-languageclient` 11 supports inline completion, so the VS Code extension is a thin client of the same
  binary. VS Code has no public command that runs inline-completion providers; the end-to-end check uses
  `editor.action.inlineSuggest.trigger` and `commit`.

## Decisions

- **Swift**, no package dependencies. The core is a library, so an Xcode app can link it. VS Code needs only a
  small TypeScript client.
- **Language neutral.** The server parses no language. It attaches to every file type next to the real language
  server and answers only `textDocument/inlineCompletion`. Guide selection uses file globs and word matching.
- **Providers behind one protocol**, picked by config: `llama-infill` (`<base>/infill`, the server builds the FIM
  prompt) and `openai-fim` (`<base>/v1/completions`, the client builds the Qwen prompt). A local server and a
  remote one differ only in `baseURL`.
- **Guide location:** `docs/guide/*.md`, apart from plans. Plans keep the reasoning for agents; the guide is the
  short version for the model.
- **Cursor context.** `ScopeContext` finds the enclosing block headers by indentation and the open call at the
  cursor (`self.init(` → `init`), and lists the declarations of that name in the file. It goes into the prompt as
  an extra file `<path>.scope`. A client can send richer context from the real language server in
  `params.extraContext: [{path, text}]`, which replaces the scope summary; the VS Code client sends signature help.
  When the cursor is in an open call, the completion ends where that call closes.
- **Cleanup is text only:** FIM tokens, text that repeats the rest of the line or the next line, lines that leave
  the cursor's block, repeated typed words, comment-line rules above.
- **Defaults point at a local llama-server** (`http://127.0.0.1:8012`); each project sets its own
  `.plan-complete.json`, which git ignores.
- **Minimal code comments.** Only where the code cannot say it.

## Existing tools, and why we still build this

| Tool | Ghost text through the LSP request | Local FIM backend | Guide in the prompt |
|---|---|---|---|
| copilot-language-server | yes | no | no |
| llm-ls | own request, needs own clients | yes | no |
| lsp-ai | popup and own request | yes | partly: embedding search, no file or symbol match |
| llama.vim / llama.vscode | plugin code | yes, `/infill` | by accident: recent buffers |

## Guide format

```markdown
---
files: ["Sources/Net/**"]
symbols: [ResponseCache, store]
priority: 2
---
## ResponseCache
ResponseCache is an actor. store() evicts LRU when count > 100. No force unwraps.
`func store(_ data: Data, for key: URL) async`
```

Each `## ` section is one chunk, with the front-matter of its file. A file with no heading is one chunk.
Bodies stay short: signatures, invariants, naming rules. The server rereads the folder at most once a second.

## Config: `.plan-complete.json` at the workspace root (all fields optional)

```json
{ "baseURL": "http://127.0.0.1:8012", "provider": "llama-infill", "model": "default", "apiKey": null,
  "guideDir": "docs/guide", "guideTokenBudget": 1200, "maxTokens": 64, "maxLines": 12,
  "prefixLines": 80, "suffixLines": 40, "timeoutMs": 4000, "debounceMs": 60,
  "useGuide": true, "useScope": true }
```

LSP `initializationOptions` (VS Code `planComplete.settings`, Neovim `settings`) override the file.

## Layout

```
Package.swift
Sources/PlanCompleteCore/    Config, JSONValue, Guide, Glob, GuideSelector, TextDocument, ScopeContext,
                             Providers, Postprocess, Engine
Sources/PlanCompleteLSP/     Framing (Content-Length), LSPServer
Sources/plan-complete/       main: `serve` (stdio LSP), `probe FILE:LINE:COL`
Tests/PlanCompleteCoreTests/ guide, selection, text, scope, cleanup, engine
Tests/PlanCompleteLSPTests/  server in process, framing
editors/nvim/lua/plan_complete.lua
editors/vscode/              client extension, test/run.js (end-to-end)
scripts/                     lsp-smoke.mjs, nvim-smoke.lua
examples/sample/             Swift and Python files with a guide
docs/guide/                  guide for this repository
```

## Phases

Each phase ends with `swift build` and `swift test` passing, the STATUS block updated, and one commit.
Each phase end is a compaction point.

### Phase 0 — Scaffold (done)
Package with the library, the LSP target, the executable, and test targets; `.gitignore`; sample guide.

### Phase 1 — Core (done)
`JSONValue`, `Config`; `Guide` (front-matter, chunks); `GuideSelector` (globs, symbols, word overlap,
priority, token budget); `TextDocument` (UTF-16 positions, incremental edits, context); `ScopeContext`;
`CompletionProvider` with `LlamaInfillProvider` and `OpenAIFIMProvider`; `Postprocess`; `Engine` (guide
reload, LRU cache, typeahead reuse of an earlier completion); `probe`.

### Phase 2 — LSP server (done)
Content-Length framing over stdio; `initialize` (incremental sync, `inlineCompletionProvider`),
`didOpen`/`didChange`/`didClose`, `didChangeConfiguration`, `textDocument/inlineCompletion` (with
`selectedCompletionInfo` and `extraContext`), `$/cancelRequest`, `shutdown`, `exit`. A newer request for the
same document cancels the older one. `PLAN_COMPLETE_LOG` writes a trace.

### Phase 3 — Neovim (done)
`editors/nvim/lua/plan_complete.lua`: starts the server for every file type (or a list), enables
`vim.lsp.inline_completion`, maps Tab, `M-]`, `M-[`. `scripts/nvim-smoke.lua` checks ghost text and accept.

### Phase 4 — VS Code (done)
`editors/vscode`: `vscode-languageclient` 11 client for every file, `planComplete.serverPath`,
`planComplete.settings`, signature help as `extraContext`. esbuild bundle, `.vsix` with `npm run package`.

### Phase 5 — Xcode (not started)
Options: a suggestion-service plugin for Copilot for Xcode (intitni) that links the core, or an HTTP mode of
the server for an overlay app of our own.
