import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let status: vscode.StatusBarItem;
let workspaceState: vscode.Memento;
let lastStatus: PlanStatus = { active: false, reason: "starting" };

const enabledKey = "planComplete.enabled";

interface PlanStatus {
  active: boolean;
  reason: string;
}

export async function activate(context: vscode.ExtensionContext) {
  workspaceState = context.workspaceState;
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  status.command = "planComplete.toggle";
  context.subscriptions.push(
    status,
    vscode.commands.registerCommand("planComplete.restart", async () => {
      await stop();
      await start(context);
    }),
    vscode.commands.registerCommand("planComplete.toggle", toggle),
    vscode.commands.registerCommand("planComplete.status", () => lastStatus),
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("planComplete")) {
        await stop();
        await start(context);
      }
    }),
  );
  showStatus({ active: false, reason: "starting" });
  await start(context);
}

export async function deactivate() {
  await stop();
}

function isEnabled(): boolean {
  return workspaceState.get<boolean>(enabledKey, true);
}

async function toggle() {
  const enabled = !isEnabled();
  await workspaceState.update(enabledKey, enabled);
  await client?.sendRequest("planComplete/setEnabled", { enabled });
}

function showStatus(state: PlanStatus) {
  lastStatus = state;
  status.text = state.active ? "$(sparkle) Plan: on" : "$(circle-slash) Plan: off";
  status.tooltip = state.active
    ? `Plan Complete follows ${state.reason}. Click to turn it off for this workspace.`
    : `Plan Complete is off: ${state.reason}. Click to ${isEnabled() ? "check again" : "turn it on"}.`;
  status.show();
}

async function start(context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration("planComplete");
  const command = config.get<string>("serverPath", "plan-complete");
  const serverOptions: ServerOptions = {
    run: { command, args: ["serve"], transport: TransportKind.stdio },
    debug: { command, args: ["serve"], transport: TransportKind.stdio },
  };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file" }, { scheme: "untitled" }],
    initializationOptions: config.get<object>("settings", {}),
    middleware: config.get<boolean>("passSignatureHelp", true)
      ? { provideInlineCompletionItems: withSignatureHelp }
      : undefined,
  };
  client = new LanguageClient("planComplete", "Plan Complete", serverOptions, clientOptions);
  client.onNotification("planComplete/status", showStatus);
  context.subscriptions.push(client);
  try {
    await client.start();
    if (!isEnabled()) await client.sendRequest("planComplete/setEnabled", { enabled: false });
  } catch {
    showStatus({ active: false, reason: "server did not start" });
    void vscode.window.showErrorMessage(
      `Plan Complete: cannot start "${command}". Set planComplete.serverPath to the full path of the binary.`);
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

/// Adds the signature of the call at the cursor, from the real language server, as `extraContext`.
const withSignatureHelp: NonNullable<LanguageClientOptions["middleware"]>["provideInlineCompletionItems"] =
  async (document, position, context, token, next) => {
    const extra = await signatureContext(document, position);
    if (!extra || !client) return next(document, position, context, token);
    const params = {
      ...client.code2ProtocolConverter.asInlineCompletionParams(document, position, context),
      extraContext: [extra],
    };
    const result = await client.sendRequest("textDocument/inlineCompletion", params, token);
    if (token.isCancellationRequested) return null;
    return client.protocol2CodeConverter.asInlineCompletionResult(result as never, token);
  };

async function signatureContext(document: vscode.TextDocument, position: vscode.Position) {
  const help = await Promise.race([
    vscode.commands.executeCommand<vscode.SignatureHelp | undefined>(
      "vscode.executeSignatureHelpProvider", document.uri, position),
    new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), 150)),
  ]);
  if (!help || help.signatures.length === 0) return undefined;
  const lines = help.signatures.map((signature) => {
    const doc = typeof signature.documentation === "string"
      ? signature.documentation
      : signature.documentation?.value;
    return doc ? `${signature.label}\n  ${doc.split("\n")[0]}` : signature.label;
  });
  const path = vscode.workspace.asRelativePath(document.uri);
  return { path: `${path}.signature`, text: `Signatures at the cursor in ${path}:\n${lines.join("\n")}\n` };
}
