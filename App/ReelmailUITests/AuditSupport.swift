import XCTest

// Shared pieces of the UI audit. The app runs in fixture mode (see App/Reelmail/Fixtures): fictional mail, a fake Gmail and
// no network. Every job records what it did, how many taps it took, and what the fake Gmail was asked to do.

struct AuditCondition {
    let name: String
    let arguments: [String]
    /// Run the accessibility audit on each new screen. Slow, so only for the conditions where it teaches the most.
    let audit: Bool
    var isError: Bool { ["expired", "nopermission", "offline", "empty"].contains(name) }

    static let light = AuditCondition(name: "light", arguments: ["-uiTestAppearance", "light"], audit: true)
    static let dark = AuditCondition(name: "dark", arguments: ["-uiTestAppearance", "dark"], audit: false)
    static let neon = AuditCondition(name: "neon", arguments: ["-uiTestAppearance", "neon"], audit: false)
    static let largeText = AuditCondition(name: "largetext", arguments: ["-uiTestAppearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], audit: true)
    static let expired = AuditCondition(name: "expired", arguments: ["-uiTestAppearance", "light", "-uiTestExpired"], audit: false)
    static let noPermission = AuditCondition(name: "nopermission", arguments: ["-uiTestAppearance", "light", "-uiTestNoPermission"], audit: false)
    static let offline = AuditCondition(name: "offline", arguments: ["-uiTestAppearance", "light", "-uiTestOffline"], audit: false)
    static let empty = AuditCondition(name: "empty", arguments: ["-uiTestAppearance", "light", "-uiTestEmpty"], audit: false)
    static let signedOut = AuditCondition(name: "firstlaunch", arguments: ["-uiTestAppearance", "light", "-uiTestSignedOut"], audit: true)
}

struct StepRecord: Codable { var number: Int; var label: String; var screenshot: String; var taps: Int }
struct AssertionRecord: Codable { var name: String; var passed: Bool; var detail: String }
struct FindingRecord: Codable { var kind: String; var screen: String; var control: String; var detail: String }
struct A11yRecord: Codable { var screen: String; var type: String; var detail: String; var element: String }

/// What one job did. Saved as JSON next to the screenshots and merged into audit-summary.json.
final class JobRecorder: Codable {
    var number: Int
    var slug: String
    var title: String
    var condition: String
    var taps = 0
    var typedEntries = 0
    var steps: [StepRecord] = []
    var assertions: [AssertionRecord] = []
    var accessibility: [A11yRecord] = []
    var findings: [FindingRecord] = []
    var screens: [String] = []
    var marks: [String: Int] = [:]
    var notes: [String] = []
    var requests: [String] = []
    var seconds: Double = 0

    init(number: Int, slug: String, title: String, condition: String) {
        self.number = number; self.slug = slug; self.title = title; self.condition = condition
    }

    var base: String { String(format: "%02d", number) + "-" + slug }
    var id: String { base + "-" + condition }
}

class AuditCase: XCTestCase {
    var app: XCUIApplication!
    var job: JobRecorder!
    var condition: AuditCondition = .light
    private var audited: Set<String> = []
    private var started = Date()

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        if let job {
            job.seconds = Date().timeIntervalSince(started)
            job.requests = fixtureLines()
            if let data = try? JSONEncoder().encode(job) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "result-" + job.id
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        app?.terminate()
        super.tearDown()
    }

    // MARK: Launching

    func begin(_ number: Int, _ slug: String, _ title: String, _ condition: AuditCondition) {
        self.condition = condition
        started = Date()
        audited = []
        job = JobRecorder(number: number, slug: slug, title: title, condition: condition.name)
        app = XCUIApplication()
        app.launchArguments = ["-uiTestFixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + condition.arguments
        app.launch()
    }

    /// Waits for Home to be on screen.
    @discardableResult
    func waitForHome(timeout: TimeInterval = 30) -> Bool {
        let ok = app.buttons["tab.home"].waitForExistence(timeout: timeout)
        check(ok, "Home is on screen after launch")
        return ok
    }

    // MARK: Steps, taps and checks

    /// Takes a screenshot with a name the exporter turns into NN-job-step-condition.png.
    func shot(_ label: String, screen: String? = nil) {
        let number = job.steps.count + 1
        let name = job.base + "-s" + String(format: "%02d", number) + "-" + label + "-" + condition.name
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        job.steps.append(StepRecord(number: number, label: label, screenshot: name, taps: job.taps))
        if let screen { auditAccessibility(screen) }
    }

    /// One tap on a real control. Returns false (and records a failed check) when the control is not there.
    @discardableResult
    func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            check(false, "Found '\(what)' to tap", "not on screen after \(Int(timeout)) s")
            return false
        }
        if !element.isHittable { scrollIntoView(element) }
        guard element.isHittable else {
            check(false, "Could tap '\(what)'", "on screen but not hittable")
            return false
        }
        job.taps += 1
        element.tap()
        return true
    }

    /// Typing is counted separately from taps: one entry per field filled in.
    func enter(_ text: String, into field: XCUIElement, _ what: String) {
        if tap(field, "field " + what) {
            job.typedEntries += 1
            field.typeText(text)
        }
    }

    func scrollIntoView(_ element: XCUIElement, maxSwipes: Int = 8) {
        var n = 0
        while (!element.exists || !element.isHittable) && n < maxSwipes {
            app.swipeUp(velocity: .slow)
            n += 1
        }
    }

    func check(_ ok: Bool, _ name: String, _ detail: String = "") {
        job.assertions.append(AssertionRecord(name: name, passed: ok, detail: detail))
        XCTAssertTrue(ok, name + (detail.isEmpty ? "" : " (" + detail + ")"))
    }

    func mark(_ name: String) { job.marks[name] = job.taps }
    func note(_ text: String) { job.notes.append(text) }

    // MARK: What the fake Gmail was asked

    /// Everything the fake Gmail and fake transport recorded so far, in order.
    func fixtureLines() -> [String] {
        guard let app, app.state == .runningForeground else { return [] }
        let element = app.descendants(matching: .any)["fixture.requests"]
        guard element.exists, let value = element.value as? String, !value.isEmpty else { return [] }
        return value.split(separator: "\n").map(String.init)
    }

    func count(_ needle: String) -> Int { fixtureLines().filter { $0.contains(needle) }.count }

    /// Waits until the fake Gmail has seen at least `atLeast` lines containing `needle`.
    @discardableResult
    func waitForRequest(_ needle: String, atLeast: Int = 1, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if count(needle) >= atLeast { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return count(needle) >= atLeast
    }

    func settle(_ seconds: TimeInterval = 0.8) { Thread.sleep(forTimeInterval: seconds) }

    // MARK: Accessibility

    /// Runs Apple's accessibility audit once per screen and records what it finds. Issues never fail the run.
    func auditAccessibility(_ screen: String) {
        guard condition.audit, !audited.contains(screen) else { return }
        audited.insert(screen)
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                self.job.accessibility.append(A11yRecord(screen: screen,
                                                         type: String(describing: issue.auditType.rawValue),
                                                         detail: issue.compactDescription,
                                                         element: issue.element?.label ?? issue.element?.identifier ?? ""))
                return true
            }
        } catch {
            note("Accessibility audit could not run on \(screen): \(error.localizedDescription)")
        }
    }

    /// The visible text on screen, for notes and plain-language checks.
    func visibleTexts(limit: Int = 40) -> [String] {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(limit).map(\.label).filter { !$0.isEmpty }
        return Array(texts)
    }

    func anyText(containing words: [String]) -> Bool {
        let all = visibleTexts(limit: 80).map { $0.lowercased() }
        return all.contains { text in words.contains { text.contains($0.lowercased()) } }
    }

    func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func text(containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func goBack() {
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { job.taps += 1; back.tap() }
    }
}
