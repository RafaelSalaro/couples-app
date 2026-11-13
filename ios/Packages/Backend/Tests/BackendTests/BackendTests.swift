import Testing
@testable import Backend

@Test func moduleLoads() {
    #expect(BackendModule.name == "Backend")
}
