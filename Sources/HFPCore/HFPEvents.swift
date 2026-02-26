// Copyright 2026 ICOA Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Shared

public enum HFPEvent: Sendable {
    // Connection events
    case connected
    case disconnected(Error?)
    case connectFailed(Error?)

    // Call state events
    case incomingCall(number: String?)
    case callAnswered
    case callEnded
    case callDialing(number: String)
    case callAlerting
    case callActive
    case callHeld
    case callWaiting(number: String?)

    // Audio events
    case scoConnected
    case scoDisconnected

    // Indicator events
    case signalStrength(Int)
    case batteryLevel(Int)
    case serviceAvailable(Bool)
    case roaming(Bool)
    case callSetup(Int)       // 0=none, 1=incoming, 2=outgoing dialing, 3=outgoing alerting
    case callIndicator(Bool)  // true=call active, false=no active call
    case callHeldIndicator(Int) // 0=none held, 1=held+active, 2=held only

    // Caller ID
    case callerID(number: String, name: String?)

    // Operator
    case operatorName(String)

    // Caller speech (transcription from STT)
    case callerSpeech(String)

    // Error
    case error(String)
}

public final class HFPEventStream: @unchecked Sendable {
    private var continuations: [UUID: AsyncStream<HFPEvent>.Continuation] = [:]
    private let lock = NSLock()

    public init() {}

    public func makeStream() -> AsyncStream<HFPEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()

            continuation.onTermination = { _ in
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    public func emit(_ event: HFPEvent) {
        lock.lock()
        let allContinuations = continuations.values
        lock.unlock()

        for continuation in allContinuations {
            continuation.yield(event)
        }
    }
}