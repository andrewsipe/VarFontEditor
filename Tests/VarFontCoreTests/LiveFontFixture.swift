import Foundation
import XCTest
@testable import VarFontCore

/// Resolves live variable-font paths for integration tests.
/// Fonts are not checked into the repo; tests skip when none are found.
enum LiveFontFixture {
    static let playfairRomanCandidates = [
        NSHomeDirectory() + "/Downloads/PlayfairRomanVF.woff2",
        NSHomeDirectory() + "/Downloads/~Untitled/PlayfairRomanVF.woff2",
    ]

    static let playfairItalicCandidates = [
        NSHomeDirectory() + "/Downloads/PlayfairItalicVF.woff2",
        NSHomeDirectory() + "/Downloads/~Untitled/PlayfairItalicVF.woff2",
    ]

    static let robotoFlexCandidates = [
        NSHomeDirectory()
            + "/Downloads/RobotoFlex-VariableFont_GRAD,XOPQ,XTRA,YOPQ,YTAS,YTDE,YTFI,YTLC,YTUC,opsz,slnt,wdth,wght.ttf",
        NSHomeDirectory() + "/Downloads/~FontVaultTESTFiles/Roboto Flex Variable/RobotoFlex-Variable.ttf",
        NSHomeDirectory() + "/Documents/FEX/R/Roboto Flex Variable/RobotoFlex-Variable.ttf",
    ]

    static func resolvePath(candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static var playfairRomanPath: String? {
        resolvePath(candidates: playfairRomanCandidates)
    }

    static var playfairItalicPath: String? {
        resolvePath(candidates: playfairItalicCandidates)
    }

    static var robotoFlexPath: String? {
        resolvePath(candidates: robotoFlexCandidates)
    }

    static var vfcommitHelperURL: URL {
        FixtureLoader.examplesDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/vfcommit/vfcommit.py")
    }

    static func makeCommitService() throws -> CommitService {
        let helper = vfcommitHelperURL
        guard FileManager.default.fileExists(atPath: helper.path) else {
            throw XCTSkip("vfcommit helper not found at \(helper.path)")
        }
        return CommitService(helperURL: helper)
    }

    static func requirePlayfairRoman() throws -> String {
        guard let path = playfairRomanPath else {
            throw XCTSkip("Playfair Roman VF not found — see fixtures/fonts/README.md")
        }
        return path
    }

    static func requireRobotoFlex() throws -> String {
        guard let path = robotoFlexPath else {
            throw XCTSkip("Roboto Flex VF not found — see fixtures/fonts/README.md")
        }
        return path
    }

    /// Patch fixture project font paths to resolved live fonts when available.
    static func resolvingPaths(in project: inout ProjectDocument) {
        let romanID = "11111111-1111-1111-1111-111111111101"
        let italicID = "11111111-1111-1111-1111-111111111102"
        for index in project.fonts.indices {
            switch project.fonts[index].id {
            case romanID where playfairRomanPath != nil:
                project.fonts[index].sourcePath = playfairRomanPath!
            case italicID where playfairItalicPath != nil:
                project.fonts[index].sourcePath = playfairItalicPath!
            default:
                break
            }
        }
    }
}
