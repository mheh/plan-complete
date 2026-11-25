import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

export interface ServerBinary {
  command: string;
  source: "setting" | "bundled" | "PATH";
}

/// The `planComplete.serverPath` setting, then the binary inside the extension, then `PATH`.
export function findServer(context: vscode.ExtensionContext): ServerBinary {
  const setting = vscode.workspace.getConfiguration("planComplete").get<string>("serverPath", "").trim();
  if (setting) return { command: setting, source: "setting" };
  const name = process.platform === "win32" ? "plan-complete.exe" : "plan-complete";
  const bundled = context.asAbsolutePath(path.join("bin", name));
  if (fs.existsSync(bundled)) {
    try {
      fs.chmodSync(bundled, 0o755);
    } catch {
      // A read-only install still runs when the mode is already right.
    }
    return { command: bundled, source: "bundled" };
  }
  return { command: "plan-complete", source: "PATH" };
}
