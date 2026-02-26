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
import CoreAudio
import Shared

/// Routes audio between SCO Bluetooth connection and system audio devices
public final class AudioRouter: @unchecked Sendable {
    private let deviceManager: AudioDeviceManager
    private let logger = PhoneBTLogger(category: .audio)

    private var previousOutputDevice: AudioDeviceID?
    private var previousInputDevice: AudioDeviceID?
    private var isRouted = false

    public init(deviceManager: AudioDeviceManager = AudioDeviceManager()) {
        self.deviceManager = deviceManager
    }

    /// Route audio to Bluetooth device when SCO connection opens
    public func routeToBluetoothDevice() -> Bool {
        let btDevices = deviceManager.getBluetoothDevices()

        guard !btDevices.isEmpty else {
            logger.error("No Bluetooth audio devices found for routing")
            return false
        }

        // Save current defaults for restoration
        previousOutputDevice = deviceManager.getDefaultOutputDevice()
        previousInputDevice = deviceManager.getDefaultInputDevice()

        // Find a BT device with both input and output (SCO device)
        if let scoDevice = btDevices.first(where: { $0.hasInput && $0.hasOutput }) {
            logger.info("Routing audio to SCO device: \(scoDevice.name) [\(scoDevice.id)]")
            let outOk = deviceManager.setDefaultOutputDevice(scoDevice.id)
            let inOk = deviceManager.setDefaultInputDevice(scoDevice.id)
            isRouted = outOk && inOk

            if isRouted {
                logger.info("Audio routed to Bluetooth successfully")
            } else {
                logger.error("Failed to route audio to Bluetooth")
            }
            return isRouted
        }

        // Fall back to separate input/output BT devices
        var routed = false
        if let outputDevice = btDevices.first(where: { $0.hasOutput }) {
            logger.info("Setting BT output: \(outputDevice.name)")
            routed = deviceManager.setDefaultOutputDevice(outputDevice.id)
        }
        if let inputDevice = btDevices.first(where: { $0.hasInput }) {
            logger.info("Setting BT input: \(inputDevice.name)")
            routed = deviceManager.setDefaultInputDevice(inputDevice.id) && routed
        }

        isRouted = routed
        return routed
    }

    /// Restore previous audio routing when call ends
    public func restorePreviousRouting() {
        guard isRouted else { return }

        if let prevOutput = previousOutputDevice {
            logger.info("Restoring previous output device: \(prevOutput)")
            _ = deviceManager.setDefaultOutputDevice(prevOutput)
        }
        if let prevInput = previousInputDevice {
            logger.info("Restoring previous input device: \(prevInput)")
            _ = deviceManager.setDefaultInputDevice(prevInput)
        }

        previousOutputDevice = nil
        previousInputDevice = nil
        isRouted = false
        logger.info("Audio routing restored")
    }

    /// List available Bluetooth audio devices (for debugging)
    public func listBluetoothDevices() -> [AudioDeviceInfo] {
        let devices = deviceManager.getBluetoothDevices()
        for device in devices {
            logger.info("BT Audio: \(device.name) [id=\(device.id), in=\(device.hasInput), out=\(device.hasOutput)]")
        }
        return devices
    }
}