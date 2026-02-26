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

import XCTest
@testable import HFPCore
@testable import Shared

final class HFPStateMachineTests: XCTestCase {

    var stateMachine: HFPStateMachine!

    override func setUp() {
        super.setUp()
        stateMachine = HFPStateMachine()
    }

    // MARK: - Initial State

    func testInitialState() {
        let state = stateMachine.currentState
        XCTAssertEqual(state.connection, .disconnected)
        XCTAssertEqual(state.call, .idle)
        XCTAssertEqual(state.audio, .disconnected)
        XCTAssertNil(state.activeCall)
    }

    // MARK: - Connection

    func testConnected() {
        stateMachine.handleEvent(.connected)
        XCTAssertEqual(stateMachine.currentState.connection, .connected)
    }

    func testDisconnectedResetsAll() {
        stateMachine.handleEvent(.connected)
        stateMachine.handleEvent(.callActive)
        stateMachine.handleEvent(.scoConnected)

        stateMachine.handleEvent(.disconnected(nil))

        let state = stateMachine.currentState
        XCTAssertEqual(state.connection, .disconnected)
        XCTAssertEqual(state.call, .idle)
        XCTAssertEqual(state.audio, .disconnected)
        XCTAssertNil(state.activeCall)
    }

    func testConnectFailed() {
        stateMachine.handleEvent(.connectFailed(nil))
        XCTAssertEqual(stateMachine.currentState.connection, .disconnected)
    }

    // MARK: - Outgoing Call Flow

    func testOutgoingCallFlow() {
        stateMachine.handleEvent(.connected)

        // Dialing
        stateMachine.handleEvent(.callDialing(number: "+15551234567"))
        XCTAssertEqual(stateMachine.currentState.call, .dialing)
        XCTAssertEqual(stateMachine.currentState.activeCall?.number, "+15551234567")
        XCTAssertEqual(stateMachine.currentState.activeCall?.direction, .outgoing)

        // Alerting (ringing on remote end)
        stateMachine.handleEvent(.callAlerting)
        XCTAssertEqual(stateMachine.currentState.call, .alerting)

        // Call active
        stateMachine.handleEvent(.callActive)
        XCTAssertEqual(stateMachine.currentState.call, .active)
        XCTAssertNotNil(stateMachine.currentState.activeCall?.startTime)

        // Call ended
        stateMachine.handleEvent(.callEnded)
        XCTAssertEqual(stateMachine.currentState.call, .idle)
        XCTAssertNil(stateMachine.currentState.activeCall)
    }

    // MARK: - Incoming Call Flow

    func testIncomingCallFlow() {
        stateMachine.handleEvent(.connected)

        // Incoming call
        stateMachine.handleEvent(.incomingCall(number: "+15559876543"))
        XCTAssertEqual(stateMachine.currentState.call, .incoming)
        XCTAssertEqual(stateMachine.currentState.activeCall?.number, "+15559876543")
        XCTAssertEqual(stateMachine.currentState.activeCall?.direction, .incoming)

        // Answer
        stateMachine.handleEvent(.callAnswered)
        XCTAssertEqual(stateMachine.currentState.call, .active)
        XCTAssertNotNil(stateMachine.currentState.activeCall?.startTime)

        // End
        stateMachine.handleEvent(.callEnded)
        XCTAssertEqual(stateMachine.currentState.call, .idle)
    }

    // MARK: - Audio State

    func testAudioConnection() {
        stateMachine.handleEvent(.scoConnected)
        XCTAssertEqual(stateMachine.currentState.audio, .connected)

        stateMachine.handleEvent(.scoDisconnected)
        XCTAssertEqual(stateMachine.currentState.audio, .disconnected)
    }

    // MARK: - Phone Status Indicators

    func testPhoneStatusIndicators() {
        stateMachine.handleEvent(.signalStrength(4))
        XCTAssertEqual(stateMachine.currentState.phoneStatus.signalStrength, 4)

        stateMachine.handleEvent(.batteryLevel(3))
        XCTAssertEqual(stateMachine.currentState.phoneStatus.batteryLevel, 3)

        stateMachine.handleEvent(.serviceAvailable(true))
        XCTAssertTrue(stateMachine.currentState.phoneStatus.serviceAvailable)

        stateMachine.handleEvent(.roaming(true))
        XCTAssertTrue(stateMachine.currentState.phoneStatus.roaming)

        stateMachine.handleEvent(.operatorName("T-Mobile"))
        XCTAssertEqual(stateMachine.currentState.phoneStatus.operatorName, "T-Mobile")
    }

    // MARK: - Call Setup Indicator (HFP Standard)

    func testCallSetupIndicatorIncoming() {
        stateMachine.handleEvent(.callSetup(1)) // incoming setup
        XCTAssertEqual(stateMachine.currentState.call, .incoming)
        XCTAssertNotNil(stateMachine.currentState.activeCall)
    }

    func testCallSetupIndicatorOutgoingDialing() {
        stateMachine.handleEvent(.callSetup(2)) // outgoing dialing
        XCTAssertEqual(stateMachine.currentState.call, .dialing)
    }

    func testCallSetupIndicatorOutgoingAlerting() {
        stateMachine.handleEvent(.callSetup(3)) // outgoing alerting
        XCTAssertEqual(stateMachine.currentState.call, .alerting)
    }

    // MARK: - Call Indicator

    func testCallIndicatorActivatesCall() {
        stateMachine.handleEvent(.callIndicator(true))
        XCTAssertEqual(stateMachine.currentState.call, .active)
    }

    func testCallIndicatorDeactivatesCall() {
        stateMachine.handleEvent(.callActive)
        stateMachine.handleEvent(.callIndicator(false))
        XCTAssertEqual(stateMachine.currentState.call, .idle)
        XCTAssertNil(stateMachine.currentState.activeCall)
    }

    // MARK: - Call Held Indicator

    func testCallHeldIndicator() {
        stateMachine.handleEvent(.callActive)
        stateMachine.handleEvent(.callHeldIndicator(1))
        XCTAssertEqual(stateMachine.currentState.call, .held)

        stateMachine.handleEvent(.callHeldIndicator(0))
        XCTAssertEqual(stateMachine.currentState.call, .active)
    }

    // MARK: - Caller ID

    func testCallerIDUpdatesActiveCall() {
        stateMachine.handleEvent(.incomingCall(number: nil))
        XCTAssertNil(stateMachine.currentState.activeCall?.number)

        stateMachine.handleEvent(.callerID(number: "+15551111111", name: "John"))
        XCTAssertEqual(stateMachine.currentState.activeCall?.number, "+15551111111")
    }
}