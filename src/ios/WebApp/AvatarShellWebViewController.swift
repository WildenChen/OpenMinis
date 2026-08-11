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
    static func url(outfit: String, state: String) -> URL? {
        let root = Bundle.main.url(forResource: nil, withExtension: nil, subdirectory: "Avatar")
        func file(_ outfit: String, _ state: String) -> URL? {
            guard let root else { return nil }
            let url = root.appendingPathComponent("assets/videos/yujie-v1/\(outfit)/\(state).mp4")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let selectedOutfit = outfit == "shorts" ? "shorts_private_casual" : outfit
        if let url = file(selectedOutfit, state) ?? file(selectedOutfit, state.hasPrefix("talk_") ? "talk_soft" : "idle_01") ?? file("casual", state) { return url }
        let placeholder: String = switch state {
        case "idle_01", "idle_02": "idle"; case "thinking": "thinking"; case "talk_happy": "happy"; case "talk_excited": "excited"; case "shy": "shy"; case "sad": "sad"; case "angry": "angry"; case "caring": "talking"; default: "talking"
        }
        return root?.appendingPathComponent("assets/videos/placeholder-\(placeholder).mp4")
    }
}

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
    private let outfits = ["casual", "office", "pajamas", "shorts"]
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeAvatarPlayer(url: NativeAvatarAssetResolver.url(outfit: outfit, state: avatar.state), looping: NativeAvatarAssetResolver.loopStates.contains(avatar.state)) { avatar.state = "idle_01" }
                .ignoresSafeArea()
            VStack {
                HStack { Button(action: onClose) { Image(systemName: "xmark").font(.headline).padding(12).background(.ultraThinMaterial, in: Circle()) }; Spacer(); Picker("Outfit", selection: $outfit) { ForEach(outfits, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu) }.padding()
                Spacer()
                if !avatar.subtitle.isEmpty || avatar.state == "thinking" { Text(avatar.subtitle.isEmpty ? "思考中…" : avatar.subtitle).multilineTextAlignment(.center).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal) }
                HStack { Button(action: onMic) { Image(systemName: "mic.fill") }; TextField("輸入訊息…", text: $input).submitLabel(.send).onSubmit(send); Button(action: send) { Image(systemName: "arrow.up.circle.fill") } }.padding().background(.ultraThinMaterial).clipShape(Capsule()).padding()
            }
        }
        .onDisappear { avatar.subtitle = "" }
    }
    private func send() { let text = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; input = ""; onSend(text) }
}
