import XCTest

@MainActor
final class NativeAvatarPresentationTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeAvatarPresentationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("Avatar/assets/videos/yujie-v1", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
        fixtureRoot = nil
    }

    func testBuiltInOutfitsAreLimitedToCasualAndOffice() {
        XCTAssertEqual(NativeAvatarOutfit.allCases, [.casual, .office])
    }

    func testEmotionFallbackUsesOutfitNeutralThenGlobalNeutral() {
        XCTAssertEqual(NativeAvatarAssetResolver.emotionFallbackStates(.happy), ["happy", "talk_happy", "neutral", "idle_01"])
        XCTAssertEqual(NativeAvatarAssetResolver.emotionFallbackStates(.excited), ["excited", "talk_excited", "neutral", "idle_01"])
        XCTAssertEqual(NativeAvatarAssetResolver.emotionFallbackStates(.shy), ["shy", "neutral", "idle_01"])
        XCTAssertEqual(NativeAvatarAssetResolver.emotionFallbackStates(.neutral), ["neutral", "idle_01"])
    }

    func testIdlePresentationChecksSemanticEmotionOverrides() {
        XCTAssertEqual(
            NativeAvatarAssetResolver.presentationOverrideStates(state: "idle_01", emotion: .neutral),
            ["neutral", "idle_01"]
        )
        XCTAssertEqual(
            NativeAvatarAssetResolver.presentationOverrideStates(state: "idle_01", emotion: .happy),
            ["happy", "talk_happy", "neutral", "idle_01"]
        )
        XCTAssertEqual(
            NativeAvatarAssetResolver.presentationOverrideStates(state: "thinking", emotion: .neutral),
            ["thinking", "neutral", "idle_01"]
        )
    }

    func testMissingThinkingUsesCurrentOutfitNeutralBeforeIdle() throws {
        let neutral = try makeFile("custom/office/neutral.mp4")
        let idle = try makeBundledVideo(outfit: "office", state: "idle_01")

        XCTAssertEqual(
            resolvedURL(outfit: "office", state: "thinking", mappings: ["office/neutral": neutral]),
            neutral
        )
        XCTAssertNotEqual(neutral, idle)
    }

    func testConfiguredThinkingWinsOverCurrentOutfitIdle() throws {
        let thinking = try makeBundledVideo(outfit: "office", state: "thinking")
        _ = try makeBundledVideo(outfit: "office", state: "idle_01")

        XCTAssertEqual(resolvedURL(outfit: "office", state: "thinking"), thinking)
    }

    func testMissingTalkSoftUsesCurrentOutfitIdle() throws {
        let idle = try makeBundledVideo(outfit: "office", state: "idle_01")

        XCTAssertEqual(resolvedURL(outfit: "office", state: "talk_soft"), idle)
    }

    func testConfiguredTalkSoftWinsOverCurrentOutfitIdle() throws {
        let talking = try makeBundledVideo(outfit: "office", state: "talk_soft")
        _ = try makeBundledVideo(outfit: "office", state: "idle_01")

        XCTAssertEqual(resolvedURL(outfit: "office", state: "talk_soft"), talking)
    }

    func testMissingLifecycleMediaNeverSelectsPlaceholder() throws {
        let globalIdle = try makeBundledVideo(outfit: "casual", state: "idle_01")
        let placeholderThinking = try makeFile("Avatar/assets/videos/placeholder-thinking.mp4")
        let placeholderTalking = try makeFile("Avatar/assets/videos/placeholder-talking.mp4")

        let thinking = resolvedURL(outfit: "custom-outfit", state: "thinking")
        let talking = resolvedURL(outfit: "custom-outfit", state: "talk_soft")
        XCTAssertEqual(thinking, globalIdle)
        XCTAssertEqual(talking, globalIdle)
        XCTAssertNotEqual(thinking, placeholderThinking)
        XCTAssertNotEqual(talking, placeholderTalking)
    }

    func testAvatarPickerAndAgentShareAllPresentationStates() {
        XCTAssertEqual(
            NativeAvatarEmotion.allCases.map(\.rawValue),
            ["neutral", "idle_02", "thinking", "talk_soft", "happy", "excited", "shy", "angry", "sad", "caring"]
        )
    }

    func testMissingAgentOutfitFallsBackToConfiguredDefault() {
        XCTAssertEqual(
            NativeAvatarPreferences.shared.resolvedOutfit("removed-outfit"),
            NativeAvatarPreferences.shared.resolvedDefaultOutfit
        )
    }

    func testAgentPresentationMapsStructuredEmotionWithoutChatText() {
        let expectation = expectation(description: "presentation notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .soulNestAvatarPresentation, object: nil, queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?["action"] as? String, "agentPresentation")
            XCTAssertEqual(notification.userInfo?["emotion"] as? String, "shy")
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertEqual(
            SoulNestAvatarPresentation.agentPresentation(
                emotion: "shy",
                outfit: "removed-outfit",
                mediaAvailable: { _, _ in true }
            ),
            "Avatar presentation updated."
        )
        wait(for: [expectation], timeout: 1)
    }

    func testAgentPresentationIgnoresUnavailableMediaWithoutChangingAvatar() {
        let avatar = NativeAvatarState()
        let notification = expectation(description: "no presentation notification")
        notification.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .soulNestAvatarPresentation, object: nil, queue: .main
        ) { _ in notification.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = SoulNestAvatarPresentation.agentPresentation(
            emotion: "thinking",
            outfit: nil,
            mediaAvailable: { _, _ in false }
        )

        XCTAssertEqual(result, "Ignored unavailable Avatar presentation.")
        wait(for: [notification], timeout: 0.1)
        XCTAssertEqual(avatar.emotion, .neutral)
        XCTAssertNil(avatar.requestedOutfit)
    }

    func testPlayerKeepsCurrentItemWhenUpdatedWithNilURL() throws {
        let media = try makeFile("player/current.mp4")
        let coordinator = NativeAvatarPlayer.Coordinator(onFinished: {})
        coordinator.update(url: media, looping: true, onFinished: {})
        let currentItem = coordinator.player.currentItem

        coordinator.update(url: nil, looping: true, onFinished: {})

        XCTAssertNotNil(currentItem)
        XCTAssertTrue(coordinator.player.currentItem === currentItem)
        XCTAssertEqual(coordinator.current, media)
    }

    private func resolvedURL(
        outfit: String,
        state: String,
        emotion: NativeAvatarEmotion = .neutral,
        mappings: [String: URL] = [:]
    ) -> URL? {
        NativeAvatarAssetResolver.url(
            outfit: outfit,
            state: state,
            emotion: emotion,
            resourceURL: fixtureRoot,
            mappingURL: { mappings["\($0)/\($1)"] }
        )
    }

    private func makeBundledVideo(outfit: String, state: String) throws -> URL {
        try makeFile("Avatar/assets/videos/yujie-v1/\(outfit)/\(state).mp4")
    }

    private func makeFile(_ relativePath: String) throws -> URL {
        let url = fixtureRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0])))
        return url
    }
}
