# Plan Complete for VS Code

Thin client: starts `plan-complete serve` and shows its inline completions for every file.

Settings:
- `planComplete.serverPath`: path of the binary (`.build/release/plan-complete`).
- `planComplete.settings`: overrides of `.plan-complete.json`.
- `planComplete.passSignatureHelp`: send the real language server's signature help at the cursor as context.

Build: `npm install && npm run package`, then `code --install-extension plan-complete-0.1.0.vsix`.
Check: `PC_BIN=<binary> node test/run.js FILE LINE COL` (zero-based) runs VS Code, triggers, accepts.
