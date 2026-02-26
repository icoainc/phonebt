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
import IOBluetooth
import Shared

/// High-level wrapper around IOBluetoothHandsFreeDevice
public final class HFPDevice: @unchecked Sendable {
    private let device: IOBluetoothHandsFreeDevice
    private let hfpDelegate: HFPDelegate
    public let eventStream: HFPEventStream
    public let stateMachine: HFPStateMachine
    private let logger = PhoneBTLogger(category: .hfp)
    private var eventTask: Task<Void, Never>?

    public var deviceName: String {
        return device.device.name ?? "Unknown"
    }

    public var deviceAddress: String {
        return device.device.addressString ?? "??:??:??:??:??:??"
    }

    public var currentState: HFPState {
        return stateMachine.currentState
    }

    public init?(bluetoothDevice: IOBluetoothDevice) {
        let events = HFPEventStream()
        let delegate = HFPDelegate(eventStream: events)
        let sm = HFPStateMachine()

        self.eventStream = events
        self.hfpDelegate = delegate
        self.stateMachine = sm

        // Create HFP device with delegate
        guard let hfDevice = IOBluetoothHandsFreeDevice(
            device: bluetoothDevice,
            delegate: delegate
        ) else {
            return nil
        }
        self.device = hfDevice

        // Start event processing loop
        self.eventTask = Task { [weak self] in
            let stream = events.makeStream()
            for await event in stream {
                self?.stateMachine.handleEvent(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Connection

    public func connect(timeout: TimeInterval = 15) async throws {
        logger.info("Connecting to \(deviceName)...")

        // connect() initiates SLC (Service Level Connection) automatically
        device.connect()

        // Wait for connection event with timeout
        let stream = eventStream.makeStream()
        let deadline = Date().addingTimeInterval(timeout)

        // Use a task group to race the event stream against a timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in stream {
                    switch event {
                    case .connected:
                        self.logger.info("Connected to \(self.deviceName)")
                        return
                    case .disconnected(let error):
                        throw BluetoothError.connectionFailed(
                            error?.localizedDescription ?? "Connection rejected"
                        )
                    case .connectFailed(let error):
                        throw BluetoothError.connectionFailed(
                            error?.localizedDescription ?? "Connection failed"
                        )
                    default:
                        continue
                    }
                }
            }

            group.addTask {
                // Timeout task
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BluetoothError.connectionFailed(
                    "Connection timed out after \(Int(timeout))s"
                )
            }

            // Wait for whichever finishes first
            do {
                try await group.next()
            } catch {
                group.cancelAll()
                throw error
            }
            group.cancelAll()
        }
    }

    public func disconnect() {
        logger.info("Disconnecting from \(deviceName)")
        device.disconnect()
    }

    // MARK: - Call Management

    public func dial(number: String) throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.info("Dialing \(number)")
        eventStream.emit(.callDialing(number: number))
        device.dialNumber(number)
    }

    public func acceptCall() throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.info("Accepting call")
        device.acceptCall()
    }

    public func endCall() throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.info("Ending call")
        device.endCall()
    }

    public func sendDTMF(_ digit: String) throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        guard digit.count == 1 else {
            throw BluetoothError.commandFailed("DTMF must be a single character")
        }
        logger.info("Sending DTMF: \(digit)")
        device.sendDTMF(digit)
    }

    // MARK: - Audio

    public func connectAudio() throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.info("Connecting SCO audio")
        device.connectSCO()
    }

    public func disconnectAudio() {
        logger.info("Disconnecting SCO audio")
        device.disconnectSCO()
    }

    public func transferAudioToComputer() throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.info("Transferring audio to computer")
        device.transferAudioToComputer()
    }

    // MARK: - AT Commands

    /// Send a raw AT command
    public func sendATCommand(_ command: String) throws {
        guard currentState.connection == .connected else {
            throw BluetoothError.notConnected
        }
        logger.debug("Sending AT command: \(command)")
        device.send(atCommand: command)
    }

    /// Request current call list (CLCC)
    public func requestCallList() throws {
        try sendATCommand("+CLCC")
    }

    /// Request operator name (COPS)
    public func requestOperator() throws {
        try sendATCommand("+COPS?")
    }
}