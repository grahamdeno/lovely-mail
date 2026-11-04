import BackgroundTasks
import Foundation
import UserNotifications

/// The owner's brief settings, stored on this phone (not per account).
struct BriefSettings {
    static let enabledKey = "lovely.brief.enabled"
    static let minutesKey = "lovely.brief.minutes"
    static let namesKey = "lovely.brief.names"
    static let offerSeenKey = "lovely.briefOffer.seen"
    static let nudgeKey = "lovely.brief.nudge"
    /// 9:30 AM, the weekday default. See BriefTiming.
    static let defaultMinutes = BriefTiming.weekdayDefault

    var defaults: UserDefaults = .standard

    var enabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    /// Set by hand in Settings. Nil: Lovely chooses (learned from use, else 9:30 weekdays and 10:00 weekends).
    var manualMinutes: Int? { defaults.object(forKey: Self.minutesKey) as? Int }
    var minutes: Int { manualMinutes ?? Self.defaultMinutes }
    /// The optional 7 PM note that opens a walk through the day's mail. Off by default.
    var nudgeEnabled: Bool { defaults.bool(forKey: Self.nudgeKey) }

    /// The brief time for one day.
    func minutes(on day: Date) -> Int {
        let log = InteractionLog(defaults: defaults)
        return BriefTiming.minutes(on: day, manual: manualMinutes, weekdaySamples: log.weekday, weekendSamples: log.weekend)
    }

    func nextFire(after now: Date) -> Date { BriefTiming.nextFire(after: now) { minutes(on: $0) } }
    var showNames: Bool { defaults.bool(forKey: Self.namesKey) }
    var offerSeen: Bool { defaults.bool(forKey: Self.offerSeenKey) }
}

/// Plans the morning brief as one local notification built on this phone from mail already loaded.
/// Nothing is sent anywhere. iOS decides whether the background refresh runs; when it does not, the brief
/// uses what was loaded last. See docs/sprint4-design.md.
@MainActor
enum MorningBriefScheduler {
    static let taskIdentifier = "com.grahamdeno.reelmail.morning"
    static let notificationID = "lovely.morning"

    /// Call once at launch, before the app finishes starting.
    static func register(store: FeedStore) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let work = Task { @MainActor in
                await store.load()
                await reschedule(store: store)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks for notification permission the first time the brief is switched on. False when declined.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces the pending brief with one built from the mail loaded right now.
    static func reschedule(store: FeedStore, settings: BriefSettings = BriefSettings(), now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard settings.enabled, store.mode == .gmail else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let fire = settings.nextFire(after: now)
        requestRefresh(before: fire, now: now)
        guard let brief = store.morningBrief(at: fire, showNames: settings.showNames) else { return }
        let content = UNMutableNotificationContent()
        content.title = brief.title
        content.body = brief.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
        await scheduleNudge(settings: settings, now: now)
    }

    static let nudgeID = "lovely.nudge"

    /// The optional 7 PM note. Counts only; it opens the same walk through.
    private static func scheduleNudge(settings: BriefSettings, now: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nudgeID])
        guard settings.nudgeEnabled else { return }
        let fire = BriefTiming.nextFire(after: now) { _ in 19 * 60 }
        let content = UNMutableNotificationContent()
        content.title = "Evening check"
        content.body = "A few minutes to go through today's mail."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: nudgeID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    static let testNotificationID = "lovely.morning.test"

    /// The next brief as it would read now, for Testing tools. Nil text means it would be skipped.
    static func preview(store: FeedStore, settings: BriefSettings = BriefSettings(), now: Date = Date()) -> MorningBrief? {
        store.morningBrief(at: settings.nextFire(after: now), showNames: settings.showNames)
    }

    /// Sends the preview as a notification in 5 seconds under its own id. It does not turn the brief on or replace it.
    /// Returns false when notifications are declined or there is nothing to send.
    static func sendTest(store: FeedStore, settings: BriefSettings = BriefSettings()) async -> Bool {
        guard await requestPermission(), let brief = preview(store: store, settings: settings) else { return false }
        let content = UNMutableNotificationContent()
        content.title = brief.title
        content.body = brief.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [testNotificationID])
        do { try await center.add(UNNotificationRequest(identifier: testNotificationID, content: content, trigger: trigger)); return true }
        catch { return false }
    }

    /// Asks iOS to wake the app about an hour before the brief so it can refresh first.
    private static func requestRefresh(before fire: Date, now: Date) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = max(fire.addingTimeInterval(-3600), now.addingTimeInterval(900))
        try? BGTaskScheduler.shared.submit(request)
    }
}
