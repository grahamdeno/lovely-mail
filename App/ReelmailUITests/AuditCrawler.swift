import XCTest

/// Visits every screen it can reach, taps every control it can hit, and records crashes, screens with no way back
/// and controls that do nothing. It reports; it never fails the run.
final class AuditCrawler: AuditCase {
    private var tapped: Set<String> = []
    private var tapCount = 0
    private let tapBudget = 220
    private let maxDepth = 3
    private var deadline = Date()
    private var restarts = 0

    func testCrawlEveryScreen() {
        deadline = Date().addingTimeInterval(14 * 60)
        begin(11, "crawler", "Crawl every reachable screen",
              AuditCondition(name: "light", arguments: AuditCondition.light.arguments, audit: false))
        guard waitForHome() else { return }
        var pass = 0
        while tapCount < tapBudget, Date() < deadline, pass < 6 {
            let before = tapCount
            crawl(depth: 0, name: "Home")
            pass += 1
            if tapCount == before { break }
            if app.state != .runningForeground || !app.buttons["tab.home"].exists { relaunch() }
        }
        note("Taps: \(tapCount). Screens: \(job.screens.count). Restarts: \(restarts). Passes: \(pass).")
        shot("finished")
    }

    private func relaunch() {
        restarts += 1
        app.terminate()
        app.launch()
        _ = app.buttons["tab.home"].waitForExistence(timeout: 30)
    }

    /// What is on screen, as one comparable string.
    private func signature() -> String {
        let bars = app.navigationBars.allElementsBoundByIndex.prefix(2).map(\.identifier).joined(separator: ",")
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map { $0.identifier + "|" + $0.label }.joined(separator: ";")
        let alerts = app.alerts.count + app.sheets.count
        return bars + "#\(alerts)#" + buttons
    }

    private func screenName(_ fallback: String) -> String {
        let title = app.navigationBars.firstMatch.identifier
        return title.isEmpty ? fallback : title
    }

    private func isSkipped(_ label: String, _ identifier: String) -> Bool {
        if identifier == "settings.disconnect" || label.localizedCaseInsensitiveContains("Disconnect") { return true }
        if label == "Back" || identifier == "BackButton" { return true }
        if identifier.hasPrefix("tab.") { return false }
        return false
    }

    private func crawl(depth: Int, name: String) {
        guard depth <= maxDepth, tapCount < tapBudget, Date() < deadline else { return }
        let sig = signature()
        let screen = screenName(name)
        if !job.screens.contains(screen) {
            job.screens.append(screen)
            shot("screen-" + screen.replacingOccurrences(of: " ", with: "-").lowercased())
        }
        let count = min(app.buttons.count, 30)
        for i in 0..<count {
            guard tapCount < tapBudget, Date() < deadline else { return }
            guard signature() == sig else { return }  // Something moved us; the caller recovers.
            let el = app.buttons.element(boundBy: i)
            guard el.exists, el.isHittable else { continue }
            let label = el.label, identifier = el.identifier
            let key = sig.hashValue.description + "::" + String(i) + "::" + identifier + label
            if tapped.contains(key) || isSkipped(label, identifier) { continue }
            tapped.insert(key)
            tapCount += 1
            let logBefore = fixtureLines().count
            let described = identifier.isEmpty ? label : identifier + " (" + label + ")"
            el.tap()
            settle(0.5)
            if app.state != .runningForeground {
                job.findings.append(FindingRecord(kind: "crash", screen: screen, control: described, detail: "The app was no longer running after this tap."))
                relaunch()
                return
            }
            let after = signature()
            if after == sig {
                if fixtureLines().count == logBefore {
                    job.findings.append(FindingRecord(kind: "does-nothing", screen: screen, control: described, detail: "Nothing on screen changed and nothing was sent to Gmail."))
                }
                continue
            }
            crawl(depth: depth + 1, name: label.isEmpty ? identifier : label)
            if !returnTo(sig) {
                job.findings.append(FindingRecord(kind: "no-way-back", screen: screen, control: described, detail: "After this tap the crawler could not get back to '\(screen)' with Back, Done, Cancel, Close or a swipe down."))
                relaunch()
                return
            }
        }
    }

    /// Tries the ways a person would leave a screen, in order. Returns true once the earlier screen is showing again.
    private func returnTo(_ sig: String) -> Bool {
        for attempt in 0..<5 {
            if signature() == sig { return true }
            switch attempt {
            case 0: dismissByButton(["Cancel", "Close", "Done", "OK", "Not now"])
            case 1: goBack()
            case 2: app.swipeDown(velocity: .fast)
            case 3: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            default: goBack()
            }
            settle(0.6)
        }
        return signature() == sig
    }

    private func dismissByButton(_ names: [String]) {
        for name in names {
            let b = app.alerts.buttons[name].exists ? app.alerts.buttons[name] : app.buttons[name]
            if b.exists && b.isHittable { b.tap(); return }
        }
    }
}
