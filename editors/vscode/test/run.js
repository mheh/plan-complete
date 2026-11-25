// node test/run.js FILE LINE COL   (zero-based LINE and COL); needs PC_BIN.
const path = require("path");
const os = require("os");
const fs = require("fs");
const { runTests } = require("@vscode/test-electron");

(async () => {
  const [file, line, col] = process.argv.slice(2);
  const result = path.join(os.tmpdir(), `pc-vscode-${process.pid}.json`);
  const userDir = fs.mkdtempSync(path.join(os.tmpdir(), "pc-vscode-user-"));
  fs.mkdirSync(path.join(userDir, "User"), { recursive: true });
  fs.writeFileSync(path.join(userDir, "User", "settings.json"),
    JSON.stringify({ "planComplete.serverPath": process.env.PC_BIN, "planComplete.passSignatureHelp": true }));
  const workspace = path.dirname(path.resolve(file));
  await runTests({
    vscodeExecutablePath: process.env.PC_VSCODE || "/Applications/Visual Studio Code.app/Contents/MacOS/Code",
    extensionDevelopmentPath: path.resolve(__dirname, ".."),
    extensionTestsPath: path.resolve(__dirname, "suite.js"),
    launchArgs: [findRoot(workspace), "--disable-extensions", "--user-data-dir", userDir, "--skip-welcome", "--disable-workspace-trust"],
    extensionTestsEnv: { PC_FILE: path.resolve(file), PC_LINE: line, PC_COL: col, PC_RESULT: result },
  });
  const report = JSON.parse(fs.readFileSync(result, "utf8"));
  console.log(JSON.stringify(report, null, 2));
  process.exit(report.ok ? 0 : 1);
})().catch((error) => { console.error(error); process.exit(1); });

function findRoot(dir) {
  for (let d = dir; d !== path.dirname(d); d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, ".plan-complete.json")) || fs.existsSync(path.join(d, ".git"))) return d;
  }
  return dir;
}
