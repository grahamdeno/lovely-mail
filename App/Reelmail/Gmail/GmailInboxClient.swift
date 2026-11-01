import Foundation

@MainActor
protocol GmailInboxClient: AnyObject {
    var config: GmailConfig { get }
    var isSignedIn: Bool { get }
    func fetchInbox(maxResults: Int) async throws -> [Email]
    func signIn() async throws
    func signOut()
}

extension GmailService: GmailInboxClient {}
