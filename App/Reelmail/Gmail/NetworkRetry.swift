import Foundation

/// Retries a Gmail request when the connection drops for a moment ("The network connection was lost"), which happened
/// when many put-aways reached Gmail at once. Only transient network errors are retried, at most twice; Gmail's own
/// answers (refusals, rate limits) are handled by the callers.
enum NetworkRetry {
    static let waits: [UInt64] = [1, 2]

    static func isTransient(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [.networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed].contains(e.code)
    }

    static func data(for request: URLRequest,
                     transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do { return try await transport(request) }
            catch where isTransient(error) && attempt < waits.count {
                try await Task.sleep(nanoseconds: waits[attempt] * 1_000_000_000)
                attempt += 1
            }
        }
    }
}
