import XCTest
@testable import VarFontCore

/// Cross-language parity with vfcommit ``test_postscript_policies.py`` — keep fixture strings identical.
final class PostScriptPolicyParityTests: XCTestCase {
    func testSanitizePostscriptParityFixtures() {
        let cases: [(String, String)] = [
            ("Milgram", "Milgram"),
            ("Loes 0.4", "Loes0.4"),
            ("Foo Bar", "FooBar"),
            ("Bad@Name", "Bad-Name"),
            ("Keep-me_ok.test?!&*", "Keep-me_ok.test?!&*"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(PostScriptNaming.sanitizePostscript(input), expected, "sanitize: \(input)")
        }
    }

    func testStripVariableTokensParityFixtures() {
        let cases: [(String, String?)] = [
            ("Milgram Variable", "Milgram"),
            ("Roboto Flex", "Roboto"),
            ("Family VF", "Family"),
            ("Plain Family", "Plain Family"),
            ("", nil),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(PostScriptNaming.stripVariableTokens(input), expected, "strip: \(input)")
        }
    }

    func testIsUsablePrefixParityFixtures() {
        XCTAssertTrue(PostScriptNaming.isUsablePrefix("Loes0.4"))
        XCTAssertFalse(PostScriptNaming.isUsablePrefix(""))
        XCTAssertFalse(PostScriptNaming.isUsablePrefix("Bad?"))
    }
}
