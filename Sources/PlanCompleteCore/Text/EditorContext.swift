/// What the editor got from the real language server for one request.
public struct EditorContext: Sendable, Equatable {
    /// Text for the prompt, for example signature help.
    public var files: [ExtraFile]
    public var symbols: SymbolPath

    public init(files: [ExtraFile] = [], symbols: SymbolPath = .init()) {
        self.files = files
        self.symbols = symbols
    }
}
