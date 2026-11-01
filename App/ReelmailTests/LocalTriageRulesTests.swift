import XCTest
@testable import Reelmail

@MainActor
final class LocalTriageRulesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "reelmail.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testUnknownMailRemainsVisible() {
        withDefaults { defaults in
            let rules = LocalTriageRules(accountID: "demo", defaults: defaults)
            XCTAssertEqual(rules.decision(messageID: "m1", sender: "sender@example.test").destination, .inbox)
        }
    }

    func testSenderRuleNormalizesAndPersistsAcrossInstances() {
        withDefaults { defaults in
            let rules = LocalTriageRules(accountID: "account-a", defaults: defaults)
            XCTAssertTrue(rules.setSender(" Newsletter@Example.Test ", destination: .reading))
            let reloaded = LocalTriageRules(accountID: "account-a", defaults: defaults)
            XCTAssertEqual(reloaded.decision(messageID: "m2", sender: "newsletter@example.test").destination, .reading)
        }
    }

    func testMessageOverrideAndRemovalRestoreSenderRule() {
        withDefaults { defaults in
            let rules = LocalTriageRules(accountID: "demo", defaults: defaults)
            XCTAssertTrue(rules.setSender("sender@example.test", destination: .filtered))
            XCTAssertTrue(rules.setMessage("m1", destination: .inbox))
            XCTAssertEqual(rules.decision(messageID: "m1", sender: "sender@example.test").destination, .inbox)
            XCTAssertEqual(rules.decision(messageID: "m2", sender: "sender@example.test").destination, .filtered)
            XCTAssertTrue(rules.setMessage("m1", destination: nil))
            XCTAssertEqual(rules.decision(messageID: "m1", sender: "sender@example.test").destination, .filtered)
            XCTAssertTrue(rules.setSender("sender@example.test", destination: nil))
            XCTAssertEqual(rules.decision(messageID: "m1", sender: "sender@example.test").destination, .inbox)
        }
    }

    func testAccountsAndDemoRemainSeparate() {
        withDefaults { defaults in
            let first = LocalTriageRules(accountID: "account-a", defaults: defaults)
            XCTAssertTrue(first.setMessage("shared-id", destination: .filtered))
            for account in ["account-b", "demo"] {
                let other = LocalTriageRules(accountID: account, defaults: defaults)
                XCTAssertEqual(other.decision(messageID: "shared-id", sender: "sender@example.test").destination, .inbox)
            }
        }
    }

    func testCorruptPreferencesAreNotSilentlyOverwritten() {
        withDefaults { defaults in
            let key = "reelmail.triage.v1.demo"
            let original = Data("not-json".utf8)
            defaults.set(original, forKey: key)
            let rules = LocalTriageRules(accountID: "demo", defaults: defaults)
            XCTAssertNotNil(rules.persistenceError)
            XCTAssertFalse(rules.setMessage("m1", destination: .filtered))
            XCTAssertEqual(defaults.data(forKey: key), original)
        }
    }
}
