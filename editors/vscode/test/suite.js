const vscode = require("vscode");
const fs = require("fs");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitStatus(active, ms = 8000) {
  const end = Date.now() + ms;
  let status;
  while (Date.now() < end) {
    status = await vscode.commands.executeCommand("planComplete.status");
    if (status && status.active === active) return status;
    await sleep(200);
  }
  return status;
}

exports.run = async function () {
  const write = (obj) => fs.writeFileSync(process.env.PC_RESULT, JSON.stringify(obj, null, 2));
  try {
    const line = Number(process.env.PC_LINE);
    const col = Number(process.env.PC_COL);
    const expectActive = process.env.PC_EXPECT !== "off";
    const document = await vscode.workspace.openTextDocument(process.env.PC_FILE);
    const editor = await vscode.window.showTextDocument(document);
    await vscode.extensions.getExtension("plan-complete.plan-complete").activate();
    const status = await waitStatus(expectActive);
    const before = document.getText();
    const position = new vscode.Position(line, col);
    editor.selection = new vscode.Selection(position, position);
    const started = Date.now();
    let after = before;
    let attempts = 0;
    for (; attempts < (expectActive ? 15 : 3) && after === before; ) {
      attempts++;
      await vscode.commands.executeCommand("editor.action.inlineSuggest.trigger");
      await sleep(1500);
      await vscode.commands.executeCommand("editor.action.inlineSuggest.commit");
      await sleep(100);
      after = document.getText();
    }
    const inserted = after === before ? "" : diff(before, after);
    await vscode.commands.executeCommand("workbench.action.files.revert");
    const ok = expectActive ? status.active && inserted.length > 0 : !status.active && inserted.length === 0;
    write({ ok, status, ms: Date.now() - started, attempts, inserted, line: after.split("\n")[line] });
  } catch (error) {
    write({ ok: false, error: String((error && error.stack) || error) });
  }
};

function diff(a, b) {
  let start = 0;
  while (start < a.length && a[start] === b[start]) start++;
  let endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) { endA--; endB--; }
  return b.slice(start, endB);
}
