import Foundation

/// What to tell the owner when a refresh fails. Pure, so the wording can be tested.
/// Loaded mail is never replaced and demo mail is never substituted; the message only explains and offers Try again.
enum RefreshProblem {
    static func message(for error: Error) -> String {
        let kept = "Your loaded mail is unchanged."
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "Can't reach Gmail. Check the connection. " + kept
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Gmail didn't answer in time. " + kept
            default:
                return "The connection to Gmail dropped. " + kept
            }
        }
        if let gmail = error as? GmailService.GmailError {
            switch gmail {
            case .refused(let code, let detail) where code == 429 || detail.isRateLimit:
                return "Gmail asked Lovely to slow down. Try again in a minute. " + kept
            case .refused(let code, _), .http(let code):
                if (500...599).contains(code) { return "Gmail is having trouble right now. Try again shortly. " + kept }
                return "Gmail refused the refresh (code \(code)). " + kept
            default:
                return gmail.localizedDescription + " " + kept
            }
        }
        return "Gmail could not refresh. " + kept
    }
}
