import Foundation

enum LiveFamily: String, Sendable, CaseIterable {
    case claude, codex
}

/// Where `LiveActivityStore` gets one family's recent token buckets: the log tail, or demo mode's
/// synthetic source.
protocol LiveTailSource: Actor {
    func poll(now: Date) async -> LiveRateBuckets
}

/// Live token speed from this Mac's recent Claude or Codex session logs. Each poll looks only at files
/// modified in the last 30 minutes and reads only bytes appended since the previous poll, parsing
/// complete lines with the same parsers the daily history uses, so live and daily counts agree.
///
/// Every file keeps its own buckets: when a file shrinks (rewritten or truncated) only that file's
/// contribution is dropped and re-read, which keeps a rewrite from double counting.
actor LiveLogTail: LiveTailSource {
    static let window: TimeInterval = 30 * 60
    static let discoveryInterval: TimeInterval = 10

    private struct Cursor {
        var offset: UInt64 = 0
        /// The file behind the path (device + inode). A different file at the same path (an atomic
        /// rewrite or a re-synced archive) restarts this cursor even when it isn't shorter.
        var fileID: FileID?
        var buckets: LiveRateBuckets
        /// Codex rollouts are stateful (model, cumulative totals, replay gates), so the parser travels
        /// with the file's cursor.
        var codexParser: CodexLogFileParser?
    }

    private let family: LiveFamily
    private let candidateFiles: @Sendable (_ modifiedSince: Date) async -> [URL]
    private var cursors: [String: Cursor] = [:]
    private var knownFiles: [URL] = []
    /// Paths whose read failure was already logged, so a persistent failure logs once, not every poll.
    private var failingPaths: Set<String> = []

    private struct FileID: Equatable {
        var device: dev_t
        var inode: ino_t
    }
    private var lastDiscovery: Date?
    /// Claude dedup across files with the history scanner's rules (`ClaudeLogUsageScanner.dedup`):
    /// "messageID|requestID" → the kept entry and the file that counted it, plus a message-only index
    /// so a sidechain replay under a new request id collides too. A preferred duplicate (parent over
    /// sidechain, then more tokens) takes the kept entry's tokens back and counts its own.
    private var claudeKept: [String: (path: String, entry: ClaudeLogUsageScanner.Entry)] = [:]
    private var claudeKeysByMessage: [String: Set<String>] = [:]
    /// Codex dedup across files with the history aggregation's rule: an identical turn (same time,
    /// model, and counts) counts once, so a rollout copied into two roots doesn't double the speed.
    private var codexKept: [CodexLogUsageScanner.EventKey: String] = [:]

    init(family: LiveFamily, candidateFiles: @escaping @Sendable (_ modifiedSince: Date) async -> [URL]) {
        self.family = family
        self.candidateFiles = candidateFiles
    }

    func poll(now: Date) async -> LiveRateBuckets {
        // Walking the log folders is the costly part of a poll, so it runs every 10 s; the polls in
        // between only read bytes appended to the files already known.
        if let lastDiscovery, now.timeIntervalSince(lastDiscovery) < Self.discoveryInterval, now >= lastDiscovery {
            for url in knownFiles { read(url, now: now) }
        } else {
            let files = await candidateFiles(now.addingTimeInterval(-Self.window))
            knownFiles = files
            lastDiscovery = now
            let current = Set(files.map(\.path))
            for path in cursors.keys where !current.contains(path) { forget(path) }
            for url in files { read(url, now: now) }
        }
        dropClaudeKeys { now.timeIntervalSince($0.entry.timestamp) > Self.window }
        codexKept = codexKept.filter { now.timeIntervalSince($0.key.timestamp) <= Self.window }
        return LiveRateBuckets.merged(cursors.values.map(\.buckets), now: now)
    }

    func reset() {
        cursors = [:]
        knownFiles = []
        failingPaths = []
        lastDiscovery = nil
        claudeKept = [:]
        claudeKeysByMessage = [:]
        codexKept = [:]
    }

    private func reportFailure(_ path: String, _ error: Error) {
        guard failingPaths.insert(path).inserted else { return }
        AppLog.warn(LogTag.plugin(family.rawValue), "live activity can't read \((path as NSString).lastPathComponent): \(error.localizedDescription)")
    }

    private func newCursor(now: Date) -> Cursor {
        Cursor(buckets: LiveRateBuckets(now: now), codexParser: family == .codex ? CodexLogFileParser() : nil)
    }

    private func forget(_ path: String) {
        cursors[path] = nil
        dropClaudeKeys { $0.path == path }
        codexKept = codexKept.filter { $0.value != path }
    }

    private func dropClaudeKeys(where shouldDrop: ((path: String, entry: ClaudeLogUsageScanner.Entry)) -> Bool) {
        for (key, kept) in claudeKept where shouldDrop(kept) {
            claudeKept[key] = nil
            if let messageID = kept.entry.messageID {
                claudeKeysByMessage[messageID]?.remove(key)
                if claudeKeysByMessage[messageID]?.isEmpty == true { claudeKeysByMessage[messageID] = nil }
            }
        }
    }

    /// Applies the history scanner's dedup to one new Claude entry against everything kept so far.
    private func count(_ entry: ClaudeLogUsageScanner.Entry, path: String, cursor: inout Cursor, now: Date) {
        guard let messageID = entry.messageID else {
            cursor.buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: now)
            return
        }
        let key = "\(messageID)|\(entry.requestID ?? "")"
        let collision: String? = claudeKept[key] != nil ? key : claudeKeysByMessage[messageID]?.first(where: { other in
            entry.isSidechain || claudeKept[other]?.entry.isSidechain == true
        })
        if let collision, let kept = claudeKept[collision] {
            guard ClaudeLogUsageScanner.shouldReplace(candidate: entry, existing: kept.entry) else { return }
            let old = kept.entry
            if kept.path == path {
                cursor.buckets.remove(tokens: old.tokens.totalTokens, at: old.timestamp, now: now)
            } else {
                cursors[kept.path]?.buckets.remove(tokens: old.tokens.totalTokens, at: old.timestamp, now: now)
            }
            claudeKept[collision] = nil
            claudeKeysByMessage[messageID]?.remove(collision)
        }
        claudeKept[key] = (path, entry)
        claudeKeysByMessage[messageID, default: []].insert(key)
        cursor.buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: now)
    }

    private func read(_ url: URL, now: Date) {
        let path = url.path
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            // A session moved or deleted since discovery (Codex archives finished rollouts) is normal;
            // anything else (permissions) would otherwise read as "Idle" with no trace.
            if FileManager.default.fileExists(atPath: path) { reportFailure(path, error) }
            return
        }
        defer { try? handle.close() }
        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch {
            reportFailure(path, error)
            return
        }
        failingPaths.remove(path)

        var info = stat()
        let fileID = fstat(handle.fileDescriptor, &info) == 0 ? FileID(device: info.st_dev, inode: info.st_ino) : nil
        if let existing = cursors[path],
           size < existing.offset || (fileID != nil && existing.fileID != nil && fileID != existing.fileID) {
            forget(path)
        }
        var cursor: Cursor
        if let existing = cursors[path] {
            cursor = existing
        } else {
            cursor = newCursor(now: now)
            cursor.fileID = fileID
            // A new log starts where its last half hour begins, not at byte 0 (an active Codex rollout or
            // Claude session runs to tens of megabytes). A Codex parser resumed partway seeds its running
            // total from the first line it sees; a rollout begun inside the window (a child session that
            // replays its parent first) is read whole, since the offset is then 0.
            cursor.offset = LiveTailStart.offset(size: size, since: now.addingTimeInterval(-Self.window)) { offset, count in
                try? handle.seek(toOffset: offset)
                return try? handle.read(upToCount: count)
            }
            if cursor.offset > 0 { cursor.codexParser?.resumeMidFile() }
        }
        guard size > cursor.offset else {
            cursors[path] = cursor
            return
        }
        try? handle.seek(toOffset: cursor.offset)
        guard let data = try? handle.read(upToCount: Int(size - cursor.offset)),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else {
            cursors[path] = cursor   // only a partial line so far; read it once it is complete
            return
        }
        let complete = Data(data[data.startIndex...lastNewline])
        cursor.offset += UInt64(complete.count)

        switch family {
        case .claude:
            for entry in ClaudeLogUsageScanner.parseFile(complete) {
                count(entry, path: path, cursor: &cursor, now: now)
            }
        case .codex:
            var parser = cursor.codexParser ?? CodexLogFileParser()
            for event in parser.parse(complete) {
                let key = CodexLogUsageScanner.EventKey(event)
                guard codexKept[key] == nil else { continue }
                codexKept[key] = path
                cursor.buckets.add(tokens: event.total, at: event.timestamp, now: now)
            }
            cursor.codexParser = parser
        }
        cursors[path] = cursor
    }
}
