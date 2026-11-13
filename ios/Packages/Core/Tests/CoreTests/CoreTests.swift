import Testing
@testable import Core

@Test func moduleLoads() {
    #expect(CoreModule.name == "Core")
}
