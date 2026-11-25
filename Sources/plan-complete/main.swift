import Foundation
import PlanCompleteCore
import PlanCompleteLSP

let usage = """
plan-complete \(PlanComplete.version)

usage:
  plan-complete serve                       LSP over stdio
  plan-complete enable [DIR]                opt a repository in: write .plan-complete.json and a starter PLAN.md
  plan-complete config [DIR]                print the settings in effect, and where they come from
  plan-complete probe FILE:LINE:COL [opts]  one completion; LINE and COL are 1-based
    --root DIR       workspace root (default: nearest parent with .plan-complete.json, PLAN.md or .git)
    --no-guide       leave the plan out, and run even when the plan rule is off
    --no-scope       leave the scope summary out
    --prompt         print the request instead of calling the model
    --raw            also print the raw model text
  plan-complete --version
"""

func printError(_ text: String) {
    FileHandle.standardError.write(Data("\(text)\n".utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "serve":
    await LSPServer.runStdio()
case "probe":
    exit(await probe(Array(arguments.dropFirst())))
case "enable":
    exit(enable(directory(arguments.dropFirst().first)))
case "config":
    exit(showConfig(directory(arguments.dropFirst().first)))
case "--version", "version":
    print(PlanComplete.version)
default:
    print(usage)
    exit(arguments.isEmpty || arguments.first == "--help" ? 0 : 2)
}
