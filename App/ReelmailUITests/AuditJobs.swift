import XCTest

/// The ten jobs a person does in Lovely, each tapping through the app in the real order.
/// Every step has a named screenshot. Every outcome is asserted, including what the fake Gmail was asked to do.
final class AuditJobs: AuditCase {

    // MARK: Job 1: morning check (open and clear five emails)

    func testJob01_Morning_Light() { morningCheck(.light) }
    func testJob01_Morning_Dark() { morningCheck(.dark) }
    func testJob01_Morning_Neon() { morningCheck(.neon) }
    func testJob01_Morning_LargeText() { morningCheck(.largeText) }
    func testJob01_Morning_Expired() { errorWalk(1, "morning", "Morning check", .expired) }
    func testJob01_Morning_NoPermission() { errorWalk(1, "morning", "Morning check", .noPermission) }
    func testJob01_Morning_Offline() { errorWalk(1, "morning", "Morning check", .offline) }
    func testJob01_Morning_Empty() { errorWalk(1, "morning", "Morning check", .empty) }

    private func morningCheck(_ c: AuditCondition) {
        begin(1, "morning", "Morning check: open and clear five emails", c)
        guard waitForHome() else { return }
        check(app.buttons["home.nextup.open"].waitForExistence(timeout: 20) || locate(app.buttons["home.nextup.open"]), "Home shows a Next up card with mail to clear")
        shot("home", screen: "Home")

        // First one: open it, read it, tap Done.
        if tap(app.buttons["home.nextup.open"], "Next up card") {
            check(app.buttons["email.done"].waitForExistence(timeout: 8), "The open email offers Done")
            shot("email-open", screen: "Open email")
            if tap(app.buttons["email.done"], "Done in the open email") {
                check(app.buttons["home.nextup.open"].waitForExistence(timeout: 8) || locate(app.buttons["home.nextup.open"]), "Back on Home with the next email waiting")
                shot("after-first-done")
            }
        }
        mark("first email cleared")

        // Four more, straight from Home.
        for n in 2...5 {
            if tap(app.buttons["home.nextup.done"], "Done on email \(n)") {
                settle(0.6)
                if n == 3 { shot("undo-offer", screen: "Home with Undo") }
            }
        }
        mark("five emails cleared")
        shot("after-five")
        check(waitForRequest("CLIENT markRead", atLeast: 5), "Gmail was told five messages are read", "saw \(count("CLIENT markRead"))")
        check(count("CLIENT markUnread") == 0, "Nothing was marked unread by accident")
        check(count("/messages/send") == 0, "Nothing was sent")
        check(job.taps <= 11, "Five emails clear in 11 taps or fewer", "took \(job.taps)")
    }

    // MARK: Job 2: find an email from a person

    func testJob02_FindPerson() {
        begin(2, "find-person", "Find an email from a person", .light)
        guard waitForHome() else { return }
        shot("home")
        if tap(app.buttons["tab.people"], "People tab") {
            shot("people", screen: "People")
            let field = app.textFields["Find a person or organization"]
            enter("Dana", into: field, "Find a person")
            settle()
            shot("typed-dana")
            let result = text(containing: "Dana Brooks")
            check(result.waitForExistence(timeout: 8), "Dana Brooks appears in the results")
            if tap(result, "Dana Brooks") {
                shot("person", screen: "Person")
                check(text(containing: "Carpool").waitForExistence(timeout: 8), "Dana's mail 'Carpool Thursday?' is shown")
            }
        }
        mark("found the email")
        check(job.taps <= 4, "Finding a person takes 4 taps or fewer", "took \(job.taps)")
    }

    // MARK: Job 3: reply and send, with the 10-second Undo

    func testJob03_ReplyAndSend() {
        begin(3, "reply-send", "Reply and send, including Undo", .light)
        guard waitForHome() else { return }
        openMail(subject: "Carpool", rowID: "fx-dana")
        mark("opened Dana's email")

        // First reply: send, then Undo inside the 10 seconds. Nothing may go out.
        replyAndConfirm(label: "first", body: " Thursday works for me.")
        if app.buttons["undo.banner"].waitForExistence(timeout: 8) {
            shot("undo-offer")
            if tap(app.buttons["undo.banner"], "Undo") {
                mark("undid the send")
                settle(1)
                shot("after-undo")
            }
        } else {
            check(false, "An Undo bar appears after confirming a send")
        }
        Thread.sleep(forTimeInterval: 12)
        check(count("/messages/send") == 0, "Undo inside 10 seconds sent nothing", "saw \(count("/messages/send")) sends")

        // Second reply: let the 10 seconds pass. Exactly one message goes, to Dana.
        if !app.buttons["email.reply"].exists { openMail(subject: "Carpool", rowID: "fx-dana") }
        replyAndConfirm(label: "second", body: " Thursday works for me.")
        shot("waiting-10s")
        check(waitForRequest("POST /messages/send", timeout: 20), "After 10 seconds the reply is sent")
        check(count("POST /messages/send") == 1, "Exactly one message was sent", "saw \(count("POST /messages/send"))")
        check(fixtureLines().contains { $0.contains("POST /messages/send") && $0.contains("to=dana@riversidefc.example") }, "The reply went to Dana only")
        shot("after-send")
        mark("sent")
    }

    /// Opens a message from Home: through its row if it shows, otherwise through Search.
    private func openMail(subject: String, rowID: String) {
        let row = app.buttons["mail.row." + rowID]
        _ = locate(row)
        if row.exists && row.isHittable {
            shot("home-scrolled")
            tap(row, "mail row \(subject)")
        } else if app.buttons["home.waiting.all"].exists || locate(app.buttons["home.waiting.all"]) {
            // Home shows two Waiting on you rows; the rest are behind "See all".
            tap(app.buttons["home.waiting.all"], "See all waiting on you")
            let listed = app.buttons["mail.row." + rowID]
            if !locate(listed) { tap(text(containing: subject), "row \(subject) in the full list") } else { tap(listed, "row \(subject) in the full list") }
        } else {
            note("The row for \(subject) was not reachable on Home after 6 swipes; used Search.")
            app.swipeDown(); app.swipeDown()
            tap(app.buttons["tab.search"], "Search tab")
            enter(subject, into: app.textFields["People, organizations, subjects"], "Search")
            tap(text(containing: subject), "search result \(subject)")
        }
        check(app.buttons["email.reply"].waitForExistence(timeout: 10), "The email opens with a Reply button")
        shot("email-open", screen: "Open email")
    }

    private func replyAndConfirm(label: String, body: String) {
        if tap(app.buttons["email.reply"], "Reply") {
            let editor = app.textViews["draft.editor"]
            check(editor.waitForExistence(timeout: 15), "The reply sheet opens with a text box (\(label))")
            shot("reply-sheet-" + label, screen: "Reply sheet")
            let kept = (editor.value as? String)?.contains(body.trimmingCharacters(in: .whitespaces)) ?? false
            if label == "second" { check(kept, "After Undo, Reply brings back the text you typed") }
            if editor.exists && !kept { enter(body, into: editor, "reply text") }
            shot("reply-typed-" + label)
            if tap(app.buttons["draft.send"], "Send") {
                check(app.buttons["preview.confirm"].waitForExistence(timeout: 8), "A preview sheet shows exactly what will be sent (\(label))")
                shot("send-preview-" + label, screen: "Send preview")
                tap(app.buttons["preview.confirm"], "Confirm send")
            }
        }
    }

    // MARK: Job 4: Trash from Home and from an open email, then Undo

    func testJob04_Trash_Light() { trashAndUndo(.light) }
    func testJob04_Trash_Dark() { trashAndUndo(.dark) }
    func testJob04_Trash_Neon() { trashAndUndo(.neon) }
    func testJob04_Trash_LargeText() { trashAndUndo(.largeText) }
    func testJob04_Trash_Expired() { errorWalk(4, "trash", "Trash and Undo", .expired) }
    func testJob04_Trash_NoPermission() { errorWalk(4, "trash", "Trash and Undo", .noPermission) }
    func testJob04_Trash_Offline() { errorWalk(4, "trash", "Trash and Undo", .offline) }
    func testJob04_Trash_Empty() { errorWalk(4, "trash", "Trash and Undo", .empty) }

    private func trashAndUndo(_ c: AuditCondition) {
        begin(4, "trash", "Trash from Home and from an open email, then Undo", c)
        guard waitForHome() else { return }
        check(app.buttons["home.nextup.trash"].waitForExistence(timeout: 20) || locate(app.buttons["home.nextup.trash"]), "Home offers Trash on the Next up card")
        shot("home", screen: "Home")

        // From Home.
        if tap(app.buttons["home.nextup.trash"], "Trash on Home") {
            check(waitForRequest("CLIENT trash", atLeast: 1), "Gmail was asked to move the message to Trash")
            check(app.buttons["undo.banner"].waitForExistence(timeout: 6), "An Undo bar appears after Trash on Home")
            shot("trashed-from-home")
            if tap(app.buttons["undo.banner"], "Undo") {
                check(waitForRequest("CLIENT untrash", atLeast: 1), "Undo brought the message back from Trash")
                shot("undone-from-home")
            }
        }
        mark("Home trash and undo")

        // From an open email.
        if tap(app.buttons["home.nextup.open"], "Next up card") {
            if tap(app.buttons["email.trash"], "Trash in the open email") {
                check(waitForRequest("CLIENT trash", atLeast: 2), "The second Trash reached Gmail")
                check(app.buttons["undo.banner"].waitForExistence(timeout: 6), "An Undo bar appears after Trash in an open email")
                shot("trashed-from-email")
                if tap(app.buttons["undo.banner"], "Undo") {
                    check(waitForRequest("CLIENT untrash", atLeast: 2), "Undo from the email brought the message back")
                    shot("undone-from-email")
                }
            }
        }
        mark("email trash and undo")
        check(count("CLIENT trash") == count("CLIENT untrash"), "Every Trash was undone", "trash \(count("CLIENT trash")), untrash \(count("CLIENT untrash"))")
    }

    // MARK: Job 5: Send to Shoebox

    func testJob05_Shoebox() {
        begin(5, "shoebox", "Send an email to Shoebox", .light)
        guard waitForHome() else { return }
        openMail(subject: "Contract draft", rowID: "fx-ben")
        if tap(app.buttons["email.more"], "More actions") {
            let item = app.buttons["Send to Shoebox"]
            check(item.waitForExistence(timeout: 5), "'Send to Shoebox' is offered on an ordinary email")
            shot("more-menu", screen: "More actions menu")
            if tap(item, "Send to Shoebox") {
                check(app.buttons["preview.confirm"].waitForExistence(timeout: 8), "A preview shows who gets it")
                check(anyText(containing: ["household-demo@inmyshoebox.com"]), "The preview names the Shoebox address")
                shot("preview", screen: "Shoebox preview")
                tap(app.buttons["preview.confirm"], "Confirm")
                check(app.buttons["undo.banner"].waitForExistence(timeout: 8), "An Undo bar holds the forward for 10 seconds")
                shot("held", screen: "Undo bar")
            }
        }
        mark("forward confirmed")
        check(waitForRequest("POST /messages/send", timeout: 20), "After 10 seconds the forward is sent")
        check(fixtureLines().contains { $0.contains("POST /messages/send") && $0.contains("to=household-demo@inmyshoebox.com") }, "It went to the Shoebox address and nowhere else")
        shot("after-send")
    }

    // MARK: Job 6: decline a new sender

    func testJob06_DeclineNewSender() {
        begin(6, "decline-sender", "Decline a new sender", .light)
        guard waitForHome() else { return }
        let row = app.buttons["home.row.screenedout"]
        _ = locate(row)
        check(row.waitForExistence(timeout: 20), "Home shows a 'New senders' row for the first-time sender")
        shot("home-row", screen: "Home")
        if tap(row, "New senders row") {
            check(app.buttons["screened.decline"].waitForExistence(timeout: 10), "The list offers Accept and Decline")
            check(text(containing: "Jordan Pike").exists, "The first-time sender is Jordan Pike")
            shot("new-senders", screen: "New senders")
            if tap(app.buttons["screened.decline"], "Decline") {
                check(app.buttons["preview.confirm"].waitForExistence(timeout: 8), "A preview says what Decline will do")
                shot("decline-preview", screen: "Decline preview")
                tap(app.buttons["preview.confirm"], "Confirm decline")
                check(!text(containing: "Jordan Pike").waitForExistence(timeout: 3) || !app.buttons["screened.decline"].exists, "Jordan Pike leaves the list at once")
                check(app.buttons["undo.banner"].waitForExistence(timeout: 5), "An Undo bar holds the decline for 10 seconds")
                shot("decline-held", screen: "Undo bar after Decline")
                check(waitForRequest("fx-new/modify", timeout: 25), "The sender's mail was filed under the Lovely label, out of the inbox")
                check(count("DELETE") == 0 && count("trash") == 0, "Nothing was deleted or trashed")
                shot("after-decline")
            }
        }
        mark("declined")
    }

    // MARK: Job 7: Kids view for one child

    func testJob07_Kids() {
        begin(7, "kids", "Kids view for one child", .light)
        guard waitForHome() else { return }
        let row = app.buttons["home.row.kids"]
        _ = locate(row)
        check(row.waitForExistence(timeout: 10), "Home shows a Kids row")
        shot("home-row", screen: "Home")
        if tap(row, "Kids row") {
            shot("kids", screen: "Kids")
            if tap(button(containing: "Ava"), "Ava") {
                shot("ava", screen: "One child")
                check(text(containing: "field trip").waitForExistence(timeout: 8), "Ava's school mail (permission slip) is shown")
                check(!text(containing: "Robotics").exists, "Noah's mail is not shown on Ava's page")
            }
        }
        mark("one child's mail")
    }

    // MARK: Job 8: bills and money alerts

    func testJob08_Money() {
        begin(8, "money", "Bills and money alerts", .light)
        guard waitForHome() else { return }
        let row = app.buttons["home.row.money"]
        _ = locate(row)
        check(row.waitForExistence(timeout: 30), "Home shows a Money row once bills are read")
        shot("home-row", screen: "Home")
        if tap(row, "Money row") {
            shot("money", screen: "Money")
            check(text(containing: "Brightwater").waitForExistence(timeout: 10), "The utility bill is listed")
            check(text(containing: "Cedar").exists, "The failed gas payment is listed")
            check(anyText(containing: ["declined", "failed", "problem", "needs attention", "past due"]), "The payment failure is flagged in plain words")
            goBack()
        }
        mark("money checked")
        let energy = app.buttons["home.row.energy"]
        _ = locate(energy)
        if tap(energy, "Energy row") {
            shot("energy", screen: "Energy")
            check(anyText(containing: ["kWh", "$3.84", "Sense"]), "The Sense report numbers are shown")
        }
        mark("energy checked")
    }

    // MARK: Job 9: first launch through the Connect screen

    func testJob09_FirstLaunch() {
        begin(9, "first-launch", "First launch through Connect", .signedOut)
        guard waitForHome() else { return }
        shot("first-home", screen: "Home (not connected)")
        check(app.buttons["home.connect"].waitForExistence(timeout: 8), "Home says the mail is sample mail and offers Connect")
        if tap(app.buttons["home.settings"], "Settings") {
            let connect = app.buttons["settings.connect"]
            check(connect.waitForExistence(timeout: 8), "Settings offers 'Connect Gmail'")
            shot("settings", screen: "Settings (not connected)")
            if tap(connect, "Connect Gmail") {
                check(waitForRequest("CLIENT signIn", timeout: 8), "Connect starts Google sign-in (the audit stops here)")
                settle(1)
                shot("after-connect-cancelled", screen: "After cancelled sign-in")
                check(connect.exists, "The app stays usable after sign-in is cancelled, with Connect still offered")
                check(!anyText(containing: ["error", "exception", "nserror", "(null)", "couldn\u{2019}t be completed"]), "The message after cancelling is plain language", visibleTexts(limit: 12).joined(separator: " | "))
            }
        }
        mark("reached Google's sign-in")
    }

    // MARK: Job 10: Settings changes, then Disconnect

    func testJob10_Settings_Light() { settingsAndDisconnect(.light) }
    func testJob10_Settings_Dark() { settingsAndDisconnect(.dark) }
    func testJob10_Settings_Neon() { settingsAndDisconnect(.neon) }
    func testJob10_Settings_LargeText() { settingsAndDisconnect(.largeText) }
    func testJob10_Settings_Expired() { errorWalk(10, "settings", "Settings and Disconnect", .expired) }
    func testJob10_Settings_NoPermission() { errorWalk(10, "settings", "Settings and Disconnect", .noPermission) }
    func testJob10_Settings_Offline() { errorWalk(10, "settings", "Settings and Disconnect", .offline) }
    func testJob10_Settings_Empty() { errorWalk(10, "settings", "Settings and Disconnect", .empty) }

    private func settingsAndDisconnect(_ c: AuditCondition) {
        begin(10, "settings", "Settings changes, then Disconnect", c)
        guard waitForHome() else { return }
        if tap(app.buttons["home.settings"], "Settings") {
            check(app.buttons["settings.disconnect"].waitForExistence(timeout: 15) || app.buttons["settings.row.Households and kids"].waitForExistence(timeout: 5), "Settings opens")
            shot("settings", screen: "Settings")

            // A few changes: appearance, a toggle, a new household.
            let dark = app.segmentedControls.buttons["Dark"]
            if dark.exists { tap(dark, "Appearance: Dark"); settle(); shot("appearance-dark") }
            let logos = app.switches["Company logos"]
            scrollIntoView(logos)
            if logos.exists {
                let before = logos.value as? String
                tap(logos, "Company logos switch")
                check((logos.value as? String) != before, "The Company logos switch changed")
            }
            let rowButton = app.buttons["settings.row.Households and kids"]
            scrollIntoView(rowButton)
            if tap(rowButton, "Households and kids") {
                shot("households", screen: "Households and kids")
                check(app.textFields.matching(NSPredicate(format: "value == %@", "Maple Street house")).firstMatch.waitForExistence(timeout: 8), "The household 'Maple Street house' is listed")
                check(present(app.textFields.matching(NSPredicate(format: "value == %@", "Ava")).firstMatch), "Ava is listed")
                let add = app.textFields["Add a household"]
                scrollIntoView(add)
                enter("Beach cabin", into: add, "Add a household")
                tap(app.buttons["Add"].firstMatch, "Add household")
                shot("household-added")
                goBack()
            }
            mark("settings changed")

            // Disconnect.
            let disconnect = app.buttons["settings.disconnect"]
            scrollIntoView(disconnect)
            if tap(disconnect, "Disconnect Gmail") {
                let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Disconnect")).firstMatch
                check(confirm.waitForExistence(timeout: 5), "Disconnect asks once before signing out")
                shot("disconnect-confirm", screen: "Disconnect confirmation")
                tap(confirm, "Confirm Disconnect")
                check(waitForRequest("CLIENT signOut", timeout: 8), "Disconnect signed out of Gmail")
                settle(1.5)
                shot("after-disconnect", screen: "Settings after Disconnect")
                check(app.buttons["settings.connect"].waitForExistence(timeout: 8), "After Disconnect, Settings offers Connect again")
                // Households and kids must survive.
                let again = app.buttons["settings.row.Households and kids"]
                scrollIntoView(again)
                if tap(again, "Households and kids after Disconnect") {
                    shot("households-after", screen: "Households after Disconnect")
                    check(app.textFields.matching(NSPredicate(format: "value == %@", "Maple Street house")).firstMatch.waitForExistence(timeout: 8), "The household is still there after Disconnect")
                    check(present(app.textFields.matching(NSPredicate(format: "value == %@", "Beach cabin")).firstMatch), "The household added a moment ago is still there")
                    check(present(app.textFields.matching(NSPredicate(format: "value == %@", "Ava")).firstMatch), "Ava is still there after Disconnect")
                    check(present(app.textFields.matching(NSPredicate(format: "value == %@", "Noah")).firstMatch), "Noah is still there after Disconnect")
                }
            }
        }
        mark("disconnected")
    }

    // MARK: The same jobs when something is wrong

    /// Error states: what a person sees, whether it says what happened in plain words, and whether there is a way forward.
    private func errorWalk(_ number: Int, _ slug: String, _ title: String, _ c: AuditCondition) {
        begin(number, slug, title, c)
        guard waitForHome() else { return }
        settle(3)
        shot("home")
        let words: [String: [String]] = [
            "expired": ["reconnect", "signed you out", "sign in"],
            "nopermission": ["access", "permission", "reconnect", "tick"],
            "offline": ["internet", "offline", "connection", "couldn't", "could not"],
            "empty": ["nothing", "all clear", "caught up", "no mail", "empty", "inbox"]
        ]
        let found = anyText(containing: words[c.name] ?? [])
        note("Home text: " + visibleTexts(limit: 20).joined(separator: " | "))
        check(found, "Home explains this situation in plain words", visibleTexts(limit: 12).joined(separator: " | "))

        switch number {
        case 1:
            app.swipeDown()
            settle(2)
            shot("pulled-to-refresh")
        case 4:
            check(!app.buttons["home.nextup.trash"].exists, "Trash is not offered when there is no mail to trash")
        default: break
        }

        // The way forward is always Settings.
        if tap(app.buttons["home.settings"], "Settings") {
            settle(1)
            shot("settings")
            let connect = app.buttons["settings.connect"]
            switch c.name {
            case "expired", "nopermission":
                check(connect.waitForExistence(timeout: 8), "Settings offers 'Reconnect Gmail'")
                if tap(connect, "Reconnect Gmail") { settle(1); shot("after-reconnect") }
            default:
                check(app.buttons["settings.disconnect"].waitForExistence(timeout: 8) || connect.exists, "Settings offers Disconnect or Connect")
            }
            if number == 10 {
                let rowButton = app.buttons["settings.row.Households and kids"]
                scrollIntoView(rowButton)
                if tap(rowButton, "Households and kids") {
                    shot("households")
                    check(app.textFields.matching(NSPredicate(format: "value == %@", "Ava")).firstMatch.waitForExistence(timeout: 8), "Households and kids are still shown in this state")
                }
            }
        }
        mark("walked the error state")
    }
}
