import XCTest

@MainActor
final class NativeAvatarPresentationTests: XCTestCase {
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
            ["thinking"]
        )
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

        XCTAssertEqual(SoulNestAvatarPresentation.agentPresentation(emotion: "shy", outfit: "removed-outfit"), "Avatar presentation updated.")
        wait(for: [expectation], timeout: 1)
    }
}
