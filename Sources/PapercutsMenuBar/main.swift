import AppKit
import Darwin
import PapercutsCore
import SwiftUI

@main
struct PapercutsMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PapercutsModel()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var socketServer: PapercutsSocketServer!
    private var globalMouseMonitor: Any?
    private let panelSize = NSSize(width: 410, height: 560)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Papercuts")
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusItemClicked(_:))

        model.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        socketServer = PapercutsSocketServer(model: model)

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: PapercutPopover(model: model))
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            let location = NSEvent.mouseLocation
            guard !self.panel.frame.contains(location), !self.statusItemFrame.contains(location) else { return }
            self.panel.orderOut(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        socketServer?.stop()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu(for: sender, event: event)
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            let anchorRect = button.convert(button.bounds, to: nil)
            guard let screenRect = button.window?.convertToScreen(anchorRect) else { return }
            let origin = NSPoint(
                x: screenRect.midX - panelSize.width / 2,
                y: screenRect.minY - panelSize.height - 8
            )
            panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
            panel.orderFrontRegardless()
        }
    }

    private var statusItemFrame: NSRect {
        guard let button = statusItem?.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshPapercuts), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Papercuts", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func refreshPapercuts() {
        model.reload()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.title = model.unreadCount > 0 ? "\(model.unreadCount)" : ""
        button.toolTip = model.unreadCount > 0 ? "Papercuts — \(model.unreadCount) unread" : "Papercuts"
    }
}

@MainActor
final class PapercutsModel: ObservableObject {
    @Published private(set) var cuts: [Papercut] = []
    @Published private(set) var errorMessage: String?
    var onChange: (() -> Void)?

    private let store = PapercutStore.shared
    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    var unreadCount: Int { cuts.filter { !$0.isRead }.count }

    func reload() {
        do {
            cuts = try store.all()
            errorMessage = nil
            onChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRead(_ isRead: Bool, for cut: Papercut) {
        do {
            try store.setRead(isRead, for: cut.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ cut: Papercut) {
        do {
            try store.delete(id: cut.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPrompt(for cut: Papercut) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cut.formattedPrompt, forType: .string)
    }

    func add(
        title: String,
        description: String,
        whyItMatters: String,
        prompt: String,
        repositoryPath: String,
        branch: String?,
        model: String?
    ) throws -> Papercut {
        let context = RepositoryContext.detect(at: URL(fileURLWithPath: repositoryPath))
        let papercut = Papercut(
            title: title,
            description: description,
            whyItMatters: whyItMatters,
            prompt: prompt,
            repository: context.repository,
            repositoryPath: context.repositoryPath,
            branch: branch ?? context.branch,
            model: model
        )
        try store.add(papercut)
        reload()
        return papercut
    }

    func list(repositoryPath: String?) throws -> [Papercut] {
        let cuts = try store.all()
        guard let repositoryPath else { return cuts }
        let context = RepositoryContext.detect(at: URL(fileURLWithPath: repositoryPath))
        return cuts.filter { $0.repositoryPath == context.repositoryPath }
    }

    func edit(
        id: UUID,
        title: String?,
        description: String?,
        whyItMatters: String?,
        prompt: String?,
        branch: String?,
        model: String?
    ) throws -> Papercut? {
        guard var papercut = try store.all().first(where: { $0.id == id }) else { return nil }
        if let title { papercut.title = title }
        if let description { papercut.description = description }
        if let whyItMatters { papercut.whyItMatters = whyItMatters }
        if let prompt { papercut.prompt = prompt }
        if let branch { papercut.branch = branch }
        if let model { papercut.model = model }
        guard try store.update(papercut) else { return nil }
        reload()
        return papercut
    }
}

private let papercutsSocketMaxRequestSize = 64 * 1024

@MainActor
private final class PapercutsSocketServer {
    private static let socketURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Papercuts", isDirectory: true)
        .appendingPathComponent("papercuts.sock")
    private let model: PapercutsModel
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?

    init(model: PapercutsModel) {
        self.model = model
        start()
    }

    func stop() {
        listenerSource?.cancel()
        listenerSource = nil
        listenerDescriptor = -1
        unlink(Self.socketURL.path)
    }

    private func start() {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: Self.socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            print("Papercuts socket unavailable: \(error.localizedDescription)")
            return
        }

        unlink(Self.socketURL.path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            print("Papercuts socket unavailable: could not create socket")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(Self.socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            print("Papercuts socket unavailable: socket path is too long")
            return
        }
        _ = pathBytes.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                memcpy(destination.baseAddress, source.baseAddress, pathBytes.count)
            }
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            print("Papercuts socket unavailable: could not bind socket")
            return
        }

        chmod(Self.socketURL.path, 0o600)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        listenerDescriptor = descriptor

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.acceptConnections() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        listenerSource = source
    }

    private func acceptConnections() {
        guard listenerDescriptor >= 0 else { return }
        while true {
            let client = accept(listenerDescriptor, nil, nil)
            guard client >= 0 else {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let requestData = Self.readRequest(from: client) else {
                    close(client)
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        close(client)
                        return
                    }
                    Self.write(self.response(for: requestData), to: client)
                    close(client)
                }
            }
        }
    }

    private func response(for data: Data) -> Data {
        do {
            let request = try JSONDecoder().decode(PapercutsSocketRequest.self, from: data)
            switch request.action {
            case "list":
                let papercuts = try model.list(repositoryPath: request.repositoryPath)
                return encoded(PapercutsSocketResponse(ok: true, papercut: nil, papercuts: papercuts, error: nil))
            case "add":
                guard
                    let title = nonEmpty(request.title),
                    let description = nonEmpty(request.description),
                    let why = nonEmpty(request.why),
                    let prompt = nonEmpty(request.prompt),
                    let repositoryPath = nonEmpty(request.repositoryPath)
                else {
                    return encoded(error: "add requires title, description, why, prompt, and repositoryPath")
                }

                let papercut = try model.add(
                    title: title,
                    description: description,
                    whyItMatters: why,
                    prompt: prompt,
                    repositoryPath: repositoryPath,
                    branch: request.branch,
                    model: request.model
                )
                return encoded(PapercutsSocketResponse(ok: true, papercut: papercut, papercuts: nil, error: nil))
            case "edit":
                guard let id = request.id else {
                    return encoded(error: "edit requires id")
                }
                guard let papercut = try model.edit(
                    id: id,
                    title: request.title,
                    description: request.description,
                    whyItMatters: request.why,
                    prompt: request.prompt,
                    branch: request.branch,
                    model: request.model
                ) else {
                    return encoded(error: "papercut not found: \(id.uuidString)")
                }
                return encoded(PapercutsSocketResponse(ok: true, papercut: papercut, papercuts: nil, error: nil))
            default:
                return encoded(error: "unknown action: \(request.action)")
            }
        } catch {
            return encoded(error: error.localizedDescription)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func encoded(_ response: PapercutsSocketResponse) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = (try? encoder.encode(response)) ?? Data(#"{\"ok\":false,\"error\":\"Could not encode response\"}"#.utf8)
        data.append(10)
        return data
    }

    private func encoded(error: String) -> Data {
        encoded(PapercutsSocketResponse(ok: false, papercut: nil, papercuts: nil, error: error))
    }

    private nonisolated static func readRequest(from client: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count < papercutsSocketMaxRequestSize {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(client, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { return data.isEmpty ? nil : data }
            data.append(buffer, count: count)
            if buffer[..<count].contains(10) { return data }
        }

        return nil
    }

    private nonisolated static func write(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { bytes in
            _ = Darwin.write(client, bytes.baseAddress, bytes.count)
        }
    }
}

struct TerminalApplication: Hashable, Identifiable {
    let id: String
    let name: String
    let applicationURL: URL
}

enum TerminalLauncher {
    private static let knownTerminals = [
        ("Terminal", "com.apple.Terminal"),
        ("iTerm2", "com.googlecode.iterm2"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("WezTerm", "com.github.wez.wezterm"),
        ("Alacritty", "org.alacritty"),
        ("kitty", "net.kovidgoyal.kitty")
    ]

    static func installed() -> [TerminalApplication] {
        knownTerminals.compactMap { name, bundleIdentifier in
            guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return nil
            }
            return TerminalApplication(id: bundleIdentifier, name: name, applicationURL: applicationURL)
        }
    }

    static func open(_ terminal: TerminalApplication, at path: String) {
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: terminal.applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

struct PapercutPopover: View {
    @ObservedObject var model: PapercutsModel
    @State private var selectedID: UUID?
    @State private var collapsedRepositories: Set<String> = []
    private let terminals = TerminalLauncher.installed()

    var body: some View {
        ZStack {
            PapercutVisualEffect(material: .hudWindow)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle()
                    .fill(PapercutTheme.border.opacity(0.9))
                    .frame(height: 1)

                if let errorMessage = model.errorMessage {
                    EmptyStateView(title: "Store unavailable", systemImage: "exclamationmark.triangle", message: errorMessage)
                } else if model.cuts.isEmpty {
                    EmptyStateView(title: "No papercuts yet", systemImage: "sparkles", message: "Agents can add one through the Papercuts socket.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groupedCuts, id: \.repository) { group in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            if collapsedRepositories.contains(group.repository) {
                                                collapsedRepositories.remove(group.repository)
                                            } else {
                                                collapsedRepositories.insert(group.repository)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(group.repository)
                                                .font(.system(size: 10, weight: .semibold))
                                                .tracking(0.7)
                                                .foregroundStyle(PapercutTheme.secondary)
                                            Spacer(minLength: 0)
                                            Image(systemName: collapsedRepositories.contains(group.repository) ? "chevron.right" : "chevron.down")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(PapercutTheme.muted)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.top, 13)
                                        .padding(.bottom, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if !collapsedRepositories.contains(group.repository) {
                                        ForEach(group.cuts) { cut in
                                            PapercutRow(
                                                cut: cut,
                                                isExpanded: selectedID == cut.id,
                                                onToggle: {
                                                    withAnimation(.spring(response: 0.22, dampingFraction: 1)) {
                                                        selectedID = selectedID == cut.id ? nil : cut.id
                                                    }
                                                    if !cut.isRead { model.setRead(true, for: cut) }
                                                },
                                                onMarkUnread: { model.setRead(false, for: cut) },
                                                onCopy: { model.copyPrompt(for: cut) },
                                                onDelete: {
                                                    if selectedID == cut.id { selectedID = nil }
                                                    model.delete(cut)
                                                },
                                                onOpenInTerminal: { terminal in
                                                    TerminalLauncher.open(terminal, at: cut.repositoryPath)
                                                },
                                                terminals: terminals
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .scrollIndicators(.hidden)
                }

                Rectangle()
                    .fill(PapercutTheme.border.opacity(0.9))
                    .frame(height: 1)
                HStack {
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.system(size: 9))
                        .foregroundStyle(PapercutTheme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
        .preferredColorScheme(.dark)
    }

    private var groupedCuts: [(repository: String, cuts: [Papercut])] {
        Dictionary(grouping: model.cuts, by: \.repository)
            .map { (repository: $0.key, cuts: $0.value) }
            .sorted { $0.cuts[0].createdAt > $1.cuts[0].createdAt }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "scissors")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PapercutTheme.primary)
                .frame(width: 28, height: 28)
                .background(PapercutTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(PapercutTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text("Papercuts")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PapercutTheme.primary)
                Text(model.unreadCount == 0 ? "All caught up" : "\(model.unreadCount) need attention")
                    .font(.system(size: 11))
                    .foregroundStyle(PapercutTheme.secondary)
            }

            Spacer()

            Button(action: model.reload) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PapercutTheme.secondary)
                    .frame(width: 28, height: 28)
                    .background(PapercutTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(PapercutTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(PapercutTheme.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PapercutTheme.primary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(PapercutTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct PapercutVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct PapercutRow: View {
    let cut: Papercut
    let isExpanded: Bool
    let onToggle: () -> Void
    let onMarkUnread: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onOpenInTerminal: (TerminalApplication) -> Void
    let terminals: [TerminalApplication]
    @State private var didCopy = false
    @State private var isHovering = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(cut.isRead ? PapercutTheme.muted : PapercutTheme.primary)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(cut.title)
                            .font(.system(size: 13, weight: cut.isRead ? .medium : .semibold))
                            .foregroundStyle(PapercutTheme.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(cut.repository)
                            Text("·")
                            Text(cut.branch)
                            if let model = cut.model, !model.isEmpty {
                                Text("·")
                                Text(model)
                            }
                            Spacer(minLength: 0)
                            Text(relativeAge(cut.createdAt))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(PapercutTheme.secondary)
                        .lineLimit(1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PapercutTheme.muted)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    detail("What happened", cut.description)
                    detail("Why it matters", cut.whyItMatters)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("SUGGESTED PROMPT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(PapercutTheme.secondary)
                        Text(cut.prompt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(PapercutTheme.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PapercutTheme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PapercutTheme.border, lineWidth: 1))
                    }

                    HStack(spacing: 8) {
                        Button {
                            onCopy()
                            withAnimation(.spring(response: 0.2, dampingFraction: 1)) { didCopy = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeOut(duration: 0.12)) { didCopy = false }
                            }
                        } label: {
                            Label(didCopy ? "Copied" : "Copy prompt", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(PapercutButtonStyle(prominent: true))
                        .controlSize(.small)

                        Button("Mark unread", action: onMarkUnread)
                            .buttonStyle(PapercutButtonStyle(prominent: false))
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 15)
                .padding(.top, 13)
                .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isExpanded ? PapercutTheme.surface : (isHovering ? PapercutTheme.hover : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isExpanded ? PapercutTheme.borderStrong : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy prompt", systemImage: "doc.on.doc")
            }

            if terminals.isEmpty {
                Text("No terminal apps detected")
            } else {
                Menu("Open in") {
                    ForEach(terminals) { terminal in
                        Button {
                            onOpenInTerminal(terminal)
                        } label: {
                            Label(terminal.name, systemImage: "terminal")
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this papercut?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        }
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(PapercutTheme.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(PapercutTheme.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum PapercutTheme {
    static let background = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let surface = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let hover = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let border = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let borderStrong = Color(red: 0.22, green: 0.22, blue: 0.22)
    static let primary = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let secondary = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let muted = Color(red: 0.32, green: 0.32, blue: 0.35)
}

private func relativeAge(_ date: Date) -> String {
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
    if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
    return "\(Int(seconds / 86_400))d ago"
}

private struct PapercutButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? PapercutTheme.background : PapercutTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(prominent ? PapercutTheme.primary : PapercutTheme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PapercutTheme.borderStrong, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
