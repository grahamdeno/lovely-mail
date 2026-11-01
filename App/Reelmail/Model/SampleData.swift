import Foundation

/// Fake people and neutral emails for sample mode, previews, the Summary Lab and tests.
/// All addresses use reserved .example domains.
enum SampleData {
    static let me = Person(id: "me", name: "Graham D", email: "graham@reelmail.example", hue: 0.62)

    static let maya = Person(id: "maya", name: "Maya Chen", email: "maya@chen-family.example", hue: 0.02)
    static let dana = Person(id: "dana", name: "Dana Brooks", email: "dana@riversidefc.example", hue: 0.33)
    static let hillview = Person(id: "hillview", name: "Hillview Middle School", email: "office@hillview-ms.example", hue: 0.58)
    static let priya = Person(id: "priya", name: "Priya Raman", email: "priya@studiopine.example", hue: 0.85)
    static let ledgerly = Person(id: "ledgerly", name: "Ledgerly Receipts", email: "receipts@ledgerly.example", hue: 0.12)
    static let weekendRead = Person(id: "weekendread", name: "The Weekend Read", email: "hello@weekendread.example", hue: 0.08)
    static let leo = Person(id: "leo", name: "Leo Park", email: "leo.park@mailbox.example", hue: 0.47)
    static let northwind = Person(id: "northwind", name: "Northwind Air", email: "trips@northwind-air.example", hue: 0.55)
    static let juniper = Person(id: "juniper", name: "Juniper Dental", email: "care@juniperdental.example", hue: 0.40)
    static let rosa = Person(id: "rosa", name: "Rosa Marin", email: "rosa.m@familymail.example", hue: 0.95)
    static let sam = Person(id: "sam", name: "Sam Ortiz", email: "sam@ortiz-builds.example", hue: 0.15)
    static let library = Person(id: "library", name: "Oakridge Library", email: "notices@oakridge-library.example", hue: 0.30)
    static let nora = Person(id: "nora", name: "Nora Lindqvist", email: "nora@lindqvist.example", hue: 0.70)
    static let security = Person(id: "security", name: "Account Security", email: "no-reply@accounts.example", hue: 0.0)
    static let ben = Person(id: "ben", name: "Ben Adeyemi", email: "ben@adeyemi-co.example", hue: 0.52)
    static let brightwater = Person(id: "brightwater", name: "Brightwater Utilities", email: "billing@brightwater.example", hue: 0.60)
    static let riversideNews = Person(id: "riversidenews", name: "Riverside FC", email: "news@riversidefc.example", hue: 0.36)
    static let tess = Person(id: "tess", name: "Tess Morgan", email: "tess@morgan-design.example", hue: 0.78)
    static let parcel = Person(id: "parcel", name: "Parcel Point", email: "updates@parcelpoint.example", hue: 0.10)

    private static let now = Date()
    private static func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    private static func mail(_ id: String, _ from: Person, _ subject: String, _ hours: Double,
                             _ body: String, thread: String? = nil, unread: Bool = true) -> Email {
        Email(id: id, threadId: thread ?? "t-\(id)", from: from, to: [me.email], subject: subject,
              date: ago(hours), body: body, isUnread: unread)
    }

    /// About 20 incoming emails, newest first.
    static let emails: [Email] = [
        mail("e01", maya, "Saturday hike?", 1, """
        Hi Graham,
        A few of us are doing the Ridge Loop trail this Saturday, Nov 8, starting at 9am. Want to join? Let me know by Thursday so I can plan carpools.
        Maya
        """, thread: "t-hike"),
        mail("e02", dana, "Final game day and team photo", 2, """
        Hi families,
        Our season final is on Nov 7 at Lakeside Field, warmups at 8:30. Team photos are right after the game. Please confirm whether your player can make it.
        Thanks, Coach Dana
        """),
        mail("e03", hillview, "Field trip forms received", 3, """
        Hello,
        This is a confirmation that the permission forms for the 8th grade science trip on Mar 24 were received. No further action is needed.
        Hillview Middle School Office
        """, unread: false),
        mail("e04", priya, "Second draft of the brochure", 4, """
        Hi Graham,
        The second draft of the brochure layout is in the shared folder. Could you look at the two cover options and tell me which one you prefer? I'd like to send it to print by Nov 12.
        Thanks, Priya
        """, thread: "t-brochure"),
        mail("e05", ledgerly, "Your receipt from Corner Market", 5, """
        Thanks for your purchase.
        Total: $70.15 paid on Oct 29. Items: groceries and household supplies. This is an automated receipt; replies are not monitored.
        """, unread: false),
        mail("e06", weekendRead, "This week: slow mornings, small gardens", 7, """
        Good morning,
        In this issue we look at why slow mornings are back, a beginner's guide to balcony gardens, and three soups for cold nights. Read it online any time. Unsubscribe at any time.
        """),
        mail("e07", leo, "Photos from the lake", 9, """
        Hey!
        Finally uploaded the photos from the lake weekend. The sunset ones came out great. The album is in the shared folder.
        Leo
        """, unread: false),
        mail("e08", northwind, "Your trip to Denver is confirmed", 11, """
        Hello Graham,
        Your flight NW 482 departs on Nov 21 at 7:45am from Gate B12. Check-in opens 24 hours before departure. Have a great trip.
        """),
        mail("e09", juniper, "Appointment reminder", 14, """
        Hello,
        This is a reminder of your cleaning appointment on Nov 14 at 3:30pm. Please call the front desk if you need to reschedule.
        """),
        mail("e10", rosa, "Thanksgiving plans", 18, """
        Hi sweetheart,
        We're hosting this year on Nov 27. Can you bring a dessert? Also, how many are coming from your side?
        Love, Rosa
        """, thread: "t-thanks"),
        mail("e11", sam, "Quote for the deck repair", 22, """
        Hi Graham,
        Here is the quote for the deck repair: $1,240 for materials and labor. We can start the week of Dec 1 if that works for you. Would you like to go ahead?
        Sam
        """),
        mail("e12", library, "Your hold is ready", 26, """
        Hello,
        The book you placed on hold, The Quiet Garden, is ready for pickup at the front desk. It will be held until Nov 6.
        """),
        mail("e13", nora, "Coffee next week?", 30, """
        Hi Graham,
        It's been ages! Are you free for coffee next Tuesday or Wednesday morning? I found a new place near the park.
        Nora
        """),
        mail("e14", security, "Your verification code", 33, """
        Hello,
        Your verification code is 482913. It expires in 10 minutes. If you didn't request this, you can ignore this email.
        """, unread: false),
        mail("e15", ben, "Notes from Thursday's call", 40, """
        Hi Graham,
        Thanks for the call on Thursday. We agreed to keep the launch on Dec 3 and revisit pricing in January. I'll share the updated plan by Friday, no action needed from you yet.
        Ben
        """, unread: false),
        mail("e16", brightwater, "Your November statement", 48, """
        Hello,
        Your statement is ready. Amount due: $86.40, due on Nov 18. Autopay is on, so no action is needed.
        """),
        mail("e17", riversideNews, "Season recap newsletter", 55, """
        Hi Riverside families,
        Highlights from the fall season, a thank-you to our volunteers, and winter training dates are inside. Unsubscribe anytime.
        """, unread: false),
        mail("e18", tess, "Quick question about Friday", 60, """
        Hey Graham,
        Are we still on for the workshop Friday at 2pm? I can bring the projector if you need it.
        Tess
        """),
        mail("e19", maya, "Re: Saturday hike?", 0.5, """
        Also, I can pick you up on the way if that helps. Just say the word.
        """, thread: "t-hike"),
        mail("e20", parcel, "Your package is on the way", 70, """
        Hello,
        Your package from Field & Fern is out for delivery and should arrive by Oct 31 before 8pm. Track it in the app.
        """, unread: false),
    ].sorted { $0.date > $1.date }

    /// A few messages "from me" so threads read like a conversation. Never sent anywhere.
    static let sentByMe: [Email] = [
        Email(id: "s01", threadId: "t-hike", from: me, to: [maya.email], subject: "Re: Saturday hike?",
              date: ago(0.8), body: "Sounds fun. Checking the weekend and will confirm tomorrow.", isUnread: false, isFromMe: true),
        Email(id: "s02", threadId: "t-brochure", from: me, to: [priya.email], subject: "Re: First draft",
              date: ago(80), body: "Looks great so far. Can we try a lighter cover?", isUnread: false, isFromMe: true),
        Email(id: "s03", threadId: "t-thanks", from: me, to: [rosa.email], subject: "Re: Holidays",
              date: ago(120), body: "Can't wait. We'll sort out who's coming soon.", isUnread: false, isFromMe: true),
    ]

    /// Pasteable sample for the Summary Lab text box.
    static let labPasteExample = """
    From: Jordan Lee <jordan@example.com>
    Subject: Book club moved to Thursday

    Hi all,
    We're moving book club to Thursday, Nov 13 at 7pm because the library room is booked. Can everyone still make it? Reply so I know how many chairs to set up.
    Jordan
    """
}
