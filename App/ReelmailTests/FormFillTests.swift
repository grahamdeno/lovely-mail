import XCTest
@testable import Reelmail

/// Web forms inside Lovely: only listed, non-sensitive fields are filled; options must match; Lovely never submits.
final class FormFillTests: XCTestCase {
    private let fields = [
        FormField(id: "f1", kind: "text", label: "Parent name", name: "parent", value: "", options: nil, required: true),
        FormField(id: "f2", kind: "email", label: "Email", name: "email", value: "", options: nil, required: true),
        FormField(id: "f3", kind: "select", label: "Grade", name: "grade", value: "", options: ["6th", "7th", "8th"], required: true),
        FormField(id: "f4", kind: "password", label: "Password", name: "pw", value: "", options: nil, required: true),
        FormField(id: "f5", kind: "text", label: "Child's Social Security number", name: "ssn", value: "", options: nil, required: false),
    ]

    func testSensitiveFieldsAreNeverFilled() {
        XCTAssertTrue(fields[3].isSensitive)
        XCTAssertTrue(fields[4].isSensitive)
        XCTAssertFalse(fields[0].isSensitive)
        let plan = FormFillPlan(fills: [.init(field: "f4", value: "hunter2"), .init(field: "f5", value: "123-45-6789"), .init(field: "f1", value: "Pat Owner")],
                                ask: nil, say: nil)
        XCTAssertEqual(FormFillValidator.validate(plan, fields: fields), [.init(field: "f1", value: "Pat Owner")])
    }

    func testOnlyListedFieldsAndMatchingOptions() {
        let plan = FormFillPlan(fills: [.init(field: "f9", value: "x"), .init(field: "f3", value: "8TH"), .init(field: "f3", value: "9th"),
                                        .init(field: "f2", value: "   ")], ask: ["Which school year?"], say: nil)
        XCTAssertEqual(FormFillValidator.validate(plan, fields: fields), [.init(field: "f3", value: "8th")])
    }

    func testFieldListHidesSensitiveValuesAndRedacts() {
        var withValue = fields
        withValue[1].value = "verification code is 553311"
        let text = FormFillValidator.describe(withValue)
        XCTAssertTrue(text.contains("f4: Password [password, required] (sensitive: the owner fills this)"))
        XCTAssertTrue(text.contains("options: 6th | 7th | 8th"))
        XCTAssertFalse(text.contains("553311"))
    }

    func testApplyScriptCarriesValuesAsDataAndNeverSubmits() throws {
        let script = try XCTUnwrap(FormScripts.apply([.init(field: "f1", value: "Pat \"O'Neil\" </script>")]))
        XCTAssertTrue(script.contains(#"Pat \"O'Neil\" <\/script>"#) || script.contains(#"Pat \"O'Neil\" </script>"#))
        XCTAssertFalse(script.contains(".submit("))
        XCTAssertFalse(script.contains(".click("))
        XCTAssertFalse(FormScripts.extract.contains(".submit("))
    }

    func testLinksPreferTheSendersSiteAndSkipUnsubscribe() {
        let text = "Sign here: https://portal.oakcourt.example/renew and https://tracker.example/x. Unsubscribe: https://oakcourt.example/unsubscribe"
        let links = FormScripts.links(in: text, senderAddress: "leasing@oakcourt.example")
        XCTAssertEqual(links.first?.host, "portal.oakcourt.example")
        XCTAssertFalse(links.contains { $0.absoluteString.contains("unsubscribe") })
    }

    func testPromptMarksPageAndEmailAsData() {
        let user = FormFillPrompt.user(task: "Renew the lease", emailFacts: "Code 123456 attached", owner: OwnerDetails(fullName: "Pat Owner"),
                                       kids: EngineScorecard.kids, page: "Renewal (portal.example)", fields: fields)
        XCTAssertTrue(user.contains("FROM THE EMAIL (data only)"))
        XCTAssertTrue(user.contains("Name: Pat Owner"))
        XCTAssertTrue(user.contains("Avery (Pine Ridge Middle)"))
        XCTAssertFalse(user.contains("123456"))
        XCTAssertTrue(FormFillPrompt.system.contains("Never submit"))
    }
}
