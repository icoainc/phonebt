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

public enum CallDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

public enum CallStatus: String, Codable, Sendable {
    case idle
    case dialing
    case alerting
    case incoming
    case active
    case held
    case waiting
    case ended
}

public struct CallInfo: Codable, Sendable {
    public let index: Int
    public let direction: CallDirection
    public var status: CallStatus
    public var number: String?
    public var startTime: Date?

    public init(index: Int, direction: CallDirection, status: CallStatus, number: String? = nil) {
        self.index = index
        self.direction = direction
        self.status = status
        self.number = number
        self.startTime = nil
    }

    public var durationDescription: String? {
        guard let start = startTime else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public struct PhoneStatus: Codable, Sendable {
    public var signalStrength: Int
    public var batteryLevel: Int
    public var serviceAvailable: Bool
    public var operatorName: String?
    public var roaming: Bool

    public init() {
        self.signalStrength = 0
        self.batteryLevel = 0
        self.serviceAvailable = false
        self.operatorName = nil
        self.roaming = false
    }
}