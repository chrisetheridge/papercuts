import Foundation
import PapercutsCore

@main
struct PapercutCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("papercut: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "add":
            try add(Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func add(_ arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard (argument.hasPrefix("--") || argument == "-m"), index + 1 < arguments.count else {
                throw CLIError.invalidArgument(argument)
            }
            let key = argument == "-m" ? "model" : String(argument.dropFirst(2))
            guard ["title", "description", "why", "prompt", "repo", "branch", "model"].contains(key) else {
                throw CLIError.invalidArgument(argument)
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        for required in ["title", "description", "why", "prompt"] where values[required]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw CLIError.missingValue(required)
        }

        let context = values["repo"].map { RepositoryContext.detect(at: URL(fileURLWithPath: $0)) }
            ?? RepositoryContext.detect()
        let papercut = Papercut(
            title: values["title"]!,
            description: values["description"]!,
            whyItMatters: values["why"]!,
            prompt: values["prompt"]!,
            repository: context.repository,
            repositoryPath: context.repositoryPath,
            branch: values["branch"] ?? context.branch,
            model: values["model"]
        )

        try PapercutStore.shared.add(papercut)
        let modelSuffix = papercut.model.map { " / \($0)" } ?? ""
        print("Added papercut \(papercut.id.uuidString) for \(papercut.repository) / \(papercut.branch)\(modelSuffix)")
    }

    private static func printUsage() {
        print("""
        papercut add --title <title> --description <description> --why <why> --prompt <prompt> [--model <model>] [--repo <path>] [--branch <branch>]
        papercut add -m <model> --title <title> --description <description> --why <why> --prompt <prompt>
        """)
    }
}

private enum CLIError: LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument): "Invalid argument: \(argument)"
        case .missingValue(let key): "Missing value for --\(key)"
        case .unknownCommand(let command): "Unknown command: \(command)"
        }
    }
}
