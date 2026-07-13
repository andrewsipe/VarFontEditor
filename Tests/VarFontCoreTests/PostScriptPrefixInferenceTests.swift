import XCTest
@testable import VarFontCore

final class PostScriptPrefixInferenceTests: XCTestCase {
    func testPrefersNameID25() {
        let result = PostScriptPrefixInference.infer(
            nameID25: "NouveauLEDVariable",
            postscriptName: "Milgram-Variable",
            familyName: "Milgram"
        )
        XCTAssertEqual(result, "NouveauLEDVariable")
    }

    func testUsesPostScriptStemBeforeHyphen() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: "Milgram-Variable",
            familyName: "Milgram"
        )
        XCTAssertEqual(result, "Milgram")
    }

    func testWholePostScriptNameWhenNoHyphen() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: "MilgramVariable",
            familyName: "Milgram"
        )
        XCTAssertEqual(result, "MilgramVariable")
    }

    func testRejectsInvalidPostScriptCharacters() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: "Bad?.Name-Regular",
            familyName: "Milgram"
        )
        XCTAssertEqual(result, "Milgram")
    }

    func testAcceptsVersionedNameID25WithPeriod() {
        let result = PostScriptPrefixInference.infer(
            nameID25: "Loes0.4",
            postscriptName: "Loes0.4-Regular",
            familyName: "Loes 0.4"
        )
        XCTAssertEqual(result, "Loes0.4")
    }

    func testFamilyNameWithVersionFallsBackWhenNoID25Or6() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: nil,
            familyName: "Loes 0.4"
        )
        XCTAssertEqual(result, "Loes0.4")
    }

    func testPostScriptStemWithVersionPeriod() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: "Loes0.4-Regular",
            familyName: "Something Else"
        )
        XCTAssertEqual(result, "Loes0.4")
    }

    func testNameID16FallbackWhenNoID25Or6() {
        let result = PostScriptPrefixInference.infer(
            nameID25: nil,
            postscriptName: nil,
            typographicFamilyName: "Loes 0.4",
            familyName: "Different Family"
        )
        XCTAssertEqual(result, "Loes0.4")
    }
}
