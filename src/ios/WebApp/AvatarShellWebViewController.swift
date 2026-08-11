import AVFoundation
import SwiftUI
import UIKit

extension Notification.Name {
    static let soulNestAvatarPresentation = Notification.Name("soulnest.avatar.presentation")
}

@MainActor
enum SoulNestAvatarPresentation {
    static func thinking() { post(action: "state", value: "thinking") }
    static func talking(subtitle: String? = nil) {
        post(action: "state", value: "talk_soft")
        if let subtitle, !subtitle.isEmpty { post(action: "subtitle", value: subtitle) }
    }
    static func say(_ text: String) {
        guard !text.isEmpty else { idle(); return }
        post(action: "say", value: text)
    }
    static func idle(clearSubtitle: Bool = true) {
        post(action: "state", value: "idle_01")
        if clearSubtitle { post(action: "clearSubtitle", value: nil) }
    }
    private static func post(action: String, value: String?) {
        var info: [String: Any] = ["action": action]
        if let value { info["value"] = value }
        NotificationCenter.default.post(name: .soulNestAvatarPresentation, object: nil, userInfo: info)
    }
}

@MainActor
final class NativeAvatarState: ObservableObject {
    @Published var state = "idle_01"
    @Published var subtitle = ""
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .soulNestAvatarPresentation, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.userInfo?["action"] as? String else { return }
            let value = note.userInfo?["value"] as? String ?? ""
            switch action {
            case "state": self.state = value
            case "subtitle": self.subtitle = value
            case "say": self.state = "talk_soft"; self.subtitle = value
            case "clearSubtitle": self.subtitle = ""
            default: break
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}

struct NativeAvatarAssetResolver {
    static let states: Set<String> = ["idle_01", "idle_02", "thinking", "talk_soft", "talk_happy", "talk_excited", "shy", "sad", "angry", "caring"]
    static let loopStates: Set<String> = ["idle_01", "idle_02", "thinking", "talk_soft", "talk_happy", "talk_excited"]

    static func avatarRoot(resourceURL: URL? = Bundle.main.resourceURL, fileManager: FileManager = .default) -> URL? {
        guard let resourceURL else { return nil }
        let root = resourceURL.appendingPathComponent("Avatar", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path), fileManager.isReadableFile(atPath: root.path) else { return nil }
        return root
    }

    static func url(outfit: String, state: String) -> URL? {
        let root = avatarRoot()
        let manager = FileManager.default
        func file(_ outfit: String, _ state: String) -> URL? {
            guard let root else { return nil }
            let url = root.appendingPathComponent("assets/videos/yujie-v1/\(outfit)/\(state).mp4")
            return manager.fileExists(atPath: url.path) && manager.isReadableFile(atPath: url.path) ? url : nil
        }
        let selectedOutfit = outfit == "shorts" ? "shorts_private_casual" : outfit
        if let url = file(selectedOutfit, state) ?? file(selectedOutfit, state.hasPrefix("talk_") ? "talk_soft" : "idle_01") ?? file("casual", state) { return url }
        let placeholder: String = switch state {
        case "idle_01", "idle_02": "idle"; case "thinking": "thinking"; case "talk_happy": "happy"; case "talk_excited": "excited"; case "shy": "shy"; case "sad": "sad"; case "angry": "angry"; case "caring": "talking"; default: "talking"
        }
        guard let root else { return nil }
        let url = root.appendingPathComponent("assets/videos/placeholder-\(placeholder).mp4")
        return manager.fileExists(atPath: url.path) && manager.isReadableFile(atPath: url.path) ? url : nil
    }
}

#if DEBUG
@MainActor
private final class NativeAvatarDiagnostics: ObservableObject {
    static let shared = NativeAvatarDiagnostics()

    @Published private(set) var text = "Waiting for Native Avatar diagnostics…"
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    func captureRuntime(outfit: String, state: String) {
        let bundle = Bundle.main
        let manager = FileManager.default
        append("=== Native Avatar runtime ===")
        append("Bundle.main.bundleURL: \(bundle.bundleURL.path)")
        append("Bundle.main.bundlePath: \(bundle.bundlePath)")
        append("Bundle.main.resourceURL: \(bundle.resourceURL?.path ?? "nil")")
        append("Bundle.main.resourcePath: \(bundle.resourcePath ?? "nil")")
        append("Bundle.main readable: \(manager.isReadableFile(atPath: bundle.bundlePath))")
        append("Bundle.main.bundleIdentifier: \(bundle.bundleIdentifier ?? "nil")")
        append("Bundle.main.executableURL: \(bundle.executableURL?.path ?? "nil")")
        append("NSHomeDirectory: \(NSHomeDirectory())")

        let root = NativeAvatarAssetResolver.avatarRoot(resourceURL: bundle.resourceURL, fileManager: manager)
        append("Avatar root: \(root?.path ?? "nil")")
        append("Avatar root exists/readable: \(root.map { manager.fileExists(atPath: $0.path) } ?? false)/\(root.map { manager.isReadableFile(atPath: $0.path) } ?? false)")

        let idleURL = NativeAvatarAssetResolver.url(outfit: "casual", state: "idle_01")
        appendFile("resolved casual/idle_01", url: idleURL)
        if let idleURL { inspectAsset(label: "resolved casual/idle_01", url: idleURL) }

        for name in ["placeholder-idle.mp4", "placeholder-thinking.mp4", "placeholder-talking.mp4"] {
            let url = root?.appendingPathComponent("assets/videos/\(name)")
            appendFile(name, url: url)
            if let url { inspectAsset(label: name, url: url) }
        }
    }

    func observe(player: AVPlayer, item: AVPlayerItem, view: UIView) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player, weak view] _, _ in
            DispatchQueue.main.async { self?.capturePlayer(player: player, item: item, view: view) }
        }
        playerStatusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self, weak view] _, _ in
            DispatchQueue.main.async { self?.capturePlayer(player: player, item: item, view: view) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak view] _, _ in
            DispatchQueue.main.async { self?.capturePlayer(player: player, item: item, view: view) }
        }
        capturePlayer(player: player, item: item, view: view)
        DispatchQueue.main.async { [weak self, weak player, weak view] in
            self?.capturePlayer(player: player, item: item, view: view)
        }
    }

    private func capturePlayer(player: AVPlayer?, item: AVPlayerItem, view: UIView?) {
        guard let player, let view else { return }
        let layer = view.layer as? AVPlayerLayer
        append("item status/error: \(item.status.rawValue)/\(item.error?.localizedDescription ?? "nil")")
        append("player status/error: \(player.status.rawValue)/\(player.error?.localizedDescription ?? "nil")")
        append("player timeControl/wait: \(player.timeControlStatus.rawValue)/\(player.reasonForWaitingToPlay.map(String.init(describing:)) ?? "nil")")
        append("player currentItem/layer player same: \(player.currentItem != nil)/\(layer?.player === player)")
        append("PlayerView bounds/frame: \(String(describing: view.bounds))/\(String(describing: view.frame))")
        append("AVPlayerLayer bounds/frame/gravity: \(layer.map { String(describing: $0.bounds) } ?? "nil")/\(layer.map { String(describing: $0.frame) } ?? "nil")/\(layer?.videoGravity.rawValue ?? "nil")")
    }

    private func appendFile(_ label: String, url: URL?) {
        let manager = FileManager.default
        guard let url else { append("\(label): URL nil"); return }
        let exists = manager.fileExists(atPath: url.path)
        let readable = manager.isReadableFile(atPath: url.path)
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        append("\(label): \(url.path)")
        append("\(label) exists/readable/size: \(exists)/\(readable)/\(size.map(String.init) ?? "nil")")
    }

    private func inspectAsset(label: String, url: URL) {
        Task { [weak self] in
            let asset = AVURLAsset(url: url)
            do {
                let playable = try await asset.load(.isPlayable)
                let protected = try await asset.load(.hasProtectedContent)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                self?.append("\(label) asset playable/protected/duration/videoTracks: \(playable)/\(protected)/\(duration.seconds)/\(tracks.count)")
            } catch {
                self?.append("\(label) asset error: \(error.localizedDescription)")
            }
        }
    }

    private func append(_ line: String) {
        let lines = (text == "Waiting for Native Avatar diagnostics…" ? [] : text.components(separatedBy: "\n")) + [line]
        text = lines.suffix(160).joined(separator: "\n")
        debugPrint("[NativeAvatarDiagnostics] \(line)")
    }
}

private struct NativeAvatarDiagnosticsOverlay: View {
    @ObservedObject var diagnostics = NativeAvatarDiagnostics.shared
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Native Avatar DEBUG diagnostics").font(.caption.bold())
                Spacer()
                Button("Copy") { UIPasteboard.general.string = diagnostics.text }
                Button("Close", action: close)
            }
            ScrollView {
                Text(diagnostics.text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
#endif

private struct NativeAvatarPlayer: UIViewRepresentable {
    let url: URL?
    let looping: Bool
    let onFinished: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }
    func makeUIView(context: Context) -> PlayerView { context.coordinator.view }
    func updateUIView(_ view: PlayerView, context: Context) { context.coordinator.update(url: url, looping: looping, onFinished: onFinished) }
    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) { coordinator.stop() }
    final class PlayerView: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } }
    final class Coordinator {
        let view = PlayerView(); let player = AVPlayer(); var token: NSObjectProtocol?; var backgroundToken: NSObjectProtocol?; var foregroundToken: NSObjectProtocol?; var current: URL?; var looping = true; var onFinished: () -> Void
        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished; view.playerLayer.player = player; view.playerLayer.videoGravity = .resizeAspectFill
            backgroundToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.player.pause() }
            foregroundToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.player.play() }
        }
        func update(url: URL?, looping: Bool, onFinished: @escaping () -> Void) {
            self.looping = looping; self.onFinished = onFinished
            guard current != url else { return }
            if let token { NotificationCenter.default.removeObserver(token) }
            current = url
            guard let url else { player.replaceCurrentItem(with: nil); return }
            let item = AVPlayerItem(url: url); player.replaceCurrentItem(with: item)
#if DEBUG
            Task { @MainActor in NativeAvatarDiagnostics.shared.observe(player: player, item: item, view: view) }
#endif
            token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.looping { self.player.seek(to: .zero); self.player.play() } else { self.onFinished() }
            }
            player.isMuted = true; player.play()
        }
        func stop() { player.pause(); if let token { NotificationCenter.default.removeObserver(token) }; if let backgroundToken { NotificationCenter.default.removeObserver(backgroundToken) }; if let foregroundToken { NotificationCenter.default.removeObserver(foregroundToken) } }
        deinit { stop() }
    }
}

struct NativeAvatarView: View {
    let onClose: () -> Void
    let onSend: (String) -> Void
    let onMic: () -> Void
    @StateObject private var avatar = NativeAvatarState()
    @State private var outfit = "casual"
    @State private var input = ""
#if DEBUG
    @State private var showsDiagnostics = false
#endif
    private let outfits = ["casual", "office", "pajamas", "shorts"]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeAvatarPlayer(url: NativeAvatarAssetResolver.url(outfit: outfit, state: avatar.state), looping: NativeAvatarAssetResolver.loopStates.contains(avatar.state)) { avatar.state = "idle_01" }
                .ignoresSafeArea()
            VStack {
                HStack { Button(action: onClose) { Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }; Spacer()
#if DEBUG
                    Button("診斷") { showsDiagnostics.toggle() }.font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
#endif
                    Picker("Outfit", selection: $outfit) { ForEach(outfits, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu) }.padding()
                Spacer()
                if !avatar.subtitle.isEmpty || avatar.state == "thinking" { Text(avatar.subtitle.isEmpty ? "思考中…" : avatar.subtitle).multilineTextAlignment(.center).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal) }
                HStack { Button(action: onMic) { Image(systemName: "mic.fill") }; TextField("輸入訊息…", text: $input).submitLabel(.send).onSubmit(send); Button(action: send) { Image(systemName: "arrow.up.circle.fill") } }.padding().background(.ultraThinMaterial).clipShape(Capsule()).padding()
            }
#if DEBUG
            if showsDiagnostics { NativeAvatarDiagnosticsOverlay { showsDiagnostics = false } }
#endif
        }
#if DEBUG
        .onAppear { NativeAvatarDiagnostics.shared.captureRuntime(outfit: outfit, state: avatar.state) }
#endif
        .onDisappear { avatar.subtitle = "" }
    }
    private func send() { let text = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; input = ""; onSend(text) }
}
