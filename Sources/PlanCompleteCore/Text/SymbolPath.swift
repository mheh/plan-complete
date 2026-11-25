/// The symbols that enclose the cursor, outermost first, as the real language server reports them.
public struct SymbolPath: Sendable, Equatable, CustomStringConvertible {
    public struct Symbol: Sendable, Equatable {
        public var name: String
        public var isType: Bool

        public init(name: String, isType: Bool) {
            self.name = name
            self.isType = isType
        }

        /// `kind` is a `SymbolKind` of the Language Server Protocol.
        public init(name: String, lspKind kind: Int) {
            self.init(name: name, isType: SymbolPath.typeKinds.contains(kind))
        }

        /// `store(_:for:)` gives `store`. Nil for a name that many types share.
        var identifier: String? {
            guard let word = GuideSelector.symbolParts(name).first,
                  word.count >= 4, !SymbolPath.genericNames.contains(word)
            else { return nil }
            return word
        }
    }

    public var symbols: [Symbol]

    public init(_ symbols: [Symbol] = []) {
        self.symbols = symbols
    }

    /// `ResponseCache>store()`: a name that ends in `()` is a member, any other is a type.
    public init(parsing text: String) {
        self.init(text.split(separator: ">").map { part in
            let name = part.trimmingCharacters(in: .whitespaces)
            return Symbol(name: name, isType: !name.hasSuffix(")"))
        })
    }

    public var isEmpty: Bool { symbols.isEmpty }
    public var description: String { symbols.map(\.name).joined(separator: " > ") }

    var typeNames: Set<String> { Set(symbols.filter(\.isType).compactMap(\.identifier)) }
    var memberName: String? { symbols.last.flatMap { $0.isType ? nil : $0.identifier } }

    /// File, module, namespace, package, class, enum, interface, object, struct.
    static let typeKinds: Set<Int> = [1, 2, 3, 4, 5, 10, 11, 19, 23]
    static let genericNames: Set<String> = [
        "init", "deinit", "body", "description", "constructor", "main", "self", "setup", "test", "__init__",
    ]
}
