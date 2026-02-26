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

public enum ConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
}

public enum AudioState: String, Codable, Sendable {
    case disconnected
    case connected
}

public struct HFPState: Sendable {
    public var connection: ConnectionState
    public var call: CallStatus
    public var audio: AudioState
    public var phoneStatus: PhoneStatus
    public var activeCall: CallInfo?

    public init() {
        self.connection = .disconnected
        self.call = .idle
        self.audio = .disconnected
        self.phoneStatus = PhoneStatus()
        self.activeCall = nil
    }
}

public final class HFPStateMachine: @unchecked Sendable {
    private var state: HFPState
    private let lock = NSLock()
    private let logger = PhoneBTLogger(category: .hfp)

    public init() {
        self.state = HFPState()
    }

    public var currentState: HFPState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func handleEvent(_ event: HFPEvent) {
        lock.lock()
        defer { lock.unlock() }

        switch event {
        case .connected:
            state.connection = .connected
            logger.info("State: connected")

        case .disconnected:
            state.connection = .disconnected
            state.call = .idle
            state.audio = .disconnected
            state.activeCall = nil
            logger.info("State: disconnected")

        case .connectFailed:
            state.connection = .disconnected
            logger.info("State: connect failed")

        case .incomingCall(let number):
            state.call = .incoming
            state.activeCall = CallInfo(index: 1, direction: .incoming, status: .incoming, number: number)
            logger.info("State: incoming call from \(number ?? "unknown")")

        case .callAnswered:
            state.call = .active
            state.activeCall?.status = .active
            state.activeCall?.startTime = Date()
            logger.info("State: call answered")

        case .callEnded:
            state.call = .idle
            state.activeCall = nil
            logger.info("State: call ended")

        case .callDialing(let number):
            state.call = .dialing
            state.activeCall = CallInfo(index: 1, direction: .outgoing, status: .dialing, number: number)
            logger.info("State: dialing \(number)")

        case .callAlerting:
            state.call = .alerting
            state.activeCall?.status = .alerting
            logger.info("State: alerting (ringing remote)")

        case .callActive:
            state.call = .active
            state.activeCall?.status = .active
            if state.activeCall?.startTime == nil {
                state.activeCall?.startTime = Date()
            }
            logger.info("State: call active")

        case .callHeld:
            state.call = .held
            state.activeCall?.status = .held
            logger.info("State: call held")

        case .callWaiting(let number):
            logger.info("State: call waiting from \(number ?? "unknown")")

        case .scoConnected:
            state.audio = .connected
            logger.info("State: SCO audio connected")

        case .scoDisconnected:
            state.audio = .disconnected
            logger.info("State: SCO audio disconnected")

        case .signalStrength(let strength):
            state.phoneStatus.signalStrength = strength

        case .batteryLevel(let level):
            state.phoneStatus.batteryLevel = level

        case .serviceAvailable(let available):
            state.phoneStatus.serviceAvailable = available

        case .roaming(let isRoaming):
            state.phoneStatus.roaming = isRoaming

        case .callSetup(let setupState):
            switch setupState {
            case 0:
                // No call setup — if we were dialing/alerting, call either connected or failed
                if state.call == .dialing || state.call == .alerting {
                    // Will be resolved by callIndicator
                }
            case 1:
                state.call = .incoming
                if state.activeCall == nil {
                    state.activeCall = CallInfo(index: 1, direction: .incoming, status: .incoming)
                }
            case 2:
                state.call = .dialing
            case 3:
                state.call = .alerting
                state.activeCall?.status = .alerting
            default:
                break
            }

        case .callIndicator(let active):
            if active && state.call != .active {
                state.call = .active
                state.activeCall?.status = .active
                if state.activeCall?.startTime == nil {
                    state.activeCall?.startTime = Date()
                }
            } else if !active {
                state.call = .idle
                state.activeCall = nil
            }

        case .callHeldIndicator(let held):
            switch held {
            case 0:
                if state.call == .held {
                    state.call = .active
                    state.activeCall?.status = .active
                }
            case 1, 2:
                state.call = .held
                state.activeCall?.status = .held
            default:
                break
            }

        case .callerID(let number, _):
            state.activeCall?.number = number

        case .operatorName(let name):
            state.phoneStatus.operatorName = name

        case .error:
            break
        }
    }
}