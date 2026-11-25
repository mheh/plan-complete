import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct JSONPoster: Sendable {
    var session: URLSession
    var timeout: TimeInterval
    var apiKey: String?

    func post(_ url: URL, body: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try body.encoded()
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do { return try JSONValue.decode(data) }
        catch { throw ProviderError.badResponse(String(decoding: data, as: UTF8.self)) }
    }
}

func endpoint(_ base: String, _ path: String) throws -> URL {
    var trimmed = base
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    // /infill lives at the server root, not under /v1.
    if path == "/infill", trimmed.hasSuffix("/v1") { trimmed.removeLast(3) }
    if path.hasPrefix("/v1/"), trimmed.hasSuffix("/v1") { trimmed.removeLast(3) }
    guard let url = URL(string: trimmed + path), url.scheme != nil else { throw ProviderError.badURL(base) }
    return url
}
