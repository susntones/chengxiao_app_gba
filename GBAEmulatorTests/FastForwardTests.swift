import Testing
@testable import GBAEmulator

struct FastForwardTests {
    @Test func supportsEveryMultiplierFromTwoThroughTen() {
        #expect(FastForwardSpeed.allCases.map { Int($0.rawValue) } == Array(2...10))
        #expect(FastForwardSpeed.x2.displayName == "2 倍")
        #expect(FastForwardSpeed.x10.displayName == "10 倍")
    }
}
