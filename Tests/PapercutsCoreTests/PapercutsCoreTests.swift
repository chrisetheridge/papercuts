import Foundation
import Testing
@testable import PapercutsCore

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
    #expect(newer.formattedPrompt.contains("Context:\nd"))
    #expect(newer.formattedPrompt.contains("Why it matters:\nw"))
    #expect(newer.formattedPrompt.contains("How to fix it:\np"))
    try store.delete(id: newer.id)
    #expect(try store.all().map(\.title) == ["Older"])
}
