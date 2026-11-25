import Foundation
import PlanCompleteCore

/// LSP base protocol: `Content-Length` headers, then a JSON body.
public struct MessageReader: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) { buffer.append(data) }

    public mutating func next() throws -> JSONValue? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }
        let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var length: Int?
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        guard let length else {
            buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
            throw FramingError.missingLength
        }
        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = buffer[bodyStart..<bodyEnd]
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return try JSONValue.decode(Data(body))
    }

    public static func frame(_ message: JSONValue) throws -> Data {
        let body = try message.encoded()
        var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}

public enum FramingError: Error { case missingLength }
