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

public struct DiscoveredDevice: Sendable {
    public let name: String
    public let address: String
    public let isHandsFreeGateway: Bool

    public init(name: String, address: String, isHandsFreeGateway: Bool) {
        self.name = name
        self.address = address
        self.isHandsFreeGateway = isHandsFreeGateway
    }
}

public final class BluetoothManager: NSObject, @unchecked Sendable {
    private let logger = PhoneBTLogger(category: .bluetooth)
    private var inquiry: IOBluetoothDeviceInquiry?
    private var discoveredDevices: [DiscoveredDevice] = []
    private var scanContinuation: CheckedContinuation<[DiscoveredDevice], Error>?

    public override init() {
        super.init()
    }

    /// Scan for Bluetooth devices for the specified duration
    public func scanForDevices(duration: TimeInterval = 10) async throws -> [DiscoveredDevice] {
        logger.info("Starting device scan for \(Int(duration))s...")

        return try await withCheckedThrowingContinuation { continuation in
            self.scanContinuation = continuation
            self.discoveredDevices = []

            guard let inq = IOBluetoothDeviceInquiry(delegate: self) else {
                self.scanContinuation = nil
                continuation.resume(throwing: BluetoothError.scanFailed(kIOReturnError))
                return
            }
            inq.inquiryLength = UInt8(min(Int(duration), 255))
            inq.updateNewDeviceNames = true
            self.inquiry = inq

            let result = inq.start()
            if result != kIOReturnSuccess {
                self.scanContinuation = nil
                continuation.resume(throwing: BluetoothError.scanFailed(result))
            }
        }
    }

    /// Get already-paired devices that support HFP Audio Gateway
    public func getPairedPhones() -> [DiscoveredDevice] {
        logger.info("Looking for paired devices...")

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        let phones = paired.compactMap { device -> DiscoveredDevice? in
            let name = device.name ?? "Unknown"
            let address = device.addressString ?? "??:??:??:??:??:??"
            // Check for HFP Audio Gateway service (UUID 0x111F)
            let hfpAGUUID = IOBluetoothSDPUUID(uuid16: 0x111F)
            let isHFAG = device.services?.contains(where: { service in
                guard let svc = service as? IOBluetoothSDPServiceRecord else { return false }
                return svc.hasService(from: [hfpAGUUID as Any])
            }) ?? false

            return DiscoveredDevice(name: name, address: address, isHandsFreeGateway: isHFAG)
        }

        logger.info("Found \(phones.count) paired device(s)")
        return phones
    }

    /// Get an IOBluetoothDevice by address string
    public func device(forAddress address: String) -> IOBluetoothDevice? {
        return IOBluetoothDevice(addressString: address)
    }

    public func stopScan() {
        inquiry?.stop()
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension BluetoothManager: IOBluetoothDeviceInquiryDelegate {
    public func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry,
        device: IOBluetoothDevice
    ) {
        let name = device.name ?? "Unknown"
        let address = device.addressString ?? "??:??:??:??:??:??"
        logger.info("Found device: \(name) [\(address)]")

        let discovered = DiscoveredDevice(
            name: name,
            address: address,
            isHandsFreeGateway: false // Will be checked via SDP after scan
        )
        discoveredDevices.append(discovered)
    }

    public func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry,
        error: IOReturn,
        aborted: Bool
    ) {
        logger.info("Scan complete. Found \(discoveredDevices.count) device(s)")
        let cont = scanContinuation
        scanContinuation = nil
        inquiry = nil
        cont?.resume(returning: discoveredDevices)
    }
}

// MARK: - Errors

public enum BluetoothError: Error, LocalizedError {
    case scanFailed(IOReturn)
    case deviceNotFound
    case connectionFailed(String)
    case notConnected
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scanFailed(let code):
            return "Bluetooth scan failed with code: \(code)"
        case .deviceNotFound:
            return "Bluetooth device not found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .notConnected:
            return "Not connected to any device"
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        }
    }
}