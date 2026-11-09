import Foundation

/// Old login codes, new-device checks and password resets: the one kind of mail worth clearing out. Lovely never
/// clears it on its own; the owner opens the list, sees every message, and moves them to Gmail's Trash (recoverable
/// for 30 days) with one tap and one Undo. Pure query and filter here, so they are tested.
enum AccountsCleanup {
    static let defaultAgeDays = 90
    static let limit = 200

    /// The Gmail search: Lovely's Accounts category, plus the usual code and device subjects, older than the age.
    static func query(ageDays: Int = defaultAgeDays) -> String {
        let subjects = ["verification code", "security code", "sign-in code", "one-time", "new device", "new sign-in", "password reset",
                        "verify your new device", "login code"]
        let either = subjects.map { "subject:\"\($0)\"" }.joined(separator: " OR ")
        return "older_than:\(ageDays)d -in:trash -is:starred (label:lovely-accounts OR \(either))"
    }

    /// A second check on what Gmail returned: subjects must look like account notices, and never from a person
    /// the owner writes to (their mail is never cleaned up here).
    static func keep(_ stub: MessageStub, knownPeople: Set<String>) -> Bool {
        if knownPeople.contains(stub.fromAddress.lowercased()) { return false }
        let s = stub.subject.lowercased()
        return DrawerGuesser.hasAny(s, DrawerGuesser.accountWords) || ["code", "sign-in", "sign in", "login", "password", "device"].contains { s.contains($0) }
    }
}
