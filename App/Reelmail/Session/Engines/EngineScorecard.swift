import Foundation

/// Fictional owner sentences about fictional mail, each with the action it should become. Run against every enabled
/// engine in Testing tools; the quick commands are also checked in unit tests. A change to the playbook should not
/// lower any engine's score.
enum EngineScorecard {
    struct Case: Identifiable, Sendable {
        let id: String
        let said: String
        let item: SessionItem
        let action: String
        let drawer: String?
        /// The quick commands must answer this one without any model.
        let quick: Bool
    }

    struct Result: Identifiable, Sendable {
        let id: String
        let passed: Bool
        let got: String
    }

    static let kids = [KidProfile(id: "k1", name: "Avery", school: "Pine Ridge Middle", teacherNames: [], activities: ["band"])]

    private static func item(_ id: String, from: String, address: String, subject: String, text: String, person: Bool = false,
                             section: FeedSection = .updates, ask: String? = nil, drawer: DrawerChoice? = nil) -> SessionItem {
        let m = SessionMessage(id: id, threadId: "t-" + id, fromName: from, fromAddress: address, subject: subject,
                               date: Date(timeIntervalSince1970: 2_000_000_000), text: text, section: section, category: .updates,
                               isPerson: person, ask: ask, isHealth: false, isFirstTimeSender: false, asksForAction: false, hasDates: false)
        return SessionItem(message: m, group: person ? .oneAtATime : .quick,
                           suggestion: drawer.map { .putAway($0) } ?? .decide,
                           drawer: drawer.map { DrawerGuess(choice: $0, confidence: .rule, reason: "") }, heldBecause: nil)
    }

    static let statement = item("stmt", from: "Harbor Bank", address: "alerts@harborbank.example", subject: "Your statement is ready",
                                text: "Your October statement is ready. Log in to view it.", drawer: DrawerChoice(.money))
    static let school = item("school", from: "Pine Ridge Middle", address: "office@pineridge.example", subject: "Winter concert Dec 12",
                             text: "The band winter concert is Thursday, Dec 12 at 6:30 PM in the gym.", drawer: DrawerChoice(.kids, child: "Avery"))
    static let newsletter = item("nl", from: "Weekend Reads", address: "hello@weekendreads.example", subject: "Five long reads",
                                 text: "This week: five long reads for a slow Sunday.", section: .reading)
    static let ask = item("ask", from: "Dana Brooks", address: "dana@lovely.example", subject: "Review on Thursday?",
                          text: "Hi, can you do Thursday at 2 for the review? Dana", person: true, section: .waiting,
                          ask: "Can you do Thursday at 2 for the review?", drawer: DrawerChoice(.personal))
    static let lease = item("lease", from: "Oak Court Leasing", address: "leasing@oakcourt.example", subject: "Please eSign your renewal",
                            text: "Your lease renewal is ready. Please eSign by Nov 20 on our resident portal.", drawer: DrawerChoice(.home))
    static let shipped = item("ship", from: "Trail Outfitters", address: "orders@trailoutfitters.example", subject: "Your order has shipped",
                              text: "Your running shoes have shipped and arrive Monday.", drawer: DrawerChoice(.orders))

    static let cases: [Case] = [
        Case(id: "q1", said: "file it in money", item: statement, action: "put_away", drawer: "Money", quick: true),
        Case(id: "q2", said: "kids avery", item: school, action: "put_away", drawer: "Kids/Avery", quick: true),
        Case(id: "q3", said: "archive", item: newsletter, action: "archive", drawer: nil, quick: true),
        Case(id: "q3t", said: "Delete.", item: newsletter, action: "trash", drawer: nil, quick: true),
        Case(id: "q4", said: "later this weekend", item: shipped, action: "later", drawer: nil, quick: true),
        Case(id: "q5", said: "leave it", item: lease, action: "leave_unread", drawer: nil, quick: true),
        Case(id: "q6", said: "money drawer", item: statement, action: "put_away", drawer: "Money", quick: true),
        Case(id: "q7", said: "Skip.", item: ask, action: "skip", drawer: nil, quick: true),
        Case(id: "e1", said: "tell her Thursday at 2 works", item: ask, action: "reply", drawer: nil, quick: false),
        Case(id: "e2", said: "say no thanks, I'm booked all week", item: ask, action: "reply", drawer: nil, quick: false),
        Case(id: "e3", said: "yes", item: ask, action: "reply", drawer: nil, quick: false),
        Case(id: "e4", said: "have an agent fill out the renewal for me", item: lease, action: "handoff", drawer: nil, quick: false),
        Case(id: "e5", said: "put the concert on my calendar and file it under kids", item: school, action: "add_date", drawer: "Kids", quick: false),
        Case(id: "e6", said: "toss it in orders", item: shipped, action: "put_away", drawer: "Orders", quick: false),
        Case(id: "e7", said: "bring this back to me tomorrow morning", item: lease, action: "later", drawer: nil, quick: false),
    ]

    /// Drawer names compare loosely: "Kids" matches "Kids/Avery", since either is a fair answer for a one-child family.
    static func check(_ c: Case, _ command: SessionCommand) -> Result {
        let actionOK = command.action.lowercased() == c.action
        var drawerOK = true
        if let want = c.drawer?.lowercased() {
            let got = (command.drawer ?? "").lowercased()
            let suggested: String = c.item.drawer.map { guess in guess.choice.child.map { name in "kids/" + name.lowercased() } ?? guess.choice.drawer.title.lowercased() } ?? ""
            drawerOK = got == want || got.hasPrefix(want + "/") || want.hasPrefix(got + "/") || (got.isEmpty && suggested.hasPrefix(want))
        }
        return Result(id: c.id, passed: actionOK && drawerOK, got: command.action + (command.drawer.map { " " + $0 } ?? ""))
    }
}
