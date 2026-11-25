import Testing
@testable import PlanCompleteCore

@Suite struct ModelTests {
    func body(prefix: String) -> JSONValue {
        let request = CompletionRequest(path: "a.swift", prefix: prefix, suffix: "\n}", extras: [], maxTokens: 64)
        return LlamaInfillProvider(config: Config()).body(for: request)
    }

    @Test func theIndentOfTheCursorLineGoesToTheServer() {
        #expect(body(prefix: "struct A {\n    func b() {\n        let c = ")["n_indent"] == 8)
        #expect(body(prefix: "struct A {\n    ")["n_indent"] == 4)
        #expect(body(prefix: "struct A {\n\tfunc ")["n_indent"] == 1)
        #expect(body(prefix: "let a = ")["n_indent"] == 0)
        #expect(body(prefix: "")["n_indent"] == 0)
    }

    @Test func theCursorLineStaysInThePrefix() {
        let sent = body(prefix: "struct A {\n    func ")
        #expect(sent["input_prefix"] == "struct A {\n    func ")
        #expect(sent["prompt"] == nil)
    }
}
