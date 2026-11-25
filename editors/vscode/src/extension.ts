import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions, ServerOptions, TransportKind } from "vscode-languageclient/node";
import { contextMiddleware } from "./context";
import { findServer } from "./server";
import { PlanStatus, StatusItem } from "./status";
import { SymbolPaths } from "./symbols";

const enabledKey = "planComplete.enabled";
const helpURL = "https://github.com/mheh/plan-complete#requirements";

let client: LanguageClient | undefined;
let status: StatusItem;
let symbols: SymbolPaths;
let extension: vscode.ExtensionContext;

interface Files {
  global: string;
  repo: string;
  plan: string;
}

export async function activate(context: vscode.ExtensionContext) {
  extension = context;
  status = new StatusItem("planComplete.menu");
  symbols = new SymbolPaths(context.subscriptions);
  const command = (name: string, run: () => unknown) => vscode.commands.registerCommand(`planComplete.${name}`, run);
  context.subscriptions.push(
    status,
    command("menu", menu),
    command("enable", enable),
    command("toggle", toggle),
    command("restart", restart),
    command("openPlan", () => open("plan")),
    command("openSettings", () => open("repo")),
    command("openGlobalSettings", () => open("global")),
    command("status", () => status.current),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("planComplete")) void restart();
    }),
  );
  await start();
}

export async function deactivate() {
  await stop();
}

function isEnabled(): boolean {
  return extension.workspaceState.get<boolean>(enabledKey, true);
}

async function start() {
  const server = findServer(extension);
  const run = { command: server.command, args: ["serve"], transport: TransportKind.stdio };
  const serverOptions: ServerOptions = { run, debug: run };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file" }, { scheme: "untitled" }],
    initializationOptions: vscode.workspace.getConfiguration("planComplete").get<object>("settings", {}),
    middleware: {
      provideInlineCompletionItems: contextMiddleware(() => client, () => status.current.context, symbols),
    },
  };
  client = new LanguageClient("planComplete", "Plan Complete", serverOptions, clientOptions);
  client.onNotification("planComplete/status", (state: PlanStatus) => status.show(state));
  try {
    await client.start();
    if (!isEnabled()) await client.sendRequest("planComplete/setEnabled", { enabled: false });
  } catch {
    client = undefined;
    const where = server.source === "PATH" ? `"plan-complete" is not on PATH` : `cannot run "${server.command}"`;
    status.show({ active: false, reason: "the server did not start", problem: where });
    const pick = await vscode.window.showErrorMessage(
      `Plan Complete: ${where}. Set planComplete.serverPath to the full path of the binary.`, "Open Setting");
    if (pick) void vscode.commands.executeCommand("workbench.action.openSettings", "planComplete.serverPath");
  }
}

async function stop() {
  const old = client;
  client = undefined;
  try {
    await old?.stop();
  } catch {
    // A client that never started cannot stop.
  }
}

async function restart() {
  await stop();
  await start();
}

async function toggle() {
  const enabled = !isEnabled();
  await extension.workspaceState.update(enabledKey, enabled);
  await client?.sendRequest("planComplete/setEnabled", { enabled });
}

async function enable() {
  if (!client) return restart();
  if (!isEnabled()) await toggle();
  const reply = await client.sendRequest<{ created: string[] }>("planComplete/enable", {});
  if (reply.created.some((name) => name.toLowerCase().endsWith(".md"))) await open("plan");
}

async function open(which: keyof Files) {
  if (!client) return;
  const files = await client.sendRequest<Files>("planComplete/files", { createGlobal: which === "global" });
  try {
    await vscode.window.showTextDocument(vscode.Uri.file(files[which]));
  } catch {
    void vscode.window.showWarningMessage(`Plan Complete: ${files[which]} does not exist. Run "Plan Complete: Enable in This Workspace".`);
  }
}

async function menu() {
  const state = status.current;
  const items: (vscode.QuickPickItem & { run: () => unknown })[] = [];
  const add = (label: string, detail: string, run: () => unknown) => items.push({ label, detail, run });
  if (!client) {
    add("$(debug-restart) Start the server", state.problem ?? state.reason, restart);
    add("$(gear) Set the server path", "planComplete.serverPath",
      () => vscode.commands.executeCommand("workbench.action.openSettings", "planComplete.serverPath"));
  } else {
    if (state.problem) add("$(warning) Model server help", state.problem, () => vscode.env.openExternal(vscode.Uri.parse(helpURL)));
    if (!state.active && isEnabled()) {
      add("$(sparkle) Enable in this workspace", `Off: ${state.reason}. Writes .plan-complete.json, and a starter plan when there is none.`, enable);
    }
    if (state.active) add("$(book) Open the plan", state.reason, () => open("plan"));
    add(isEnabled() ? "$(circle-slash) Turn off for this workspace" : "$(sparkle) Turn on for this workspace",
      "VS Code remembers this for the workspace.", toggle);
    if (state.active) add("$(gear) Open the repository settings", ".plan-complete.json", () => open("repo"));
    add("$(globe) Open the global settings", "Where your model server is, for every repository.", () => open("global"));
    add("$(debug-restart) Restart the server", "", restart);
    add("$(output) Show the log", "", () => client?.outputChannel.show());
  }
  const pick = await vscode.window.showQuickPick(items, { title: "Plan Complete" });
  await pick?.run();
}
