import XCTest
@testable import OpenUsage

final class TailscaleDiscoveryTests: XCTestCase {
    private func peers(_ json: String) -> [TailscalePeer]? {
        guard case .running(let peers) = TailscaleDiscovery.parse(Data(json.utf8)) else { return nil }
        return peers
    }

    /// Shape taken from a real tailnet: Windows, iOS, an empty-OS server, and a non-ASCII HostName.
    private let tailnet = """
    {"BackendState":"Running",
     "Self":{"DNSName":"studio.tail1.ts.net.","HostName":"Studio","OS":"macOS","Online":true},
     "Peer":{
      "a":{"DNSName":"desktop-ol6nnfe.tail1.ts.net.","HostName":"DESKTOP-OL6NNFE","OS":"windows","Online":true,"TailscaleIPs":["100.115.179.72"]},
      "b":{"DNSName":"muse.tail1.ts.net.","HostName":"muse","OS":"","Online":true},
      "c":{"DNSName":"iphone-15-pro.tail1.ts.net.","HostName":"localhost","OS":"iOS","Online":true},
      "d":{"DNSName":"nutsk.tail1.ts.net.","HostName":"NutsK麥塊左營","OS":"windows","Online":false},
      "e":{"DNSName":"lab.tail1.ts.net.","HostName":"lab","OS":"linux","Online":true},
      "f":{"DNSName":"studio.tail1.ts.net.","HostName":"Studio","OS":"macOS","Online":true}
     }}
    """

    func testKeepsWindowsAndUnknownSystemsAndDropsPhones() throws {
        let result = try XCTUnwrap(peers(tailnet))
        XCTAssertEqual(result.map(\.host), [
            "100.115.179.72", "lab.tail1.ts.net", "muse.tail1.ts.net", "nutsk.tail1.ts.net",
        ])
        XCTAssertEqual(result.first?.dnsName, "desktop-ol6nnfe.tail1.ts.net")
        XCTAssertEqual(result.map(\.system), [.windows, .linux, .unknown, .windows])
    }

    func testOnlinePeersComeFirstAndOfflineAreMarked() throws {
        let result = try XCTUnwrap(peers(tailnet))
        XCTAssertEqual(result.map(\.isOnline), [true, true, true, false])
    }

    func testNonASCIIHostNameIsOnlyTheDisplayName() throws {
        let offline = try XCTUnwrap(peers(tailnet)?.last)
        XCTAssertEqual(offline.name, "NutsK麥塊左營")
        XCTAssertEqual(offline.host, "nutsk.tail1.ts.net")
    }

    func testExcludesThisMac() throws {
        XCTAssertFalse(try XCTUnwrap(peers(tailnet)).contains { $0.host.hasPrefix("studio") })
    }

    func testPeerArrayAndNullShapes() {
        XCTAssertEqual(peers(#"{"BackendState":"Running","Peer":[{"DNSName":"lab.x.ts.net.","OS":"linux","Online":true}]}"#)?.map(\.host),
                       ["lab.x.ts.net"])
        XCTAssertEqual(peers(#"{"BackendState":"Running","Self":{},"Peer":null}"#), [])
    }

    func testFallsBackToIPv4WhenThereIsNoDNSName() {
        let json = #"{"BackendState":"Running","Peer":{"a":{"HostName":"box","OS":"linux","Online":true,"TailscaleIPs":["fd7a::1","100.64.0.5"]}}}"#
        XCTAssertEqual(peers(json)?.first?.host, "100.64.0.5")
    }

    /// Regression: a MagicDNS host failed with "Could not resolve hostname" when this Mac had Use
    /// Tailscale DNS off, so the Tailscale IP comes first.
    func testPrefersTailscaleIPOverMagicDNSName() {
        let json = #"{"BackendState":"Running","Peer":{"a":{"DNSName":"box.x.ts.net.","HostName":"box","OS":"windows","Online":true,"TailscaleIPs":["fd7a::1","100.64.0.5"]}}}"#
        XCTAssertEqual(peers(json)?.first?.host, "100.64.0.5")
        XCTAssertEqual(peers(json)?.first?.addresses, ["100.64.0.5", "box.x.ts.net"])
    }

    func testMenuHidesMachineSavedUnderItsDNSNameOrAlias() {
        let peer = TailscalePeer(name: "lab-pc", host: "100.115.179.72", system: .windows, isOnline: true,
                                 dnsName: "lab-pc.tail1.ts.net")
        let byDNS = RemoteUsageDevice(name: "Lab", host: "lab-pc.tail1.ts.net", platform: .windows)
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [byDNS], draftPlatform: .linux), [])
        let byAlias = RemoteUsageDevice(name: "Lab", host: "lab", platform: .windows)
        let aliases = ["lab": SSHResolvedDestination(user: "smilelab", hostName: "100.115.179.72", port: 22)]
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [byAlias], draftPlatform: .linux, aliases: aliases), [])
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [byAlias], draftPlatform: .linux), [peer])
    }

    func testStoppedBackendAndGarbage() {
        XCTAssertEqual(TailscaleDiscovery.parse(Data(#"{"BackendState":"Stopped","Peer":null}"#.utf8)), .notRunning)
        XCTAssertNil(TailscaleDiscovery.parse(Data("not json".utf8)))
        XCTAssertNil(TailscaleDiscovery.parse(Data(#"{"something":"else"}"#.utf8)))
    }

    func testFallsThroughBrokenCandidates() async {
        let running = Data(#"{"BackendState":"Running","Peer":{"a":{"DNSName":"lab.x.ts.net.","OS":"linux","Online":true}}}"#.utf8)
        let outcome = await TailscaleDiscovery.discover(candidates: ["broken", "garbage", "app"]) { binary in
            switch binary {
            case "broken": nil
            case "garbage": Data("oops".utf8)
            default: running
            }
        }
        XCTAssertEqual(outcome, .peers([TailscalePeer(name: "lab", host: "lab.x.ts.net", system: .linux, isOnline: true)]))
    }

    func testReportsNotConnectedOrUnavailable() async {
        let stopped = Data(#"{"BackendState":"NeedsLogin"}"#.utf8)
        let notConnected = await TailscaleDiscovery.discover(candidates: ["cli"]) { _ in stopped }
        XCTAssertEqual(notConnected, .notConnected)
        let none = await TailscaleDiscovery.discover(candidates: []) { _ in stopped }
        XCTAssertEqual(none, .unavailable)
    }

    func testCandidatesIncludeFixedPathsAndAppBinary() {
        let candidates = TailscaleDiscovery.candidates(path: "/usr/bin:/bin")
        XCTAssertEqual(candidates.suffix(3), [
            "/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ])
        XCTAssertEqual(TailscaleDiscovery.cliEnvironment(from: [:])["TAILSCALE_BE_CLI"], "1")
    }

    func testPlatformMapping() {
        XCTAssertEqual(RemoteUsageDevice.Platform(tailscale: .macOS), .macOS)
        XCTAssertEqual(RemoteUsageDevice.Platform(tailscale: .windows), .windows)
        XCTAssertEqual(RemoteUsageDevice.Platform(tailscale: .unknown), .linux)
        XCTAssertEqual(RemoteUsageDevice.Platform(tailscale: .windows, keeping: .wsl), .wsl)
        XCTAssertEqual(RemoteUsageDevice.Platform(tailscale: .linux, keeping: .wsl), .linux)
    }

    /// Regression: a Windows host saved as Windows stayed hidden even with Windows + WSL selected.
    func testMenuKeepsWindowsHostForWSLAfterWindowsIsSaved() {
        let peer = TailscalePeer(name: "lab-pc", host: "lab-pc.tail1234.ts.net", system: .windows, isOnline: true)
        let windows = RemoteUsageDevice(name: "Lab", host: "Lab-PC.tail1234.ts.net", platform: .windows)
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [windows], draftPlatform: .wsl), [peer])
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [windows], draftPlatform: .linux), [])

        let wsl = RemoteUsageDevice(name: "Lab WSL", host: peer.host, platform: .wsl)
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [wsl], draftPlatform: .linux), [peer])
        XCTAssertEqual(TailscaleDiscovery.unsaved([peer], saved: [windows, wsl], draftPlatform: .wsl), [])
    }
}
