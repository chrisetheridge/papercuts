import Darwin
import Foundation

public struct Papercut: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var description: String
    public var whyItMatters: String
    public var prompt: String
    public var repository: String
    public var repositoryPath: String
    public var branch: String
    public var model: String?
    public let createdAt: Date
    public var isRead: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        whyItMatters: String,
        prompt: String,
        repository: String,
        repositoryPath: String,
        branch: String,
        model: String? = nil,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.whyItMatters = whyItMatters
        self.prompt = prompt
        self.repository = repository
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.model = model
        self.createdAt = createdAt
        self.isRead = isRead
    }

    public var formattedPrompt: String {
        """
        You're fixing a small issue another agent encountered. Use the context and instruction to make the smallest possible fix to improve work for other agents.

        Context:
        \(description)

        Why it matters:
        \(whyItMatters)

        How to fix it:
        \(prompt)
        """
    }
}

public struct RepositoryContext: Sendable {
    public let repository: String
    public let repositoryPath: String
    public let branch: String

    public static func detect(at directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> Self {
        let directoryPath = directory.standardizedFileURL.path
        let rootPath = runGit(["-C", directoryPath, "rev-parse", "--show-toplevel"])
            ?? directoryPath
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let repository = rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
        let branch = runGit(["-C", rootURL.path, "branch", "--show-current"])
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? runGit(["-C", rootURL.path, "rev-parse", "--short", "HEAD"]).map { "detached @ \($0)" }
            ?? "No Git branch"

        return Self(repository: repository, repositoryPath: rootURL.path, branch: branch)
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class PapercutStore: @unchecked Sendable {
    public static let shared = PapercutStore()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileURL: URL
    private let lockURL: URL

    public init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        let environmentDirectory = ProcessInfo.processInfo.environment["PAPERCUTS_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.directoryURL = directoryURL ?? environmentDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Papercuts", isDirectory: true)
        self.fileURL = self.directoryURL.appendingPathComponent("papercuts.json")
        self.lockURL = self.directoryURL.appendingPathComponent("papercuts.lock")
    }

    public func all() throws -> [Papercut] {
        try withLock { try readUnlocked().sorted { $0.createdAt > $1.createdAt } }
    }

    public func add(_ papercut: Papercut) throws {
        try withLock {
            var cuts = try readUnlocked()
            cuts.append(papercut)
            try writeUnlocked(cuts)
        }
    }

    public func setRead(_ isRead: Bool, for id: UUID) throws {
        try withLock {
            var cuts = try readUnlocked()
            guard let index = cuts.firstIndex(where: { $0.id == id }) else { return }
            cuts[index].isRead = isRead
            try writeUnlocked(cuts)
        }
    }

    @discardableResult
    public func update(_ papercut: Papercut) throws -> Bool {
        try withLock {
            var cuts = try readUnlocked()
            guard let index = cuts.firstIndex(where: { $0.id == papercut.id }) else { return false }
            cuts[index] = papercut
            try writeUnlocked(cuts)
            return true
        }
    }

    public func delete(id: UUID) throws {
        try withLock {
            var cuts = try readUnlocked()
            cuts.removeAll { $0.id == id }
            try writeUnlocked(cuts)
        }
    }

    private func readUnlocked() throws -> [Papercut] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.papercuts.decode([Papercut].self, from: data)
    }

    private func writeUnlocked(_ cuts: [Papercut]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.papercuts.encode(cuts)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw PapercutStoreError.lockUnavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw PapercutStoreError.lockUnavailable }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}

public enum PapercutStoreError: LocalizedError {
    case lockUnavailable

    public var errorDescription: String? {
        switch self {
        case .lockUnavailable: "Could not access the papercut store."
        }
    }
}

private extension JSONEncoder {
    static var papercuts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var papercuts: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
