import Testing
@testable import GBAEmulator

@MainActor
struct InputManagerTests {
    @Test func touchButtonsRemainAvailableAcrossControlActions() {
        let input = InputManager()
        input.pressTouchButton(.a)
        #expect(input.pollInput() == GBAButton.a.rawValue)
        #expect(input.activeButtons == .a)

        // Fast-forward changes emulator pacing, not input ownership.
        input.pressTouchButton(.right)
        #expect(input.pollInput() == GBAButton.a.union(.right).rawValue)
        input.releaseTouchButton(.a)
        #expect(input.pollInput() == GBAButton.right.rawValue)

        // Pausing releases any gesture that was interrupted by the pause overlay.
        input.releaseAllTouchButtons()
        #expect(input.pollInput() == 0)
        #expect(input.activeButtons == .none)

        // The same mounted overlay can immediately submit input after resume.
        input.pressTouchButton(.start)
        #expect(input.pollInput() == GBAButton.start.rawValue)
        #expect(input.activeButtons == .start)
        input.releaseTouchButton(.start)
        #expect(input.pollInput() == 0)
    }
}
