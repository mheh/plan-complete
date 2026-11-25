import * as vscode from "vscode";

export interface PathSymbol {
  name: string;
  kind: number;
}

/// The symbols that enclose a position, outermost first, from the real language server.
/// The outline of a document is kept until the document changes.
export class SymbolPaths {
  private readonly outlines = new Map<string, { version: number; symbols: Thenable<vscode.DocumentSymbol[]> }>();

  constructor(subscriptions: vscode.Disposable[]) {
    subscriptions.push(
      vscode.workspace.onDidCloseTextDocument((document) => this.outlines.delete(document.uri.toString())),
    );
  }

  async at(document: vscode.TextDocument, position: vscode.Position): Promise<PathSymbol[]> {
    const path: PathSymbol[] = [];
    let level = await this.outline(document);
    for (;;) {
      const inside = level.find((symbol) => symbol.range.contains(position));
      if (!inside) return path;
      // The protocol counts kinds from 1, VS Code from 0.
      path.push({ name: inside.name, kind: inside.kind + 1 });
      level = inside.children;
    }
  }

  private outline(document: vscode.TextDocument): Thenable<vscode.DocumentSymbol[]> {
    const key = document.uri.toString();
    const known = this.outlines.get(key);
    if (known?.version === document.version) return known.symbols;
    const symbols = vscode.commands
      .executeCommand<(vscode.DocumentSymbol | vscode.SymbolInformation)[] | undefined>(
        "vscode.executeDocumentSymbolProvider", document.uri)
      .then((found) => (found ?? []).filter((item): item is vscode.DocumentSymbol => "children" in item));
    this.outlines.set(key, { version: document.version, symbols });
    return symbols;
  }
}
