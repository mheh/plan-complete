import Testing
@testable import PlanCompleteCore

@Suite struct ScopeTests {
    let source = """
    import Foundation

    actor ResponseCache {
        private var items: [URL: Data] = [:]

        init(capacity: Int) {
            self.capacity = capacity
        }

        convenience init() {
            self.init(
        }

        func store(_ data: Data, for key: URL) async {
        }
    }
    """

    @Test func selfInit() {
        let doc = TextDocument(path: "Cache.swift", text: source)
        let context = doc.context(line: 10, utf16Column: 18, prefixLines: 80, suffixLines: 40)
        #expect(context.linePrefix == "        self.init(")
        #expect(context.scope.callee == "init")
        #expect(context.scope.outline == ["actor ResponseCache {", "convenience init() {"])
        #expect(context.scope.definitions == ["init(capacity: Int) {", "convenience init() {"])
        let summary = context.scope.summary(path: "Cache.swift")
        #expect(summary?.text.contains("init(capacity: Int)") == true)
    }

    @Test func callees() {
        #expect(ScopeContext.calleeName(in: "cache.store(data, ") == "store")
        #expect(ScopeContext.calleeName(in: "foo(bar(1), ") == "foo")
        #expect(ScopeContext.calleeName(in: "let x = 1") == nil)
        #expect(ScopeContext.calleeName(in: "xs[") == nil)
    }

    @Test func declarations() {
        #expect(ScopeContext.isDeclaration(of: "store", "func store(_ data: Data) async {"))
        #expect(ScopeContext.isDeclaration(of: "store", "def store(self, data):"))
        #expect(!ScopeContext.isDeclaration(of: "store", "cache.store(data)"))
        #expect(!ScopeContext.isDeclaration(of: "store", "restore(x)"))
    }

    @Test func pythonScope() {
        let text = "class Cache:\n    def put(self, k):\n        self.\n"
        let context = TextDocument(path: "c.py", text: text).context(line: 2, utf16Column: 13, prefixLines: 10, suffixLines: 5)
        #expect(context.scope.outline == ["class Cache:", "def put(self, k):"])
    }
}
