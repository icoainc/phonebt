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

/// Delegate that receives IOBluetoothHandsFreeDevice callbacks and forwards them as HFPEvents
public final class HFPDelegate: NSObject, IOBluetoothHandsFreeDeviceDelegate, @unchecked Sendable {
    private let eventStream: HFPEventStream
    private let logger = PhoneBTLogger(category: .hfp)

    public init(eventStream: HFPEventStream) {
        self.eventStream = eventStream
        super.init()
    }

    // MARK: - Connection

    public func handsFree(_ device: IOBluetoothHandsFree!,
                          connected status: NSNumber!) {
        // status is an IOReturn code: 0 (kIOReturnSuccess) means connected
        let statusCode = status?.intValue ?? -1
        let isConnected = (statusCode == 0) || (device?.isConnected ?? false)
        logger.info("Delegate: connected callback, status=\(statusCode), isConnected=\(isConnected)")
        if isConnected {
            eventStream.emit(.connected)
        } else {
            eventStream.emit(.connectFailed(
                BluetoothError.connectionFailed("Connection failed with status \(statusCode)")
            ))
        }
    }

    public func handsFree(_ device: IOBluetoothHandsFree!,
                          disconnected status: NSNumber!) {
        let statusCode = status?.intValue ?? -1
        logger.info("Delegate: disconnected, status=\(statusCode)")
        eventStream.emit(.disconnected(nil))
    }

    // MARK: - Call State Indicators

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          callSetupMode mode: NSNumber!) {
        let setupState = mode?.intValue ?? 0
        logger.info("Delegate: callSetup = \(setupState)")
        eventStream.emit(.callSetup(setupState))

        switch setupState {
        case 1:
            eventStream.emit(.incomingCall(number: nil))
        case 2:
            eventStream.emit(.callDialing(number: ""))
        case 3:
            eventStream.emit(.callAlerting)
        case 0:
            // Setup ended — call connected or released
            break
        default:
            break
        }
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          isCallActive: NSNumber!) {
        let active = isCallActive?.boolValue ?? false
        logger.info("Delegate: callActive = \(active)")
        eventStream.emit(.callIndicator(active))

        if active {
            eventStream.emit(.callActive)
        } else {
            eventStream.emit(.callEnded)
        }
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          callHoldState state: NSNumber!) {
        let held = state?.intValue ?? 0
        logger.info("Delegate: callHeld = \(held)")
        eventStream.emit(.callHeldIndicator(held))

        if held > 0 {
            eventStream.emit(.callHeld)
        }
    }

    // MARK: - Phone Status Indicators

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          signalStrength: NSNumber!) {
        eventStream.emit(.signalStrength(signalStrength?.intValue ?? 0))
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          batteryCharge: NSNumber!) {
        eventStream.emit(.batteryLevel(batteryCharge?.intValue ?? 0))
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          isServiceAvailable: NSNumber!) {
        eventStream.emit(.serviceAvailable(isServiceAvailable?.boolValue ?? false))
    }

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          isRoaming: NSNumber!) {
        eventStream.emit(.roaming(isRoaming?.boolValue ?? false))
    }

    // MARK: - Caller ID

    public func handsFree(_ device: IOBluetoothHandsFreeDevice!,
                          incomingCallFrom number: String!) {
        let num = number ?? "unknown"
        logger.info("Delegate: incoming call from \(num)")
        eventStream.emit(.callerID(number: num, name: nil))
        eventStream.emit(.incomingCall(number: num))
    }

    // MARK: - SCO Audio

    public func handsFree(_ device: IOBluetoothHandsFree!,
                          scoConnectionOpened status: NSNumber!) {
        logger.info("Delegate: SCO opened, status=\(status ?? 0)")
        eventStream.emit(.scoConnected)
    }

    public func handsFree(_ device: IOBluetoothHandsFree!,
                          scoConnectionClosed status: NSNumber!) {
        logger.info("Delegate: SCO closed, status=\(status ?? 0)")
        eventStream.emit(.scoDisconnected)
    }
}