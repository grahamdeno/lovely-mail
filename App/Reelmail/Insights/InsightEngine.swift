import Foundation
import Observation
import os

/// Reads the last 12 months of mail, metadata first, and keeps only the facts the readers recognise.
/// Bodies are downloaded only for mail from senders and subjects that look like bills, energy reports or renewals.
@MainActor
@Observable
final class InsightEngine {
    private(set) var store: InsightStore
    private(set) var isRunning = false
    private(set) var lastError: String?
    private let storage: InsightStorage
    private let log = Logger(subsystem: "com.grahamdeno.reelmail", category: "insights")

    static let batchSize = 400
    static let query = "newer_than:1y -in:sent -in:drafts -in:spam -in:trash"

    init(storage: InsightStorage = .standard) {
        self.storage = storage
        self.store = storage.load()
    }

    /// Delete everything read from mail (on disconnect).
    func reset() {
        storage.removeAll()
        store = InsightStore()
    }

    /// Does this envelope look like it holds a fact worth downloading the body for?
    static func needsBody(_ stub: MessageStub) -> Bool {
        let domain = InsightText.registrable(InsightText.domain(of: stub.fromAddress))
        if HealthMail.isHealth(domain: domain, subject: stub.subject) { return false }
        if domain.contains("sense.com") { return true }
        return Rx.test("bill|statement|amount due|payment|invoice|autopay|usage|charged for your|energy", in: stub.subject)
    }

    /// One bounded pass. Safe to call often: processed mail is skipped.
    func refresh(client: any GmailInboxClient, account: String?) async {
        guard !isRunning, client.isSignedIn else { return }
        isRunning = true; lastError = nil
        defer { isRunning = false }
        do {
            let limit = min(3000, store.processed.count + Self.batchSize)
            let listed = try await client.listMessageIDs(query: Self.query, limit: limit)
            let fresh = listed.ids.filter { !store.processed.contains($0) }
            for id in fresh.prefix(Self.batchSize) {
                try Task.checkCancellation()
                let stub = try await client.getMetadata(id: id)
                var body = ""
                if Self.needsBody(stub) {
                    body = (try? await client.getMessage(id: id, account: account))?.body ?? ""
                }
                let input = InsightInput(id: id, fromName: stub.fromName, fromAddress: stub.fromAddress, subject: stub.subject, date: stub.date, body: body)
                for fact in InsightParsers.parse(input) { store.add(fact) }
                store.processed.insert(id)
            }
            store.historySeen = store.processed.count
            store.historyDone = !listed.truncated && fresh.count <= Self.batchSize
            storage.save(store)
            await PaymentAlarmNotifier.announce(store: store)
        } catch is CancellationError {
            storage.save(store)
        } catch {
            lastError = RefreshProblem.message(for: error)
            storage.save(store)
            log.error("Insight refresh stopped")
        }
    }
}
