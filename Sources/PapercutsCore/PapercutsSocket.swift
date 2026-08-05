import Darwin
import Foundation

public struct PapercutsSocketRequest: Codable, Sendable {
    public let action: String
    public let id: UUID?
    public let title: String?
    public let description: String?
    public let why: String?
    public let prompt: String?
    public let repositoryPath: String?
    public let branch: String?
    public let model: String?

    public init(
        action: String,
        id: UUID? = nil,
        title: String? = nil,
        description: String? = nil,
        why: String? = nil,
        prompt: String? = nil,
        repositoryPath: String? = nil,
        branch: String? = nil,
        model: String? = nil
    ) {
        self.action = action
        self.id = id
        self.title = title
        self.description = description
        self.why = why
        self.prompt = prompt
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.model = model
    }
}

public struct PapercutsSocketResponse: Codable, Sendable {
    public let ok: Bool
    public let papercut: Papercut?
    public let papercuts: [Papercut]?
    public let error: String?

    public init(ok: Bool, papercut: Papercut?, papercuts: [Papercut]?, error: String?) {
        self.ok = ok
        self.papercut = papercut
        self.papercuts = papercuts
        self.error = error
    }
}

public final class PapercutsSocketClient: Sendable {
    public static let socketURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Papercuts", isDirectory: true)
        .appendingPathComponent("papercuts.sock")

    private let timeoutMilliseconds: Int32

    public init(timeout: TimeInterval = 5) {
        timeoutMilliseconds = max(1, Int32(min(timeout * 1_000, Double(Int32.max))))
    }

    public func send(_ request: PapercutsSocketRequest) throws -> PapercutsSocketResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw PapercutsSocketError.socketUnavailable }
        defer { close(descriptor) }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(Self.socketURL.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw PapercutsSocketError.socketPathTooLong
        }
        pathBytes.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.copyBytes(from: source)
            }
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw PapercutsSocketError.connectionFailed }

        var data = try JSONEncoder().encode(request)
        data.append(10)
        try write(data, to: descriptor)
        Darwin.shutdown(descriptor, SHUT_WR)

        let responseData = try readResponse(from: descriptor)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PapercutsSocketResponse.self, from: responseData)
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            while offset < data.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
                guard count > 0 else { throw PapercutsSocketError.writeFailed }
                offset += count
            }
        }
    }

    private func readResponse(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count < 64 * 1024 {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
            guard ready > 0 else {
                throw ready == 0 ? PapercutsSocketError.timedOut : PapercutsSocketError.readFailed
            }

            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { break }
            data.append(buffer, count: count)
            if let newline = data.firstIndex(of: 10) {
                return Data(data[..<newline])
            }
        }

        guard !data.isEmpty else { throw PapercutsSocketError.emptyResponse }
        throw PapercutsSocketError.responseTooLarge
    }
}

public enum PapercutsSocketError: LocalizedError {
    case socketUnavailable
    case socketPathTooLong
    case connectionFailed
    case timedOut
    case writeFailed
    case readFailed
    case emptyResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .socketUnavailable: "Could not create the Papercuts socket client."
        case .socketPathTooLong: "The Papercuts socket path is too long."
        case .connectionFailed: "Could not connect to Papercuts. Is the app running?"
        case .timedOut: "Timed out waiting for Papercuts."
        case .writeFailed: "Could not send the request to Papercuts."
        case .readFailed: "Could not read the response from Papercuts."
        case .emptyResponse: "Papercuts returned an empty response."
        case .responseTooLarge: "Papercuts returned an oversized response."
        }
    }
}
