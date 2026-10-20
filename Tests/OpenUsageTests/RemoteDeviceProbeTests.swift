import XCTest
@testable import OpenUsage

final class RemoteDeviceProbeTests: XCTestCase {
    private func utf16(_ text: String) -> Data { text.data(using: .utf16LittleEndian)! }

    func testListsDistributionsFromWindowsUTF16OutputAndHidesDockersOwn() {
        // Byte-for-byte shape of `wsl.exe --list --verbose` over SSH: UTF-16LE, CRLF, no BOM.
        let output = utf16("  NAME              STATE           VERSION\r\n* Ubuntu            Stopped         2\r\n"
            + "  docker-desktop    Running         2\r\n  Debian            Running         2\r\n")
        XCTAssertEqual(WSLDistribution.parse(output), [
            WSLDistribution(name: "Ubuntu", state: "Stopped", isDefault: true),
            WSLDistribution(name: "Debian", state: "Running", isDefault: false)
        ])
    }

    func testListsDistributionsOnLocalizedWindowsAndInUTF8Mode() {
        let localized = utf16("\u{FEFF}  名稱      狀態      版本\r\n* Ubuntu-24.04    已停止    2\r\n")
        XCTAssertEqual(WSLDistribution.parse(localized), [WSLDistribution(name: "Ubuntu-24.04", state: "已停止", isDefault: true)])
        // WSL_UTF8=1 makes wsl.exe write UTF-8.
        let utf8 = Data("  NAME   STATE   VERSION\n* Arch   Running 2\n".utf8)
        XCTAssertEqual(WSLDistribution.parse(utf8), [WSLDistribution(name: "Arch", state: "Running", isDefault: true)])
        // A stray trailing byte doesn't lose the list.
        XCTAssertEqual(WSLDistribution.parse(utf16("* Ubuntu Stopped 2\r\n") + Data([0x0A])).map(\.name), ["Ubuntu"])
    }

    func testMessagesWithoutRowsListNothing() {
        let message = utf16("Windows Subsystem for Linux has no installed distributions.\r\nUse 'wsl.exe --list --online' to list available distributions.\r\n")
        XCTAssertEqual(WSLDistribution.parse(message), [])
        XCTAssertTrue(WSLDistribution.decode(message).hasPrefix("Windows Subsystem for Linux has no installed distributions."))
    }

    func testDistributionWithoutPythonGetsTheUnavailableHint() {
        // What WSL prints when the picked distribution (e.g. docker-desktop) has no python3.
        let stderr = Data("<3>WSL (16774 - Relay) ERROR: CreateProcessCommon:798: execvpe(python3) failed: No such file or directory".utf8)
        XCTAssertTrue(SSHRemoteUsageClient.failureMessage(status: 1, stderr: stderr)
            .hasPrefix("The selected Python or WSL command is unavailable."))
    }

    func testProbeLineParsesLogFlags() {
        let result = RemoteProbeResult.parse("linux | ada | /home/ada | codex=1 claude=0\n")
        XCTAssertEqual(result, RemoteProbeResult(platform: "linux", user: "ada", home: "/home/ada",
                                                 hasCodexLogs: true, hasClaudeLogs: false))
        XCTAssertEqual(result?.logsSummary, "Codex logs found. No Claude logs.")
        XCTAssertFalse(RemoteProbeResult.parse("linux | ada | /home/ada | codex=0 claude=0")!.hasAnyLogs)
        // The pre-log-check three-part line isn't mistaken for a result.
        XCTAssertNil(RemoteProbeResult.parse("linux | ada | /home/ada"))
    }

    func testProbeSendsTheExporterInProbeModeAndChecksTheSystem() async throws {
        let ssh = try fakeSSH("""
            read first
            [ "$first" = "QUOTAPUS_PROBE = True" ] || exit 9
            cat >/dev/null
            printf 'win32 | ada | C:\\\\Users\\\\Ada | codex=1 claude=1\\n'
            """)
        defer { try? FileManager.default.removeItem(at: ssh) }
        let client = SSHRemoteUsageClient(executable: ssh.path, probeTimeout: 10)
        let windows = RemoteUsageDevice(name: "Lab", host: "lab", platform: .windows)
        let result = try await client.probe(windows)
        XCTAssertEqual(result.user, "ada")
        XCTAssertEqual(result.home, #"C:\Users\Ada"#)
        XCTAssertTrue(result.hasCodexLogs && result.hasClaudeLogs)
        do {
            _ = try await client.probe(RemoteUsageDevice(name: "Lab WSL", host: "lab", platform: .wsl))
            XCTFail("A Windows answer for a WSL device must fail")
        } catch SSHRemoteUsageError.commandFailed(let detail) {
            XCTAssertTrue(detail.contains("wrong system"))
        }
    }

    func testWSLListRunsTheListCommandAndReportsWindowsOwnError() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("wsl-list-\(UUID().uuidString)")
        try utf16("  NAME      STATE      VERSION\r\n* Ubuntu    Stopped    2\r\n").write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let ssh = try fakeSSH("""
            for argument; do last=$argument; done
            [ "$last" = "wsl.exe --list --verbose" ] || exit 8
            cat '\(fixture.path)'
            """)
        defer { try? FileManager.default.removeItem(at: ssh) }
        let device = RemoteUsageDevice(name: "WSL", host: "lab", platform: .wsl)
        let listed = try await SSHRemoteUsageClient(executable: ssh.path, probeTimeout: 10).wslDistributions(device)
        XCTAssertEqual(listed, [WSLDistribution(name: "Ubuntu", state: "Stopped", isDefault: true)])

        try utf16("Windows Subsystem for Linux has no installed distributions.\r\n").write(to: fixture)
        let failing = try fakeSSH("cat '\(fixture.path)'\nexit 1")
        defer { try? FileManager.default.removeItem(at: failing) }
        do {
            _ = try await SSHRemoteUsageClient(executable: failing.path, probeTimeout: 10).wslDistributions(device)
            XCTFail("Expected wsl.exe's own message")
        } catch SSHRemoteUsageError.commandFailed(let detail) {
            XCTAssertEqual(detail, "Windows Subsystem for Linux has no installed distributions.")
        }
    }

    private func fakeSSH(_ body: String) throws -> URL {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("fake-ssh-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
