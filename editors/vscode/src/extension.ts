import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

export async function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand("planComplete.restart", async () => {
      await stop();
      await start(context);
    }),
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("planComplete")) {
        await stop();
        await start(context);
      }
    }),
  );
  await start(context);
}

export async function deactivate() {
  await stop();
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
  context.subscriptions.push(client);
  try {
    await client.start();
  } catch (error) {
    void vscode.window.showErrorMessage(`Plan Complete: cannot start "${command}". Set planComplete.serverPath to the full path of the binary.`);
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
    if (!extra || !client) {
      return next(document, position, context, token);
    }
    const params = {
      ...client.code2ProtocolConverter.asInlineCompletionParams(document, position, context),
      extraContext: [extra],
    };
    const result = await client.sendRequest("textDocument/inlineCompletion", params, token);
    if (token.isCancellationRequested) {
      return null;
    }
    return client.protocol2CodeConverter.asInlineCompletionResult(result as never, token);
  };

async function signatureContext(document: vscode.TextDocument, position: vscode.Position) {
  const help = await Promise.race([
    vscode.commands.executeCommand<vscode.SignatureHelp | undefined>(
      "vscode.executeSignatureHelpProvider", document.uri, position),
    new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), 150)),
  ]);
  if (!help || help.signatures.length === 0) {
    return undefined;
  }
  const lines = help.signatures.map((signature) => {
    const doc = typeof signature.documentation === "string"
      ? signature.documentation
      : signature.documentation?.value;
    return doc ? `${signature.label}\n  ${doc.split("\n")[0]}` : signature.label;
  });
  const path = vscode.workspace.asRelativePath(document.uri);
  return { path: `${path}.signature`, text: `Signatures at the cursor in ${path}:\n${lines.join("\n")}\n` };
}
