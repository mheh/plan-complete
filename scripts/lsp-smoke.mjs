// usage: node scripts/lsp-smoke.mjs BINARY WORKSPACE FILE LINE COL   (LINE, COL zero-based)
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import path from "node:path";

const [bin, workspace, file, line, col] = process.argv.slice(2);
const child = spawn(bin, ["serve"], { stdio: ["pipe", "pipe", "inherit"] });
const uri = pathToFileURL(path.resolve(workspace, file)).href;
let buffer = Buffer.alloc(0);
const waiting = new Map();

child.stdout.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  for (;;) {
    const end = buffer.indexOf("\r\n\r\n");
    if (end < 0) return;
    const length = Number(/Content-Length: (\d+)/i.exec(buffer.subarray(0, end).toString())[1]);
    if (buffer.length < end + 4 + length) return;
    const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length).toString());
    buffer = buffer.subarray(end + 4 + length);
    waiting.get(message.id)?.(message);
  }
});

let nextID = 1;
const send = (method, params, isRequest = true) => {
  const id = isRequest ? nextID++ : undefined;
  const body = JSON.stringify({ jsonrpc: "2.0", ...(id ? { id } : {}), method, params });
  child.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
  return id ? new Promise((resolve) => waiting.set(id, resolve)) : Promise.resolve();
};

const timer = setTimeout(() => { console.error("timeout"); process.exit(1); }, 30000);
const init = await send("initialize", { rootUri: pathToFileURL(path.resolve(workspace)).href, capabilities: {} });
console.log("capabilities:", JSON.stringify(init.result.capabilities));
await send("initialized", {}, false);
await send("textDocument/didOpen", { textDocument: { uri, languageId: "swift", version: 1, text: readFileSync(path.resolve(workspace, file), "utf8") } }, false);
const started = Date.now();
const reply = await send("textDocument/inlineCompletion", { textDocument: { uri }, position: { line: Number(line), character: Number(col) }, context: { triggerKind: 2 } });
console.log(`completion (${Date.now() - started} ms):`, JSON.stringify(reply.result.items));
await send("shutdown", null);
await send("exit", null, false);
child.on("exit", (code) => { clearTimeout(timer); console.log("exit code:", code); });
