import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let soulNestAvatarPresentation = Notification.Name("soulnest.avatar.presentation")
}

enum NativeAvatarOutfit: String, CaseIterable, Identifiable {
    case casual, office
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .casual: return String(localized: "Avatar Outfit Casual")
        case .office: return String(localized: "Avatar Outfit Office")
        }
    }
}

enum NativeAvatarEmotion: String, CaseIterable {
    case neutral
    case alternateIdle = "idle_02"
    case thinking
    case talking = "talk_soft"
    case happy
    case excited
    case shy
    case angry
    case sad
    case caring

    var mediaStates: [String] {
        switch self {
        case .neutral: return ["neutral", "idle_01"]
        case .happy: return ["happy", "talk_happy"]
        case .excited: return ["excited", "talk_excited"]
        default: return [rawValue]
        }
    }

    var displayName: String {
        switch self {
        case .neutral: return String(localized: "Avatar Emotion Neutral")
        case .alternateIdle: return String(localized: "Avatar State Idle 2")
        case .thinking: return String(localized: "Avatar State Thinking")
        case .talking: return String(localized: "Avatar State Talk Soft")
        case .happy: return String(localized: "Avatar Emotion Happy")
        case .excited: return String(localized: "Avatar State Talk Excited")
        case .shy: return String(localized: "Avatar State Shy")
        case .angry: return String(localized: "Avatar State Angry")
        case .sad: return String(localized: "Avatar State Sad")
        case .caring: return String(localized: "Avatar State Caring")
        }
    }
}

enum NativeAvatarTouchRegion: String, CaseIterable {
    case head, upperBody, handArm, lowerBody

    var mediaState: String { "reaction_\(rawValue)" }

    var displayName: String {
        switch self {
        case .head: return String(localized: "Avatar Touch Head")
        case .upperBody: return String(localized: "Avatar Touch Upper Body")
        case .handArm: return String(localized: "Avatar Touch Hand Arm")
        case .lowerBody: return String(localized: "Avatar Touch Lower Body")
        }
    }

    static let normalizedAreas: [(region: Self, rect: CGRect)] = [
        (.head, CGRect(x: 0.28, y: 0.06, width: 0.44, height: 0.27)),
        (.handArm, CGRect(x: 0.05, y: 0.31, width: 0.22, height: 0.38)),
        (.handArm, CGRect(x: 0.73, y: 0.31, width: 0.22, height: 0.38)),
        (.upperBody, CGRect(x: 0.28, y: 0.33, width: 0.44, height: 0.35)),
        (.lowerBody, CGRect(x: 0.22, y: 0.68, width: 0.56, height: 0.32)),
    ]

    static func hit(at point: CGPoint, in size: CGSize) -> Self? {
        guard size.width > 0, size.height > 0 else { return nil }
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        return normalizedAreas.first(where: { $0.rect.contains(normalized) })?.region
    }
}

@MainActor
final class NativeAvatarPreferences: ObservableObject {
    static let shared = NativeAvatarPreferences()
    static let autoOpenKey = "avatar.autoOpenConversation"
    private static let defaultOutfitKey = "avatar.defaultOutfit"
    private static let enabledOutfitsKey = "avatar.enabledOutfits"
    private static let customOutfitsKey = "avatar.customOutfits"
    private static let customOutfitNamesKey = "avatar.customOutfitNames"
    private static let mappingsKey = "avatar.videoMappings"
    private static let mappingMetadataKey = "avatar.videoMappingMetadata"

    @Published var autoOpen: Bool { didSet { UserDefaults.standard.set(autoOpen, forKey: Self.autoOpenKey) } }
    @Published var defaultOutfit: String { didSet { UserDefaults.standard.set(defaultOutfit, forKey: Self.defaultOutfitKey) } }
    @Published private(set) var enabledOutfits: Set<String> { didSet { UserDefaults.standard.set(Array(enabledOutfits), forKey: Self.enabledOutfitsKey) } }
    @Published private(set) var customOutfits: [String] { didSet { UserDefaults.standard.set(customOutfits, forKey: Self.customOutfitsKey) } }
    @Published private(set) var customOutfitNames: [String: String] { didSet { UserDefaults.standard.set(customOutfitNames, forKey: Self.customOutfitNamesKey) } }
    @Published private(set) var videoMappings: [String: String] { didSet { UserDefaults.standard.set(videoMappings, forKey: Self.mappingsKey) } }
    @Published private(set) var videoMappingMetadata: [String: [String: String]] { didSet { UserDefaults.standard.set(videoMappingMetadata, forKey: Self.mappingMetadataKey) } }

    private init() {
        let defaults = UserDefaults.standard
        autoOpen = defaults.object(forKey: Self.autoOpenKey) as? Bool ?? true
        defaultOutfit = defaults.string(forKey: Self.defaultOutfitKey) ?? NativeAvatarOutfit.casual.rawValue
        enabledOutfits = Set(defaults.stringArray(forKey: Self.enabledOutfitsKey) ?? NativeAvatarOutfit.allCases.map(\.rawValue))
        customOutfits = defaults.stringArray(forKey: Self.customOutfitsKey) ?? []
        customOutfitNames = defaults.dictionary(forKey: Self.customOutfitNamesKey) as? [String: String] ?? [:]
        videoMappings = defaults.dictionary(forKey: Self.mappingsKey) as? [String: String] ?? [:]
        videoMappingMetadata = defaults.dictionary(forKey: Self.mappingMetadataKey) as? [String: [String: String]] ?? [:]
        enabledOutfits.insert(NativeAvatarOutfit.casual.rawValue)
        if !outfits.contains(defaultOutfit) || !isEnabled(defaultOutfit) {
            defaultOutfit = NativeAvatarOutfit.casual.rawValue
        }
    }

    var outfits: [String] { NativeAvatarOutfit.allCases.map(\.rawValue) + customOutfits }
    var resolvedDefaultOutfit: String {
        outfits.contains(defaultOutfit) && isEnabled(defaultOutfit) ? defaultOutfit : NativeAvatarOutfit.casual.rawValue
    }
    func resolvedOutfit(_ requested: String?) -> String {
        guard let requested, outfits.contains(requested), isEnabled(requested) else { return resolvedDefaultOutfit }
        return requested
    }
    func isBuiltIn(_ outfit: String) -> Bool { NativeAvatarOutfit(rawValue: outfit) != nil }
    func displayName(for outfit: String) -> String { NativeAvatarOutfit(rawValue: outfit)?.displayName ?? customOutfitNames[outfit] ?? outfit }
    func stateDisplayName(for state: String) -> String {
        if let emotion = NativeAvatarEmotion(rawValue: state) { return emotion.displayName }
        switch state {
        case "idle_01": return String(localized: "Avatar State Idle 1")
        case "idle_02": return String(localized: "Avatar State Idle 2")
        case "thinking": return String(localized: "Avatar State Thinking")
        case "talk_soft": return String(localized: "Avatar State Talk Soft")
        case "talk_happy": return String(localized: "Avatar State Talk Happy")
        case "talk_excited": return String(localized: "Avatar State Talk Excited")
        case "shy": return String(localized: "Avatar State Shy")
        case "sad": return String(localized: "Avatar State Sad")
        case "angry": return String(localized: "Avatar State Angry")
        case "caring": return String(localized: "Avatar State Caring")
        case "reaction_head": return NativeAvatarTouchRegion.head.displayName
        case "reaction_upperBody": return NativeAvatarTouchRegion.upperBody.displayName
        case "reaction_handArm": return NativeAvatarTouchRegion.handArm.displayName
        case "reaction_lowerBody": return NativeAvatarTouchRegion.lowerBody.displayName
        default: return state
        }
    }
    func isEnabled(_ outfit: String) -> Bool { enabledOutfits.contains(outfit) }
    func setEnabled(_ enabled: Bool, outfit: String) {
        guard outfit != NativeAvatarOutfit.casual.rawValue || enabled else { return }
        if enabled { enabledOutfits.insert(outfit) } else { enabledOutfits.remove(outfit) }
        if !enabled, defaultOutfit == outfit { defaultOutfit = NativeAvatarOutfit.casual.rawValue }
    }
    func addCustomOutfit(named name: String) -> String? {
        let id = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        guard !id.isEmpty, !outfits.contains(id) else { return nil }
        customOutfits.append(id)
        customOutfitNames[id] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        enabledOutfits.insert(id)
        return id
    }
    func mappingURL(outfit: String, state: String) -> URL? {
        guard let path = videoMappings["\(outfit)/\(state)"] else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) && FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }
    func mappingOriginalFilename(outfit: String, state: String) -> String? {
        mappingStates(for: state).lazy.compactMap { candidate -> String? in
            let key = "\(outfit)/\(candidate)"
            if let filename = self.videoMappingMetadata[key]?["originalFilename"], !filename.isEmpty { return filename }
            return self.videoMappings[key].map { URL(fileURLWithPath: $0).lastPathComponent }
        }.first
    }
    func hasVideoOverride(outfit: String, state: String) -> Bool {
        mappingStates(for: state).contains { videoMappings["\(outfit)/\($0)"] != nil }
    }

    enum VideoImportError: LocalizedError {
        case unsupportedFormat
        case iCloudFileNotDownloaded
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return String(localized: "Avatar Video Import Unsupported Format")
            case .iCloudFileNotDownloaded:
                return String(localized: "Avatar Video Import iCloud Not Downloaded")
            case .unavailable:
                return String(localized: "Avatar Video Import Unavailable")
            }
        }
    }

    static func supportsVideo(at url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    func importVideo(from source: URL, outfit: String, state: String, originalFilename: String? = nil) async throws {
        guard Self.supportsVideo(at: source) else { throw VideoImportError.unsupportedFormat }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let resourceValues = try source.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if resourceValues.isUbiquitousItem == true,
           resourceValues.ubiquitousItemDownloadingStatus != .current {
            throw VideoImportError.iCloudFileNotDownloaded
        }

        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SoulNest/AvatarAssets/custom/\(outfit)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased()
        let destination = base.appendingPathComponent("\(state).\(ext)")
        let staged = base.appendingPathComponent(".\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: staged) }

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: staged)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard FileManager.default.isReadableFile(atPath: staged.path) else { throw VideoImportError.unavailable }

        let asset = AVURLAsset(url: staged)
        guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: staged, to: destination)
        guard FileManager.default.isReadableFile(atPath: destination.path) else { throw CocoaError(.fileReadNoPermission) }
        let key = "\(outfit)/\(state)"
        videoMappings[key] = destination.path
        videoMappingMetadata[key] = ["originalFilename": originalFilename ?? source.lastPathComponent]
    }
    func removeVideoOverride(outfit: String, state: String) {
        mappingStates(for: state).forEach { removeVideoOverride(forKey: "\(outfit)/\($0)") }
    }
    func removeOutfitOverrides(outfit: String) {
        videoMappings.keys.filter { $0.hasPrefix("\(outfit)/") }.forEach(removeVideoOverride(forKey:))
    }
    func deleteCustomOutfit(_ outfit: String) {
        guard customOutfits.contains(outfit) else { return }
        removeOutfitOverrides(outfit: outfit)
        customOutfits.removeAll { $0 == outfit }
        customOutfitNames[outfit] = nil
        enabledOutfits.remove(outfit)
        if defaultOutfit == outfit { defaultOutfit = NativeAvatarOutfit.casual.rawValue }
    }
    private func removeVideoOverride(forKey key: String) {
        guard let path = videoMappings.removeValue(forKey: key) else {
            videoMappingMetadata[key] = nil
            return
        }
        videoMappingMetadata[key] = nil
        let url = URL(fileURLWithPath: path)
        guard isManagedCustomAsset(url), !videoMappings.values.contains(path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
    private func isManagedCustomAsset(_ url: URL) -> Bool {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return false }
        let customRoot = support.appendingPathComponent("SoulNest/AvatarAssets/custom", isDirectory: true).standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(customRoot)
    }
    private func mappingStates(for state: String) -> [String] {
        NativeAvatarEmotion(rawValue: state)?.mediaStates ?? [state]
    }
}

@MainActor
enum SoulNestAvatarPresentation {
    private static let textOnlyIdleDelay: TimeInterval = 1.5
    private static var pendingTextOnlyIdle: DispatchWorkItem?
    private static var activeOutfit: String?

    static func thinking() {
        cancelPendingTextOnlyIdle()
        post(action: "clearSubtitle", value: nil)
        post(action: "state", value: "thinking")
    }
    static func talking(subtitle: String? = nil) {
        cancelPendingTextOnlyIdle()
        post(action: "state", value: "talk_soft")
        if let subtitle, !subtitle.isEmpty {
            post(action: "subtitle", value: NativeAvatarSubtitle.displayText(subtitle))
        }
    }
    static func responseCompleted(_ text: String, hasTTSPlayback: Bool) {
        cancelPendingTextOnlyIdle()
        guard !text.isEmpty else { idle(); return }
        post(action: "say", value: NativeAvatarSubtitle.displayText(text))
        guard !hasTTSPlayback else { return }
        let work = DispatchWorkItem {
            pendingTextOnlyIdle = nil
            idle(clearSubtitle: false)
        }
        pendingTextOnlyIdle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + textOnlyIdleDelay, execute: work)
    }
    static func idle(clearSubtitle: Bool = true) {
        cancelPendingTextOnlyIdle()
        post(action: "state", value: "idle_01")
        if clearSubtitle { post(action: "clearSubtitle", value: nil) }
    }
    static func setActiveOutfit(_ outfit: String) {
        activeOutfit = NativeAvatarPreferences.shared.resolvedOutfit(outfit)
    }
    static func agentPresentation(
        emotion: String?,
        outfit: String?,
        mediaAvailable: ((String, NativeAvatarEmotion) -> Bool)? = nil
    ) -> String {
        guard emotion == nil || NativeAvatarEmotion(rawValue: emotion ?? "") != nil else {
            return "Ignored unsupported Avatar emotion."
        }
        let resolvedOutfit = NativeAvatarPreferences.shared.resolvedOutfit(outfit ?? activeOutfit)
        if let emotion, let parsed = NativeAvatarEmotion(rawValue: emotion) {
            let isAvailable = mediaAvailable?(resolvedOutfit, parsed)
                ?? NativeAvatarAssetResolver.hasExplicitMedia(outfit: resolvedOutfit, emotion: parsed)
            guard isAvailable else {
                post(action: "notice", value: String(localized: "Avatar presentation unavailable"))
                return "Ignored unavailable Avatar presentation."
            }
        }
        var info: [String: Any] = ["action": "agentPresentation", "outfit": resolvedOutfit]
        if let emotion { info["emotion"] = emotion }
        activeOutfit = resolvedOutfit
        NotificationCenter.default.post(name: .soulNestAvatarPresentation, object: nil, userInfo: info)
        return "Avatar presentation updated."
    }
    private static func cancelPendingTextOnlyIdle() {
        pendingTextOnlyIdle?.cancel()
        pendingTextOnlyIdle = nil
    }
    private static func post(action: String, value: String?) {
        var info: [String: Any] = ["action": action]
        if let value { info["value"] = value }
        NotificationCenter.default.post(name: .soulNestAvatarPresentation, object: nil, userInfo: info)
    }
}

enum NativeAvatarSubtitle {
    static let characterLimit = 800

    static func displayText(_ text: String) -> String {
        guard text.count > characterLimit else { return text }
        return String(text.suffix(characterLimit))
    }
}

enum NativeAvatarVoiceState: Equatable {
    case idle
    case starting
    case listening
    case processing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        case .starting, .listening, .processing, .failed: return true
        }
    }
}

enum NativeAvatarComposer {
    static func submit(_ rawText: String, using sender: (String) -> Bool) -> (accepted: Bool, remainingText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (false, rawText) }
        return sender(text) ? (true, "") : (false, rawText)
    }
}

@MainActor
final class NativeAvatarState: ObservableObject {
    @Published var state = "idle_01"
    @Published var subtitle = ""
    @Published var emotion: NativeAvatarEmotion = .neutral
    @Published var requestedOutfit: String?
    @Published var reaction: NativeAvatarTouchRegion?
    @Published var notice = ""

    func beginReaction(_ region: NativeAvatarTouchRegion) { reaction = region }
    func finishReaction() { reaction = nil }
    private var observer: NSObjectProtocol?
    private var noticeTask: Task<Void, Never>?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .soulNestAvatarPresentation, object: nil, queue: .main) { [weak self] note in
            guard let self, let action = note.userInfo?["action"] as? String else { return }
            let value = note.userInfo?["value"] as? String ?? ""
            switch action {
            case "state": self.state = value
            case "subtitle": self.subtitle = value
            case "say": self.state = "talk_soft"; self.subtitle = value
            case "clearSubtitle": self.subtitle = ""
            case "notice":
                self.notice = value
                self.noticeTask?.cancel()
                self.noticeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.notice = ""
                }
            case "agentPresentation":
                if let emotion = note.userInfo?["emotion"] as? String,
                   let parsed = NativeAvatarEmotion(rawValue: emotion) {
                    self.emotion = parsed
                }
                self.requestedOutfit = note.userInfo?["outfit"] as? String
            default: break
            }
        }
    }
    deinit {
        noticeTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor
struct NativeAvatarAssetResolver {
    static let states: Set<String> = ["idle_01", "idle_02", "thinking", "talk_soft", "talk_happy", "talk_excited", "shy", "sad", "angry", "caring"]
    static let loopStates: Set<String> = ["idle_01", "idle_02", "thinking", "talk_soft", "talk_happy", "talk_excited"]

    static func avatarRoot(resourceURL: URL? = Bundle.main.resourceURL, fileManager: FileManager = .default) -> URL? {
        guard let resourceURL else { return nil }
        let root = resourceURL.appendingPathComponent("Avatar", isDirectory: true)
        guard fileManager.fileExists(atPath: root.path), fileManager.isReadableFile(atPath: root.path) else { return nil }
        return root
    }

    static func emotionFallbackStates(_ emotion: NativeAvatarEmotion) -> [String] {
        emotion == .neutral ? emotion.mediaStates : emotion.mediaStates + NativeAvatarEmotion.neutral.mediaStates
    }

    static func presentationOverrideStates(state: String, emotion: NativeAvatarEmotion) -> [String] {
        let requested = state == "idle_01" || state == "idle_02"
            ? emotion.mediaStates
            : (NativeAvatarEmotion(rawValue: state)?.mediaStates ?? [state])
        return orderedUnique(requested + NativeAvatarEmotion.neutral.mediaStates)
    }

    static func hasExplicitMedia(
        outfit: String,
        emotion: NativeAvatarEmotion,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default,
        mappingURL: ((String, String) -> URL?)? = nil
    ) -> Bool {
        resolve(
            outfit: outfit,
            candidates: emotion.mediaStates,
            resourceURL: resourceURL,
            fileManager: fileManager,
            mappingURL: mappingURL
        ) != nil
    }

    static func url(
        outfit: String,
        state: String,
        emotion: NativeAvatarEmotion = .neutral,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default,
        mappingURL: ((String, String) -> URL?)? = nil
    ) -> URL? {
        if let currentOutfitURL = resolve(
            outfit: outfit,
            candidates: presentationOverrideStates(state: state, emotion: emotion),
            resourceURL: resourceURL,
            fileManager: fileManager,
            mappingURL: mappingURL
        ) {
            return currentOutfitURL
        }

        let globalOutfit = NativeAvatarOutfit.casual.rawValue
        guard outfit != globalOutfit else { return nil }
        return resolve(
            outfit: globalOutfit,
            candidates: NativeAvatarEmotion.neutral.mediaStates,
            resourceURL: resourceURL,
            fileManager: fileManager,
            mappingURL: mappingURL
        )
    }

    private static func resolve(
        outfit: String,
        candidates: [String],
        resourceURL: URL?,
        fileManager: FileManager,
        mappingURL: ((String, String) -> URL?)?
    ) -> URL? {
        let root = avatarRoot(resourceURL: resourceURL, fileManager: fileManager)
        func file(_ outfit: String, _ state: String) -> URL? {
            guard let root else { return nil }
            let url = root.appendingPathComponent("assets/videos/yujie-v1/\(outfit)/\(state).mp4")
            return fileManager.fileExists(atPath: url.path) && fileManager.isReadableFile(atPath: url.path) ? url : nil
        }
        for candidate in orderedUnique(candidates) {
            let custom: URL?
            if let mappingURL {
                custom = mappingURL(outfit, candidate)
            } else {
                custom = NativeAvatarPreferences.shared.mappingURL(outfit: outfit, state: candidate)
            }
            if let custom {
                return custom
            }
            if let bundled = file(outfit, candidate) { return bundled }
        }
        return nil
    }

    private static func orderedUnique(_ states: [String]) -> [String] {
        var seen = Set<String>()
        return states.filter { seen.insert($0).inserted }
    }

    static func reactionURL(outfit: String, region: NativeAvatarTouchRegion) -> URL? {
        NativeAvatarPreferences.shared.mappingURL(outfit: outfit, state: region.mediaState)
            ?? NativeAvatarPreferences.shared.mappingURL(outfit: NativeAvatarOutfit.casual.rawValue, state: region.mediaState)
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
                    .contentShape(Rectangle())
                Button("Close", action: close)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .contentShape(Rectangle())
            .zIndex(1)
            ScrollView {
                Text(diagnostics.text)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .contentShape(Rectangle())
            .zIndex(0)
        }
        .allowsHitTesting(true)
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
#endif

struct NativeAvatarPlayer: UIViewRepresentable {
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
            guard let url else { return }
            guard current != url else { return }
            if let token { NotificationCenter.default.removeObserver(token) }
            current = url
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
    let onSend: (String) -> Bool
    let onMic: () -> Void
    let isReadOnly: Bool
    let isAgentBusy: Bool
    let voiceState: NativeAvatarVoiceState
    let errorMessage: String?
    let noticeMessage: String?
    let onDismissError: () -> Void
    let onDismissNotice: () -> Void
    @StateObject private var avatar = NativeAvatarState()
    @ObservedObject private var preferences = NativeAvatarPreferences.shared
    @State private var outfit = NativeAvatarOutfit.casual.rawValue
    @State private var input = ""
    @State private var localNotice = ""
    private let testEmotions = NativeAvatarEmotion.allCases
#if DEBUG
    @State private var showsDiagnostics = false
#endif
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                let reactionURL = avatar.reaction.flatMap { NativeAvatarAssetResolver.reactionURL(outfit: outfit, region: $0) }
                NativeAvatarPlayer(url: reactionURL ?? NativeAvatarAssetResolver.url(outfit: outfit, state: avatar.state, emotion: avatar.emotion), looping: reactionURL == nil && NativeAvatarAssetResolver.loopStates.contains(avatar.state)) {
                    if avatar.reaction != nil { avatar.finishReaction() } else { avatar.state = "idle_01" }
                }
                    .ignoresSafeArea()
                    .accessibilityLabel(Text("Avatar Settings"))
                    .accessibilityHint(Text("Avatar touch reaction hint"))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: Text(NativeAvatarTouchRegion.head.displayName)) { beginReaction(.head) }
                    .accessibilityAction(named: Text(NativeAvatarTouchRegion.upperBody.displayName)) { beginReaction(.upperBody) }
                    .accessibilityAction(named: Text(NativeAvatarTouchRegion.handArm.displayName)) { beginReaction(.handArm) }
                    .accessibilityAction(named: Text(NativeAvatarTouchRegion.lowerBody.displayName)) { beginReaction(.lowerBody) }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let region = NativeAvatarTouchRegion.hit(at: tap.location, in: proxy.size) else { return }
                        beginReaction(region)
                    })
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(Text("Close"))
                        Spacer()
#if DEBUG
                    Button("診斷") { showsDiagnostics.toggle() }.font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
#endif
                    Picker(String(localized: "Avatar Settings Outfit"), selection: $outfit) { ForEach(preferences.outfits.filter(preferences.isEnabled), id: \.self) { Text(preferences.displayName(for: $0)).tag($0) } }.pickerStyle(.menu) }
                    .padding(.horizontal)
                    // The NativeAvatarView itself now respects the host safe
                    // area. Adding proxy.safeAreaInsets.top here would apply
                    // the Dynamic Island inset a second time and push controls
                    // down over the Avatar's face.
                    .padding(.top, 8)
                    HStack {
                        Spacer()
                        Picker(String(localized: "Avatar Emotion"), selection: $avatar.emotion) {
                            ForEach(testEmotions, id: \.rawValue) { emotion in
                                Text(emotion.displayName).tag(emotion)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                    if let errorMessage, !errorMessage.isEmpty {
                        avatarBanner(errorMessage, isError: true, dismiss: onDismissError)
                    } else if let notice = visibleNotice, !notice.isEmpty {
                        avatarBanner(notice, isError: false, dismiss: dismissNotice)
                    }
                    Spacer()
                    if let voiceStatusText {
                        Label(voiceStatusText, systemImage: voiceState == .processing ? "waveform.badge.magnifyingglass" : "waveform")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    if !avatar.subtitle.isEmpty || avatar.state == "thinking" {
                        Text(avatar.subtitle.isEmpty ? String(localized: "Avatar State Thinking") : avatar.subtitle)
                            .lineLimit(5)
                            .truncationMode(.head)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                            .accessibilityLabel(Text(avatar.subtitle.isEmpty ? String(localized: "Avatar State Thinking") : avatar.subtitle))
                    }
                    composer
                }
#if DEBUG
                if showsDiagnostics { NativeAvatarDiagnosticsOverlay { showsDiagnostics = false }.zIndex(10).allowsHitTesting(true) }
#endif
            }
        }
#if DEBUG
        .onAppear { NativeAvatarDiagnostics.shared.captureRuntime(outfit: outfit, state: avatar.state) }
#endif
        .onAppear {
            outfit = preferences.resolvedDefaultOutfit
            SoulNestAvatarPresentation.setActiveOutfit(outfit)
        }
        .onChange(of: outfit) { SoulNestAvatarPresentation.setActiveOutfit($0) }
        .onChange(of: avatar.requestedOutfit) { requested in
            if let requested { outfit = preferences.resolvedOutfit(requested) }
        }
        .onDisappear { avatar.subtitle = "" }
    }

    private var visibleNotice: String? {
        if !avatar.notice.isEmpty { return avatar.notice }
        if let noticeMessage, !noticeMessage.isEmpty { return noticeMessage }
        return localNotice.isEmpty ? nil : localNotice
    }

    private var voiceStatusText: String? {
        switch voiceState {
        case .idle: return nil
        case .starting: return String(localized: "Avatar Voice Starting")
        case .listening: return String(localized: "Avatar Voice Listening")
        case .processing: return String(localized: "Avatar Voice Transcribing")
        case .failed(let message): return message
        }
    }

    private var composer: some View {
        HStack {
            Button(action: onMic) {
                Image(systemName: voiceState.isActive ? "stop.circle.fill" : "mic.fill")
            }
            .disabled(isReadOnly || (isAgentBusy && !voiceState.isActive))
            .accessibilityLabel(Text(microphoneAccessibilityLabel))

            TextField(String(localized: "Message"), text: $input)
                .submitLabel(.send)
                .onSubmit(send)
                .disabled(isReadOnly)

            Button(action: send) {
                Image(systemName: isAgentBusy ? "text.badge.plus" : "arrow.up.circle.fill")
            }
            .disabled(isReadOnly || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text(sendAccessibilityLabel))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding()
    }

    private func avatarBanner(_ message: String, isError: Bool, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
            Text(message)
                .font(.caption)
                .lineLimit(3)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(Text("Close"))
        }
        .foregroundStyle(isError ? Color.red : Color.primary)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func beginReaction(_ region: NativeAvatarTouchRegion) {
        guard NativeAvatarAssetResolver.reactionURL(outfit: outfit, region: region) != nil else {
            localNotice = String(localized: "Avatar Reaction Unavailable")
            return
        }
        avatar.beginReaction(region)
    }

    private func dismissNotice() {
        avatar.notice = ""
        localNotice = ""
        onDismissNotice()
    }

    private func send() {
        let result = NativeAvatarComposer.submit(input, using: onSend)
        input = result.remainingText
        if !result.accepted {
            localNotice = isReadOnly
                ? String(localized: "Read-only")
                : String(localized: "Avatar Message Not Sent")
        } else {
            localNotice = ""
        }
    }

    private var microphoneAccessibilityLabel: String {
        voiceState.isActive
            ? String(localized: "Avatar Stop Listening")
            : String(localized: "Avatar Start Listening")
    }

    private var sendAccessibilityLabel: String {
        isAgentBusy ? String(localized: "Avatar Queue Message") : String(localized: "Send")
    }
}
