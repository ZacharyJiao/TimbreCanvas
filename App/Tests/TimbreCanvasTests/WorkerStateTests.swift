import Testing
@testable import TimbreCanvas

@Test func readyResponseMovesAppToReady() {
    var store = WorkerStateStore()

    store.receive(.ready(requestID: "r1", engineID: "indextts2"))

    #expect(store.state == .ready)
    #expect(store.engineID == "indextts2")
}

@Test func generationTransitionsReturnToReady() {
    var store = WorkerStateStore(state: .ready)

    store.beginGeneration()
    #expect(store.state == .generating)

    store.receive(.result(.init(requestID: "r2", outputPath: "/tmp/result.wav")))
    #expect(store.state == .ready)
}

@Test func consecutiveUnexpectedExitsOnlyAutomaticallyRecoverOnce() {
    var store = WorkerStateStore(state: .ready)

    #expect(store.handleUnexpectedExit() == .restart)
    #expect(store.state == .recovering)

    #expect(store.handleUnexpectedExit() == .stop)
    #expect(store.state == .unavailable)
}

@Test func readyWithoutSuccessfulWorkDoesNotResetAutomaticRecoveryBudget() {
    var store = WorkerStateStore(state: .ready)

    #expect(store.handleUnexpectedExit() == .restart)
    store.receive(.ready(requestID: "recovered", engineID: "indextts2"))

    #expect(store.handleUnexpectedExit() == .stop)
    #expect(store.state == .unavailable)
}

@Test func successfulGenerationResetsAutomaticRecoveryBudget() {
    var store = WorkerStateStore(state: .ready)

    #expect(store.handleUnexpectedExit() == .restart)
    store.receive(.ready(requestID: "recovered", engineID: "indextts2"))
    store.beginGeneration()
    store.receive(.result(.init(requestID: "generated", outputPath: "/tmp/result.wav")))

    #expect(store.handleUnexpectedExit() == .restart)
    #expect(store.state == .recovering)
}
