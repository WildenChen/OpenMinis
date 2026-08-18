import XCTest
@testable import Minis

@MainActor
final class NativeAvatarTouchTests: XCTestCase {
    func testNormalizedHitAreasResolveDistinctRegions() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(NativeAvatarTouchRegion.hit(at: CGPoint(x: 50, y: 15), in: size), .head)
        XCTAssertEqual(NativeAvatarTouchRegion.hit(at: CGPoint(x: 50, y: 48), in: size), .upperBody)
        XCTAssertEqual(NativeAvatarTouchRegion.hit(at: CGPoint(x: 15, y: 48), in: size), .handArm)
        XCTAssertEqual(NativeAvatarTouchRegion.hit(at: CGPoint(x: 50, y: 85), in: size), .lowerBody)
    }

    func testReactionStateReturnsToCurrentPresentationState() {
        let state = NativeAvatarState()
        state.state = "thinking"
        state.emotion = .shy
        state.beginReaction(.head)
        XCTAssertEqual(state.reaction, .head)
        state.finishReaction()
        XCTAssertNil(state.reaction)
        XCTAssertEqual(state.state, "thinking")
        XCTAssertEqual(state.emotion, .shy)
    }
}
