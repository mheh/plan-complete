import Foundation
import PlanCompleteCore

extension LSPServer {
    public static func runStdio() async {
        let output = StdoutWriter()
        let server = LSPServer(send: { message in await output.write(message) })
        var reader = MessageReader()
        for await chunk in stdinChunks() {
            reader.append(chunk)
            while true {
                do {
                    guard let message = try reader.next() else { break }
                    await server.handle(message)
                    if let code = await server.exitCode { exit(code) }
                } catch {
                    FileHandle.standardError.write(Data("plan-complete: bad message: \(error)\n".utf8))
                }
            }
        }
        exit(await server.exitCode ?? 0)
    }

    static func stdinChunks() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let thread = Thread {
                while true {
                    let data = FileHandle.standardInput.availableData
                    if data.isEmpty { break }
                    continuation.yield(data)
                }
                continuation.finish()
            }
            thread.start()
        }
    }
}

actor StdoutWriter {
    func write(_ message: JSONValue) {
        guard let data = try? MessageReader.frame(message) else { return }
        FileHandle.standardOutput.write(data)
    }
}
