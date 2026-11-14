import Foundation
import Darwin

/// A bounded mailbox feeds one serial utility queue. The lock protects only the
/// mailbox; file handles, rotation and export are owned exclusively by the queue.
final class DiagnosticStore: @unchecked Sendable {
    struct Limits: Sendable {
        var fileBytes = 2_000_000
        var totalBytes = 20_000_000
        var pendingEvents = 256
        var eventBytes = 8 * 1024
    }
    private struct Mailbox {
        var enabled: Bool
        var pending: [DiagnosticEvent] = []
        var scheduled = false
        var sequence: UInt64 = 0
        var generation: UInt64 = 0
        var health = DiagnosticHealth()
    }
    let directory: URL
    private let limits: Limits
    private let launchID = UUID()
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var mailbox: Mailbox
    private let queue: DispatchQueue
    private var exportLeases: [URL: Int32] = [:]
    var exportStagingDirectory: URL { directory.appendingPathComponent("Exports", isDirectory: true) }
    private var currentFile: URL?
    private var retryAfter = Date.distantPast
    private var reportedDrops = 0
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL, enabled: Bool = true, limits: Limits = Limits(),
         clock: @escaping @Sendable () -> Date = { Date() },
         queue: DispatchQueue = DispatchQueue(label: "com.mercury.breather.diagnostics", qos: .utility)) {
        self.directory = directory
        self.limits = limits
        self.clock = clock
        self.queue = queue
        mailbox = Mailbox(enabled: enabled)
    }

    deinit { for descriptor in exportLeases.values { Darwin.close(descriptor) } }

    var health: DiagnosticHealth { lock.withLock { mailbox.health } }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            mailbox.enabled = enabled
            // Disabling must not write previously queued private state afterward.
            if !enabled { mailbox.pending.removeAll(); mailbox.generation &+= 1; mailbox.scheduled = false }
        }
    }

    func record(_ kind: DiagnosticEvent.Kind, reason: String? = nil,
                snapshot: DiagnosticSnapshot? = nil, system: DiagnosticSystemEvent? = nil) {
        lock.withLock {
            guard mailbox.enabled else { return }
            mailbox.sequence &+= 1
            let event = DiagnosticEvent(schemaVersion: 1, timestamp: clock(), uptime: ProcessInfo.processInfo.systemUptime,
                                        launchID: launchID, sequence: mailbox.sequence, kind: kind,
                                        reason: reason, snapshot: snapshot, system: system, droppedEvents: nil)
            if mailbox.pending.count >= limits.pendingEvents {
                if let index = mailbox.pending.firstIndex(where: { $0.kind == .snapshot }) {
                    mailbox.pending.remove(at: index)
                } else if kind == .snapshot {
                    mailbox.health.droppedEvents += 1
                    return
                } else {
                    mailbox.pending.removeFirst()
                }
                mailbox.health.droppedEvents += 1
            }
            mailbox.pending.append(event)
            guard !mailbox.scheduled else { return }
            mailbox.scheduled = true
            let generation = mailbox.generation
            queue.async { self.drain(generation: generation) }
        }
    }

    private func drain(generation: UInt64? = nil) {
        var batchDrops = 0
        let batch = lock.withLock { () -> [DiagnosticEvent] in
            if let generation, generation != mailbox.generation { return [] }
            var batch = mailbox.pending
            mailbox.pending.removeAll(keepingCapacity: true)
            mailbox.scheduled = false
            batchDrops = mailbox.health.droppedEvents
            if !batch.isEmpty, batchDrops > reportedDrops {
                mailbox.sequence &+= 1
                batch.append(DiagnosticEvent(schemaVersion: 1, timestamp: clock(), uptime: ProcessInfo.processInfo.systemUptime,
                    launchID: launchID, sequence: mailbox.sequence, kind: .dataLoss, reason: nil,
                    snapshot: nil, system: nil, droppedEvents: batchDrops))
            }
            return batch
        }
        guard !batch.isEmpty else { return }
        guard clock() >= retryAfter else {
            lock.withLock { mailbox.health.droppedEvents += batch.count }
            return
        }
        do {
            try prepareDirectory()
            for event in batch { try append(event) }
            reportedDrops = batchDrops
            try prune()
            lock.withLock { mailbox.health.lastError = nil }
        } catch {
            retryAfter = clock().addingTimeInterval(60)
            lock.withLock {
                mailbox.health.writeFailures += 1
                mailbox.health.droppedEvents += batch.count
                mailbox.health.lastError = "write_failed"
            }
        }
    }

    private func prepareDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw DiagnosticFailure.unavailable }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var url = directory
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try? url.setResourceValues(resource)
    }

    private func append(_ event: DiagnosticEvent) throws {
        var data = try encoder.encode(event)
        data.append(0x0a)
        guard data.count <= limits.eventBytes, data.count <= limits.fileBytes else { throw DiagnosticFailure.oversizedEvent }
        let fm = FileManager.default
        if let file = currentFile {
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? limits.fileBytes
            if size + data.count > limits.fileBytes {
                currentFile = nil
            }
        }
        if currentFile == nil {
            let lastMilliseconds = try files().compactMap(fileDate).map { Int64($0.timeIntervalSince1970 * 1000) }.max() ?? 0
            let milliseconds = max(Int64(clock().timeIntervalSince1970 * 1000), lastMilliseconds + 1)
            let filename = "events-\(milliseconds)-\(UUID().uuidString).jsonl"
            let file = directory.appendingPathComponent(filename)
            guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw DiagnosticFailure.unavailable
            }
            currentFile = file
        }
        guard let file = currentFile,
              try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw DiagnosticFailure.unavailable
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func fileDate(_ url: URL) -> Date? {
        let parts = url.lastPathComponent.split(separator: "-")
        guard url.pathExtension == "jsonl", parts.count >= 3, parts[0] == "events",
              let milliseconds = Double(parts[1]) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw DiagnosticFailure.unavailable
        }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return fileDate(url) != nil && values.isRegularFile == true && values.isSymbolicLink != true
            }
            .sorted { ($0.lastPathComponent) < ($1.lastPathComponent) }
    }

    private func prune() throws {
        var retained: [(URL, Int)] = []
        for file in try files() {
            retained.append((file, (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0))
        }
        var total = retained.reduce(0) { $0 + $1.1 }
        for (file, size) in retained where total > limits.totalBytes {
            try FileManager.default.removeItem(at: file)
            if file == currentFile { currentFile = nil }
            total -= size
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { self.drain(); continuation.resume() }
        }
    }

    /// Normal termination must wait for queued writes, but must not hang on slow
    /// storage or an export. Call from outside the serial IO queue.
    @discardableResult
    func flushForTermination(timeout: TimeInterval = 2) -> Bool {
        let completed = DispatchSemaphore(value: 0)
        queue.async { self.drain(); completed.signal() }
        guard completed.wait(timeout: .now() + max(0, timeout)) == .success else { return false }
        return health.lastError == nil
    }

    func maintenance() async {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try self.prune()
                    try self.cleanAbandonedExports()
                } catch {
                    self.lock.withLock { self.mailbox.health.lastError = "cleanup_failed" }
                }
                continuation.resume()
            }
        }
    }

    func clear() async throws {
        // Enqueue under the mailbox lock so later writes occur after deletion.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                mailbox.pending.removeAll()
                mailbox.generation &+= 1
                mailbox.scheduled = false
                queue.async {
                    do {
                        for file in try self.files() { try FileManager.default.removeItem(at: file) }
                        try self.cleanAbandonedExports()
                        self.currentFile = nil
                        self.retryAfter = .distantPast
                        self.reportedDrops = 0
                        self.lock.withLock { self.mailbox.health = DiagnosticHealth() }
                        continuation.resume()
                    } catch { continuation.resume(throwing: DiagnosticFailure.unavailable) }
                }
            }
        }
    }

    func export(snapshot: DiagnosticSnapshot) async throws -> DiagnosticExport {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.drain()
                do { continuation.resume(returning: try self.makeExport(snapshot: snapshot)) }
                catch { continuation.resume(throwing: DiagnosticFailure.unavailable) }
            }
        }
    }

    private func makeExport(snapshot: DiagnosticSnapshot) throws -> DiagnosticExport {
        try prune()
        let fm = FileManager.default
        let temporary = try createExportStaging()
        var succeeded = false
        defer { if !succeeded { releaseExportStaging(temporary) } }
        let contents = temporary.appendingPathComponent("Breather-Diagnostics", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let eventsFile = contents.appendingPathComponent("events.jsonl")
        fm.createFile(atPath: eventsFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: eventsFile)
        defer { try? handle.close() }
        var count = 0, malformed = 0
        var earliest: Date?, latest: Date?
        for file in try files() {
            let data = try Data(contentsOf: file)
            for line in data.split(separator: 0x0a) {
                guard let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)) else { malformed += 1; continue }
                // Re-encoding a typed record also removes unexpected fields.
                var encoded = try encoder.encode(event)
                encoded.append(0x0a)
                try handle.write(contentsOf: encoded)
                count += 1
                earliest = min(earliest ?? event.timestamp, event.timestamp)
                latest = max(latest ?? event.timestamp, event.timestamp)
            }
        }
        try handle.close()
        try encoder.encode(snapshot).write(to: contents.appendingPathComponent("snapshot.json"), options: .atomic)
        let health = health
        let formatter = ISO8601DateFormatter()
        let summary = """
        Breather diagnostic report — schema 1
        App: \(snapshot.environment.appVersion) (\(snapshot.environment.build))
        macOS: \(snapshot.environment.macOSVersion); architecture: \(snapshot.environment.architecture)
        Events: \(count)
        Earliest: \(earliest.map(formatter.string) ?? "none")
        Latest: \(latest.map(formatter.string) ?? "none")
        Storage: up to 20 MB, oldest records are overwritten when full; no time-based expiry.
        Current launch dropped events: \(health.droppedEvents)
        Current launch write failures: \(health.writeFailures)
        Current storage error: \(health.lastError ?? "none")
        Unreadable lines skipped: \(malformed)
        Prior-launch dataLoss events and sequence gaps may indicate incomplete coverage.
        Lock, unlock and rest times may reveal usage habits. Share privately.
        Local data only. No screenshots, typed text, account or network details are collected.
        """
        try summary.write(to: contents.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        let archive = temporary.appendingPathComponent("Breather-Diagnostics.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--keepParent", contents.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiagnosticFailure.archiveFailed }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        succeeded = true
        return DiagnosticExport(directory: temporary, archive: archive, bytes: bytes, eventCount: count,
                                earliest: earliest, latest: latest, malformedLines: malformed)
    }

    func removeExport(_ export: DiagnosticExport) async {
        await withCheckedContinuation { continuation in
            queue.async { self.releaseExportStaging(export.directory); continuation.resume() }
        }
    }

    private func createExportStaging() throws -> URL {
        try prepareDirectory()
        let fm = FileManager.default
        let root = exportStagingDirectory
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw DiagnosticFailure.unavailable
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try cleanAbandonedExports()
        let folder = root.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let lease = folder.appendingPathExtension("lock")
        // O_EXLOCK acquires the lease atomically with creation. A scanner cannot
        // mistake a just-created file for an abandoned export before we lock it.
        let descriptor = Darwin.open(lease.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw DiagnosticFailure.unavailable }
        exportLeases[folder] = descriptor
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return folder
        } catch {
            releaseExportStaging(folder)
            throw error
        }
    }

    private func releaseExportStaging(_ folder: URL) {
        guard let descriptor = exportLeases.removeValue(forKey: folder) else { return }
        defer { Darwin.close(descriptor) }
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            try FileManager.default.removeItem(at: folder.appendingPathExtension("lock"))
        } catch {
            // Keep the now-unlocked lease so next startup can retry cleanup.
        }
    }

    private func cleanAbandonedExports() throws {
        let fm = FileManager.default
        let root = exportStagingDirectory
        guard fm.fileExists(atPath: root.path) else { return }
        guard try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw DiagnosticFailure.unavailable
        }
        for lease in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let name = lease.deletingPathExtension().lastPathComponent
            guard lease.pathExtension == "lock", name.hasPrefix("export-"),
                  UUID(uuidString: String(name.dropFirst(7))) != nil else { continue }
            let descriptor = Darwin.open(lease.path, O_RDWR | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK)
            if descriptor < 0 {
                if errno == EWOULDBLOCK || errno == ENOENT || errno == ELOOP || errno == EISDIR { continue }
                throw DiagnosticFailure.unavailable
            }
            defer { Darwin.close(descriptor) }
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw DiagnosticFailure.unavailable }
            guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { continue }
            let folder = lease.deletingPathExtension()
            if fm.fileExists(atPath: folder.path) {
                guard try fm.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType == .typeDirectory else { continue }
                try fm.removeItem(at: folder)
            }
            // Another cleaner may already have removed the same orphan while
            // this descriptor was being opened. Missing files are harmless.
            if fm.fileExists(atPath: lease.path) { try fm.removeItem(at: lease) }
        }
    }

    func saveExport(_ export: DiagnosticExport, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try Data(contentsOf: export.archive).write(to: destination, options: .atomic)
                    continuation.resume()
                } catch { continuation.resume(throwing: DiagnosticFailure.unavailable) }
            }
        }
    }
}
