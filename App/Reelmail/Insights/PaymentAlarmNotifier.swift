import Foundation
import UserNotifications

@MainActor
enum PaymentAlarmNotifier {
    /// Sends a local notice for each new payment problem. Skips quietly when notifications are not allowed.
    static func announce(store: InsightStore, defaults: UserDefaults = .standard) async {
        let all = MoneyInsights.alarms(store)
        let fresh = PaymentAlarm.unannounced(all, defaults: defaults)
        guard !fresh.isEmpty else { PaymentAlarm.markSeen(all, defaults: defaults); return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for bill in fresh {
            let text = PaymentAlarm.notice(for: bill, showNames: BriefSettings(defaults: defaults).showNames)
            let content = UNMutableNotificationContent()
            content.title = text.title; content.body = text.body; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "lovely.alarm.\(bill.id)", content: content, trigger: trigger))
        }
        PaymentAlarm.markAnnounced(fresh, defaults: defaults)
        PaymentAlarm.markSeen(all, defaults: defaults)
    }
}
