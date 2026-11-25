const vscode = require("vscode");
const fs = require("fs");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

exports.run = async function () {
  const write = (obj) => fs.writeFileSync(process.env.PC_RESULT, JSON.stringify(obj, null, 2));
  try {
    const line = Number(process.env.PC_LINE);
    const col = Number(process.env.PC_COL);
    const document = await vscode.workspace.openTextDocument(process.env.PC_FILE);
    const editor = await vscode.window.showTextDocument(document);
    await vscode.extensions.getExtension("plan-complete.plan-complete").activate();
    const before = document.getText();
    const position = new vscode.Position(line, col);
    editor.selection = new vscode.Selection(position, position);
    const started = Date.now();
    let after = before;
    let attempts = 0;
    for (let attempt = 0; attempt < 15 && after === before; attempt++) {
      attempts++;
      await vscode.commands.executeCommand("editor.action.inlineSuggest.trigger");
      await sleep(1500);
      await vscode.commands.executeCommand("editor.action.inlineSuggest.commit");
      await sleep(100);
      after = document.getText();
    }
    const inserted = after === before ? "" : diff(before, after);
    await vscode.commands.executeCommand("workbench.action.files.revert");
    write({ ok: inserted.length > 0, ms: Date.now() - started, attempts, inserted, line: after.split("\n")[line] });
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
