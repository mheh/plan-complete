import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One line for the status bar when a completion failed.
public func modelFailure(_ error: any Error, config: Config) -> String {
    switch error {
    case let error as URLError where error.code == .timedOut:
        return "the model server at \(config.baseURL) did not answer in \(config.timeoutMs) ms"
    case is URLError:
        return "no model server at \(config.baseURL)"
    case ProviderError.http(let status, _) where status == 404:
        return "\(config.baseURL) has no \(config.provider == .llamaInfill ? "/infill" : "/v1/completions") endpoint"
    case ProviderError.http(let status, _):
        return "the model server at \(config.baseURL) answered HTTP \(status)"
    default:
        return "\(error)"
    }
}
