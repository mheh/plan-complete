# Plan-guided autocomplete

You or an agent such as Claude write a guide (Markdown files with front-matter). A small,
language-neutral language server picks the guide chunks that fit the cursor, adds what encloses the
cursor, and sends them with the prefix and suffix of the buffer to a fill-in-the-middle model.
Editors show the result as ghost text through `textDocument/inlineCompletion`.

## STATUS

- Done: Phases 0–4 (scaffold, core and probe, LSP server, Neovim, VS Code). Each editor has an end-to-end check that triggers, accepts, and reads the buffer.
- Done after Phase 4, from a trial in a large Swift project:
  - Comment lines: no restated typed text, no double space, one line only, a two-line suffix, and one
    retry with no suffix when the first answer is empty (the model often ends a started comment at once).
  - Trailing spaces of the typed line leave the prompt; a repeated word (`public var ` + `var x`) is dropped.
  - The VS Code client shows a clear message when the binary is missing.
  - `probe --raw` prints the raw model text.
- Done: the plan is a plain `PLAN.md` at the root by default (`guide` names a file or a folder); settings are
  global (`~/.config/plan-complete/config.json`), then the repo `.plan-complete.json`, then the editor.
- Done: the opt-in rule. The server answers only with `<repo>/.plan-complete.json`, its plan, and the toggle
  on; otherwise it returns at once. It sends `planComplete/status` `{active, reason}`; VS Code shows it in the
  status bar and toggles per workspace; Neovim has `:PlanCompleteToggle`, `:PlanCompleteStatus`, `statusline()`.
- Done: Linux and Windows. Linux is checked in Docker (Swift 6.2 and 6.4): the tests pass and a live LSP round
  trip works. Windows paths are handled (`C:\` roots, `file:///c%3A/...`, `%APPDATA%`), and CI is its first test.
- Done: CI (`.github/workflows/ci.yml`): Linux 6.2 and 6.4, macOS, Windows, and the VS Code extension. Actions are
  pinned to commits. The `.build` cache is saved on master only; branches and pull requests restore it.
- Done: version 0.2.0, "usable from a default install". 65 tests pass (54 core, 11 LSP) on macOS and on Linux
  in Docker (Swift 6.2 and 6.4).
  - Settings: nested `context` and `scoring`; layers merge field by field; the files allow comments and
    trailing commas; saving a settings file in the editor reloads it.
  - Setup: `Setup.enable` writes a commented `.plan-complete.json` and a starter `PLAN.md` (text in HTML
    comments is not read). CLI `enable`, `config`, `--version`. LSP `planComplete/enable`, `planComplete/files`.
  - Status carries `problem` (model server down, bad settings) and `context` (what the editor gathers).
  - VS Code: the binary is inside the extension; the status bar opens a menu; a JSON schema covers the
    settings files. Neovim: `:PlanCompleteEnable`. Both checked end to end.
  - Release: CI builds a universal macOS binary, static Linux binaries (musl SDK, 58 MB) and a Windows binary
    with its Swift runtime DLLs beside it (`scripts/windows-bundle.ps1`; static linking fails there, no `curl.lib`), packages one `.vsix` for each VS Code target with `scripts/package.sh`, and on a `v*` tag makes
    the GitHub release. The Windows binary and the release job have not run yet.
- Next, open:
  0. The symbol path: `context.symbols` (default on). The VS Code client caches `textDocument/documentSymbol`
     for each file and sends the enclosing path (`ResponseCache > init()`) as `extraContext`. The server scores
     a section that names the enclosing type +8 and the member +4 (`scoring.type`, `scoring.member`), and
     ignores generic names (`init`, `body`, `description`, under four characters). Compare with and without it
     on `examples/sample`, then decide on the receiver type from hover (`context.hover`, 100 ms limit) and on the
     declaration of the called name (`context.definition`). Neovim after the format settles.
  1. Compare guide selection with the llama.vim way (the guide open in a buffer, recent chunks in `input_extra`).
  2. Phase 5, Xcode: choose between the two options below.
  3. Tag `v0.2.0` after CI is green, and check the Windows `.vsix` on a Windows machine.
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
- **The plan is plain Markdown.** The default guide is `PLAN.md` at the root, as stock as possible: `## ` and `### `
  sections are chunks; a section that names the edited file ranks first; code spans stand in for symbols.
  Front-matter (`files:`, `symbols:`, `priority:`) is optional. `guide` names another file or a folder.
- **Settings in layers:** built-in defaults, the global file, the repo `.plan-complete.json`, the editor overrides.
  Each layer sets only the fields it names. The model server goes in the global file.
- **Opt in, quiet otherwise.** No `.plan-complete.json` at the repository root, or no plan, or the toggle off:
  the server returns every completion at once, with no model call. The editors always start it, so a plan
  written later turns it on within a second. Only the repo file can name the plan (`guide`); the global file and
  the editors cannot, and a path outside the repository falls back to `PLAN.md`. An empty `{}` means `PLAN.md`.
  `probe` follows the rule and prints the reason; `probe --no-guide` skips it.
- **Cursor context.** `ScopeContext` finds the enclosing block headers by indentation and the open call at the
  cursor (`self.init(` → `init`), and lists the declarations of that name in the file. It goes into the prompt as
  an extra file `<path>.scope`. A client can send richer context from the real language server in
  `params.extraContext: [{path, text}]`, which replaces the scope summary; the VS Code client sends signature help.
  When the cursor is in an open call, the completion ends where that call closes.
- **Cleanup is text only:** FIM tokens, text that repeats the rest of the line or the next line, lines that leave
  the cursor's block, repeated typed words, comment-line rules above.
- **Defaults point at a local llama-server** (`http://127.0.0.1:8012`). The model server goes in the global file.
  This repository opts in with a root `.plan-complete.json`, which git ignores here.
- **Minimal code comments.** Only where the code cannot say it.
- **Actors, no locks.** Shared state lives in an actor (`Engine`, `LSPServer`, the test doubles). No mutex, no
  `@unchecked Sendable`.
- **Usable from a default install, and every feature has a setting.** A new feature gets a field with a good
  default in `Config`, the template, the schema and the README table.

## Existing tools, and why we still build this

| Tool | Ghost text through the LSP request | Local FIM backend | Guide in the prompt |
|---|---|---|---|
| copilot-language-server | yes | no | no |
| llm-ls | own request, needs own clients | yes | no |
| lsp-ai | popup and own request | yes | partly: embedding search, no file or symbol match |
| llama.vim / llama.vscode | plugin code | yes, `/infill` | by accident: recent buffers |

## Guide format

```markdown
## Step 1: ResponseCache in Sources/Net/Cache.swift
`actor ResponseCache` holds at most 100 items. No force unwraps.
`func store(_ data: Data, for key: URL) async`
```

Each `## ` or `### ` section is one chunk. Text before the first heading is one chunk. Optional front-matter
(`files:`, `symbols:`, `priority:`) applies to every chunk of its file. Score: file glob 10, file named in the
section 8, symbol 4, code-span name near the cursor 2 (up to 3), heading word 2, word overlap up to 3, priority
added. Sections with no tie are dropped while any section ties. One section larger than the budget is cut to fit.
The server rereads the plan at most once a second.

## Config: `~/.config/plan-complete/config.json`, then `<root>/.plan-complete.json` (all fields optional)

```jsonc
{ "baseURL": "http://127.0.0.1:8012", "provider": "llama-infill", "model": "default", "apiKey": null,
  "guide": "PLAN.md", "guideTokenBudget": 1200, "maxTokens": 64, "maxLines": 12,
  "prefixLines": 80, "suffixLines": 40, "timeoutMs": 4000, "debounceMs": 60,
  "useGuide": true, "useScope": true,
  "context": { "signature": true, "timeoutMs": 100, "tokenBudget": 300 },
  // Subject to change between versions.
  "scoring": { "glob": 10, "file": 8, "symbol": 4, "codeSpan": 2, "heading": 2, "words": 3 } }
```

LSP `initializationOptions` (VS Code `planComplete.settings`, Neovim `settings`) override both files.
The server owns the settings: it sends `context` to the editor with each status, so one file configures every
editor. `Config`, the template that `enable` writes, the VS Code schema and the README table list the same
fields; tests check the first three against each other.

## Layout

```
Package.swift
Sources/PlanCompleteCore/
  Engine.swift               one completion: plan state, prompt, model call, cleanup, cache
  Config/                    Config (fields, layers), Setup (enable, the file templates)
  Plan/                      Guide (Markdown to chunks), GuideSelector (scoring), Glob, PlanState (the opt-in rule)
  Text/                      TextDocument, ScopeContext, Postprocess
  Model/                     CompletionProvider, LlamaInfillProvider, OpenAIFIMProvider, JSONPoster, ModelFailure
  Support/                   JSONValue, JSONC, LRUCache, RelativePath, Version
Sources/PlanCompleteLSP/     LSPServer (state and dispatch), InlineCompletion, Wire (replies, log, ranges),
                             Framing (Content-Length), Stdio, FileURI
Sources/plan-complete/       main (usage and dispatch), Commands (`enable`, `config`), Probe, Root
Tests/PlanCompleteCoreTests/ one file for each subject; Support.swift has the shared helpers
Tests/PlanCompleteLSPTests/  server in process, framing
editors/nvim/lua/plan_complete.lua
editors/vscode/              src/{extension,server,status,context}.ts, schemas/, test/run.js (end-to-end)
scripts/                     lsp-smoke.mjs, nvim-smoke.lua, package.sh (the .vsix files and archives)
examples/sample/             Swift and Python files with a plain PLAN.md
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
`selectedCompletionInfo` and `extraContext`), `$/cancelRequest`, `shutdown`, `exit`, and `planComplete/setEnabled` and `planComplete/status`. A newer request for
the same document cancels the older one. `PLAN_COMPLETE_LOG` writes a trace.

### Phase 3 — Neovim (done)
`editors/nvim/lua/plan_complete.lua`: starts the server for every file type (or a list), enables
`vim.lsp.inline_completion`, maps Tab, `M-]`, `M-[`. `scripts/nvim-smoke.lua` checks ghost text and accept.

### Phase 4 — VS Code (done)
`editors/vscode`: `vscode-languageclient` 11 client for every file, `planComplete.serverPath`,
`planComplete.settings`, signature help as `extraContext`. esbuild bundle, `.vsix` with `npm run package`.

### Phase 5 — Xcode (not started)
Options: a suggestion-service plugin for Copilot for Xcode (intitni) that links the core, or an HTTP mode of
the server for an overlay app of our own.
