# Plan Complete for VS Code

Inline completions that follow the plan of your repository (`PLAN.md`), from a local fill-in-the-middle model.

1. Start a model server: `llama-server -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF --port 8012`.
2. Click `Plan: off` in the status bar and pick *Enable in this workspace*.
3. Write a step into `PLAN.md`, open the file that it names, and type.

The status bar menu opens the plan and the settings files. Full documentation:
https://github.com/mheh/plan-complete

## Settings

- `planComplete.serverPath`: full path of the `plan-complete` binary. Empty: the binary inside the
  extension, then `plan-complete` on `PATH`.
- `planComplete.settings`: overrides of the server settings, for VS Code only.

Everything else is in the server's own files, so that every editor shares it.

## Development

- `src/extension.ts`: the client, the commands, and the menu.
- `src/server.ts`: where the binary is.
- `src/status.ts`: the status bar item.
- `src/context.ts`: what the real language server knows at the cursor, sent with each request.
- `schemas/plan-complete.schema.json`: the settings files. A Swift test checks it against `Config`.

`npm install && npm run package` builds a `.vsix` with no binary; `scripts/package.sh` builds the ones
with a binary. `node test/run.js FILE LINE COL` (zero-based) runs VS Code, triggers a suggestion, and
accepts it. `PC_BIN` names the binary; `PC_EXPECT` is `on`, `off`, or `enable`.
