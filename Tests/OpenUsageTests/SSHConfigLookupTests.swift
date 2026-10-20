import XCTest
@testable import OpenUsage

final class SSHConfigLookupTests: XCTestCase {
    func testParsesSSHDashGOutput() {
        let output = Data("host lab\nuser ada\nhostname 100.64.0.10\nport 2222\nidentityfile ~/.ssh/id_ed25519\n".utf8)
        XCTAssertEqual(SSHConfigLookup.parse(output),
                       SSHResolvedDestination(user: "ada", hostName: "100.64.0.10", port: 2222))
        XCTAssertNil(SSHConfigLookup.parse(Data("garbage".utf8)))
    }

    func testListsOnlyLiteralHostAliases() {
        let config = """
        Host lab nano
          HostName 100.64.0.10
        Host *.example.com !skip
        host=mc
        Match host foo
        Host lab
        """
        XCTAssertEqual(SSHConfigLookup.aliases(configText: config), ["lab", "nano", "mc"])
    }

    /// Regression: picking a tailnet machine ignored an alias that already had its username and key.
    func testFindsAliasPointingAtTailnetMachine() {
        let peer = TailscalePeer(name: "DESKTOP", host: "100.64.0.10", system: .windows, isOnline: true,
                                 dnsName: "desktop.tail1.ts.net")
        let aliases = [
            "nano": SSHResolvedDestination(user: "u", hostName: "nano.example.org", port: 22),
            "lab": SSHResolvedDestination(user: "ada", hostName: "100.64.0.10", port: 22),
            "desk": SSHResolvedDestination(user: "ada", hostName: "DESKTOP.tail1.ts.net", port: 22),
        ]
        XCTAssertEqual(SSHConfigLookup.alias(for: peer, among: aliases), "desk")
        XCTAssertNil(SSHConfigLookup.alias(for: peer, among: ["nano": aliases["nano"]!]))
    }

    /// Regression: these failures gave no hint that DNS or the guessed username was the problem.
    func testFailureMessagesNameTheCause() {
        let unresolved = SSHRemoteUsageClient.failureMessage(
            status: 255, stderr: Data("ssh: Could not resolve hostname box.x.ts.net: nodename nor servname provided".utf8))
        XCTAssertTrue(unresolved.contains("Use Tailscale DNS"))
        let denied = SSHRemoteUsageClient.failureMessage(
            status: 255, stderr: Data("grace@100.64.0.10: Permission denied (publickey,password).".utf8))
        XCTAssertTrue(denied.hasPrefix("SSH login as “grace” was rejected."))
        let bare = SSHRemoteUsageClient.failureMessage(status: 255, stderr: Data("Permission denied (publickey).".utf8))
        XCTAssertTrue(bare.hasPrefix("SSH login was rejected."))
    }
}
