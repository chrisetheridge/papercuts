import Foundation
import Testing
@testable import PapercutsCore

private func runGit(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

@Test func repositoryNameUsesGitRemote() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try runGit(["-C", directory.path, "init", "-q"])
    try runGit(["-C", directory.path, "remote", "add", "origin", "git@github.com:example/actual-repository.git"])

    #expect(RepositoryContext.detect(at: directory).repository == "actual-repository")
}

@Test func storeAddsAndSortsPapercuts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PapercutStore(directoryURL: directory)
    let older = Papercut(title: "Older", description: "d", whyItMatters: "w", prompt: "p", repository: "repo", repositoryPath: "/repo", branch: "main", createdAt: Date(timeIntervalSince1970: 1))
    let newer = Papercut(title: "Newer", description: "d", whyItMatters: "w", prompt: "p", repository: "repo", repositoryPath: "/repo", branch: "feature", model: "gpt-5", createdAt: Date(timeIntervalSince1970: 2))

    try store.add(older)
    try store.add(newer)

    #expect(try store.all().map(\.title) == ["Newer", "Older"])
    try store.setRead(true, for: newer.id)
    #expect(try store.all().first?.isRead == true)
    var edited = try store.all().first!
    edited.title = "Edited"
    #expect(try store.update(edited))
    #expect(try store.all().first?.title == "Edited")
    #expect(newer.formattedPrompt.contains("Context:\nd"))
    #expect(newer.formattedPrompt.contains("Why it matters:\nw"))
    #expect(newer.formattedPrompt.contains("Investigation and fix guidance:\np"))
    #expect(newer.formattedPrompt.contains("Do not modify files or implement a fix yet."))
    try store.delete(id: newer.id)
    #expect(try store.all().map(\.title) == ["Older"])
}

@Test func socketRequestRoundTripsWireFields() throws {
    let request = PapercutsSocketRequest(
        action: "add",
        title: "Title",
        description: "Description",
        why: "Why",
        prompt: "Prompt",
        repositoryPath: "/repo",
        branch: "main",
        model: "gpt-5"
    )
    let decoded = try JSONDecoder().decode(
        PapercutsSocketRequest.self,
        from: JSONEncoder().encode(request)
    )

    #expect(decoded.action == "add")
    #expect(decoded.title == "Title")
    #expect(decoded.repositoryPath == "/repo")
    #expect(decoded.model == "gpt-5")
}
