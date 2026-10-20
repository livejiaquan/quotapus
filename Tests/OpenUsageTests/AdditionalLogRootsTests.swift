import XCTest
@testable import OpenUsage

final class AdditionalLogRootsTests: XCTestCase {
    func testParsesArchivesAlongsideExistingProxyConfiguration() {
        let config = AdditionalLogRoots.load(text: #"""
        {
          "proxy": {"enabled": true, "url": "socks5://localhost:1080"},
          "logSources": {
            "claudeProjectDirectories": ["/tmp/claude-projects", "/tmp/claude-projects"],
            "codexSessionDirectories": ["/tmp/codex-sessions", "relative/path"]
          }
        }
        """#)

        XCTAssertEqual(config.claudeProjectDirectories, ["/tmp/claude-projects"])
        XCTAssertEqual(config.codexSessionDirectories, ["/tmp/codex-sessions"])
    }

    func testMissingOrMalformedConfigHasNoExtraRoots() {
        XCTAssertEqual(AdditionalLogRoots.load(text: nil), AdditionalLogRoots())
        XCTAssertEqual(AdditionalLogRoots.load(text: "not json"), AdditionalLogRoots())
        XCTAssertEqual(AdditionalLogRoots.load(text: #"{"proxy":{"enabled":true}}"#), AdditionalLogRoots())
    }

    /// Regression: a malformed file silently dropped the extra roots and their spend.
    func testMalformedConfigNamesTheProblem() {
        XCTAssertNotNil(AdditionalLogRoots.issue(in: "not json"))
        XCTAssertNotNil(AdditionalLogRoots.issue(in: #"{"logSources": []}"#))
        XCTAssertNotNil(AdditionalLogRoots.issue(in: #"{"logSources": {"codexSessionDirectories": "/tmp/x"}}"#))
        XCTAssertNotNil(AdditionalLogRoots.issue(in: #"{"logSources": {"codexSessionDirectories": ["rel/path"]}}"#))
        XCTAssertNil(AdditionalLogRoots.issue(in: #"{"proxy": {"enabled": true}}"#))
        XCTAssertNil(AdditionalLogRoots.issue(in: #"{"logSources": {"claudeProjectDirectories": ["~/archive"]}}"#))
    }
}
