enum WorkerState: String, Equatable, Sendable {
    case starting
    case loadingModel
    case ready
    case generating
    case recovering
    case unavailable
}

enum RecoveryDecision: Equatable, Sendable {
    case restart
    case stop
}

struct WorkerStateStore: Equatable, Sendable {
    var state: WorkerState
    private(set) var engineID: String?
    private(set) var recoveryAttempts: Int

    init(state: WorkerState = .starting, engineID: String? = nil, recoveryAttempts: Int = 0) {
        self.state = state
        self.engineID = engineID
        self.recoveryAttempts = recoveryAttempts
    }

    mutating func receive(_ message: WorkerMessage) {
        switch message {
        case let .ready(_, engineID):
            self.engineID = engineID
            state = .ready
        case .result:
            if state == .generating {
                recoveryAttempts = 0
                state = .ready
            }
        case .progress:
            state = .generating
        case .error:
            if state == .loadingModel || state == .starting || state == .recovering {
                state = .unavailable
            } else {
                state = .ready
            }
        }
    }

    mutating func beginModelLoad() {
        state = .loadingModel
    }

    mutating func beginGeneration() {
        state = .generating
    }

    mutating func handleUnexpectedExit() -> RecoveryDecision {
        if recoveryAttempts == 0 {
            recoveryAttempts = 1
            state = .recovering
            return .restart
        }
        state = .unavailable
        return .stop
    }
}
