import * as vscode from "vscode";
import { LanguageClient, LanguageClientOptions } from "vscode-languageclient/node";
import { ContextSettings } from "./status";
import { PathSymbol, SymbolPaths } from "./symbols";

type Middleware = NonNullable<LanguageClientOptions["middleware"]>;

interface ExtraContext {
  path: string;
  text: string;
}

/// Adds what the real language server knows at the cursor to each request, as `extraContext`.
/// The server's `context` settings say what to gather and how long to wait.
export function contextMiddleware(
  client: () => LanguageClient | undefined,
  settings: () => ContextSettings | undefined,
  symbols: SymbolPaths,
): Middleware["provideInlineCompletionItems"] {
  return async (document, position, context, token, next) => {
    const active = client();
    const wanted = settings();
    if (!active || !wanted) return next(document, position, context, token);
    const [extras, symbolPath] = await Promise.all([
      gather(document, position, wanted),
      wanted.symbols ? within(wanted.timeoutMs, symbols.at(document, position)) : undefined,
    ]);
    if (extras.length === 0 && !symbolPath?.length) return next(document, position, context, token);
    const params: Record<string, unknown> = {
      ...active.code2ProtocolConverter.asInlineCompletionParams(document, position, context),
      extraContext: extras,
      symbolPath: symbolPath ?? ([] as PathSymbol[]),
    };
    const result = await active.sendRequest("textDocument/inlineCompletion", params, token);
    if (token.isCancellationRequested) return null;
    return active.protocol2CodeConverter.asInlineCompletionResult(result as never, token);
  };
}

async function gather(document: vscode.TextDocument, position: vscode.Position, settings: ContextSettings) {
  const sources: Promise<ExtraContext | undefined>[] = [];
  if (settings.signature) sources.push(within(settings.timeoutMs, signature(document, position)));
  return (await Promise.all(sources)).filter((extra) => extra !== undefined);
}

function within<T>(ms: number, work: Thenable<T | undefined>): Promise<T | undefined> {
  return Promise.race([
    Promise.resolve(work).catch(() => undefined),
    new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), ms)),
  ]);
}

async function signature(document: vscode.TextDocument, position: vscode.Position): Promise<ExtraContext | undefined> {
  const help = await vscode.commands.executeCommand<vscode.SignatureHelp | undefined>(
    "vscode.executeSignatureHelpProvider", document.uri, position);
  if (!help || help.signatures.length === 0) return undefined;
  const lines = help.signatures.map((item) => {
    const doc = typeof item.documentation === "string" ? item.documentation : item.documentation?.value;
    return doc ? `${item.label}\n  ${doc.split("\n")[0]}` : item.label;
  });
  const path = vscode.workspace.asRelativePath(document.uri);
  return { path: `${path}.signature`, text: `Signatures at the cursor in ${path}:\n${lines.join("\n")}\n` };
}
