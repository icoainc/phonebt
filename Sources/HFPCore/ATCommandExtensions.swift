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

/// Helpers for parsing AT command responses commonly used with HFP
public enum ATParser {

    /// Parse a CLCC (Current List of Current Calls) response line
    /// Format: +CLCC: <idx>,<dir>,<stat>,<mode>,<mpty>[,<number>,<type>]
    public static func parseCLCC(_ line: String) -> CallInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+CLCC:") else { return nil }

        let payload = String(trimmed.dropFirst("+CLCC:".count))
            .trimmingCharacters(in: .whitespaces)
        let parts = payload.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard parts.count >= 5,
              let index = Int(parts[0]),
              let dirInt = Int(parts[1]),
              let statInt = Int(parts[2]) else {
            return nil
        }

        let direction: CallDirection = dirInt == 0 ? .outgoing : .incoming

        let status: CallStatus
        switch statInt {
        case 0: status = .active
        case 1: status = .held
        case 2: status = .dialing
        case 3: status = .alerting
        case 4: status = .incoming
        case 5: status = .waiting
        default: status = .idle
        }

        var number: String?
        if parts.count > 5 {
            number = parts[5].replacingOccurrences(of: "\"", with: "")
        }

        return CallInfo(index: index, direction: direction, status: status, number: number)
    }

    /// Parse a COPS (Current Operator Selection) response
    /// Format: +COPS: <mode>,<format>,<oper>
    public static func parseCOPS(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+COPS:") else { return nil }

        let payload = String(trimmed.dropFirst("+COPS:".count))
            .trimmingCharacters(in: .whitespaces)
        let parts = payload.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard parts.count >= 3 else { return nil }
        return parts[2].replacingOccurrences(of: "\"", with: "")
    }

    /// Parse a CLIP (Calling Line Identification Presentation) response
    /// Format: +CLIP: <number>,<type>[,<subaddr>,<satype>[,<alpha>]]
    public static func parseCLIP(_ line: String) -> (number: String, name: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+CLIP:") else { return nil }

        let payload = String(trimmed.dropFirst("+CLIP:".count))
            .trimmingCharacters(in: .whitespaces)
        let parts = payload.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard !parts.isEmpty else { return nil }

        let number = parts[0].replacingOccurrences(of: "\"", with: "")
        var name: String?
        if parts.count >= 5 {
            let alpha = parts[4].replacingOccurrences(of: "\"", with: "")
            if !alpha.isEmpty {
                name = alpha
            }
        }

        return (number: number, name: name)
    }
}