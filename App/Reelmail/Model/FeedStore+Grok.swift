import Foundation

/// Hand to Grok: the one Gmail change it makes, the filter that files Grok's reports. Approved by the owner, Nov 10,
/// 2026 ("an email report back, labeled and archived"); made once, behind its preview and his tap.
extension FeedStore {
    /// The address Grok mails its reports to (and the filter matches): the connected Gmail account.
    var grokReportAddress: String? {
        guard mode == .gmail, let a = account, ForwardAllowlist.isAddress(a) else { return nil }
        return a.lowercased()
    }

    var grokReportsFiled: Bool { UserDefaults.standard.bool(forKey: GrokHandoff.filterKey) }

    func setUpGrokReports(confirmed: ConfirmedAction) {
        guard let actions, let me = grokReportAddress else { return }
        UserDefaults.standard.set(true, forKey: GrokHandoff.filterKey)
        Task { [self] in
            do {
                let labelID = try await actions.ensureLabel(GrokHandoff.label, confirmed: confirmed)
                if !FilterRegistry().filters.contains(where: { $0.sender == me && $0.label == labelID }) {
                    _ = try await actions.createFilter(sender: me, forwardTo: nil, labelID: labelID, skipInbox: true,
                                                       subject: GrokHandoff.reportTag, confirmed: confirmed)
                }
            } catch {
                UserDefaults.standard.set(false, forKey: GrokHandoff.filterKey)
                errorMessage = "Lovely couldn't set up filing for Grok's reports. \(error.localizedDescription)"
            }
        }
    }
}
