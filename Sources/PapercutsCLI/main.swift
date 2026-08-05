import Darwin
import Foundation
import PapercutsCore

private let usage = """
Usage:
  papercuts list [--repository-path PATH]
  papercuts add --title TEXT --description TEXT --why TEXT --prompt TEXT [--model TEXT] [--branch TEXT]
  papercuts edit ID [--title TEXT] [--description TEXT] [--why TEXT] [--prompt TEXT] [--model TEXT] [--branch TEXT]
"""

private enum CLIError: Error {
    case usage(String)
    case server(String)

    var message: String {
        switch self {
        case .usage(let message), .server(let message): message
        }
    }
}

private var arguments = Array(CommandLine.arguments.dropFirst())

do {
    let response = try run()
    if !response.ok {
        throw CLIError.server(response.error ?? "Papercuts request failed")
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(response), as: UTF8.self))
} catch {
    let message: String
    if let cliError = error as? CLIError {
        message = cliError.message
    } else if let localizedError = error as? LocalizedError {
        message = localizedError.errorDescription ?? localizedError.localizedDescription
    } else {
        message = error.localizedDescription
    }
    fputs("papercuts: \(message)\n", stderr)
    exit(1)
}

@MainActor
private func run() throws -> PapercutsSocketResponse {
    guard let action = arguments.first else { throw CLIError.usage(usage) }
    arguments.removeFirst()
    if action == "help" || action == "--help" {
        print(usage)
        fflush(stdout)
        exit(0)
    }

    let repositoryPath = try option("--repository-path") ?? RepositoryContext.detect().repositoryPath
    let request: PapercutsSocketRequest

    switch action {
    case "list":
        try ensureNoArguments()
        request = PapercutsSocketRequest(action: action, repositoryPath: repositoryPath)
    case "add":
        request = PapercutsSocketRequest(
            action: action,
            title: try requiredOption("--title"),
            description: try requiredOption("--description"),
            why: try requiredOption("--why"),
            prompt: try requiredOption("--prompt"),
            repositoryPath: repositoryPath,
            branch: try option("--branch"),
            model: try option("--model")
        )
        try ensureNoArguments()
    case "edit":
        guard let id = arguments.first.flatMap(UUID.init) else {
            throw CLIError.usage("edit requires a valid papercut ID\n\n\(usage)")
        }
        arguments.removeFirst()
        request = PapercutsSocketRequest(
            action: action,
            id: id,
            title: try option("--title"),
            description: try option("--description"),
            why: try option("--why"),
            prompt: try option("--prompt"),
            branch: try option("--branch"),
            model: try option("--model")
        )
        try ensureNoArguments()
    default:
        throw CLIError.usage("unknown command: \(action)\n\n\(usage)")
    }

    return try PapercutsSocketClient().send(request)
}

@MainActor
private func option(_ name: String) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    arguments.remove(at: index)
    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
        throw CLIError.usage("\(name) requires a value")
    }
    return arguments.remove(at: index)
}

@MainActor
private func requiredOption(_ name: String) throws -> String {
    guard let value = try option(name) else {
        throw CLIError.usage("missing \(name)\n\n\(usage)")
    }
    return value
}

@MainActor
private func ensureNoArguments() throws {
    guard arguments.isEmpty else {
        throw CLIError.usage("unexpected arguments: \(arguments.joined(separator: " "))\n\n\(usage)")
    }
}
