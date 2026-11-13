import Testing
@testable import Blocking

@Test func moduleLoads() {
    #expect(BlockingModule.name == "Blocking")
}
