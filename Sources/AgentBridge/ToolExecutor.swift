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
import HFPCore
import AudioPipeline
import Shared

/// Executes tool calls by mapping them to HFP device commands
public final class ToolExecutor: @unchecked Sendable {
    private let device: HFPDevice
    private let audioRouter: AudioRouter
    private let logger = PhoneBTLogger(category: .agent)
    public var ttsPlayer: TTSPlayer?

    public init(device: HFPDevice, audioRouter: AudioRouter, ttsPlayer: TTSPlayer? = nil) {
        self.device = device
        self.audioRouter = audioRouter
        self.ttsPlayer = ttsPlayer
    }

    /// Execute a tool call and return JSON result string
    public func execute(toolName: String, input: [String: Any]) -> String {
        logger.info("Executing tool: \(toolName)")

        do {
            switch toolName {
            case "dial_number":
                return try executeDial(input: input)
            case "accept_call":
                return try executeAccept()
            case "end_call":
                return try executeEndCall()
            case "send_dtmf":
                return try executeSendDTMF(input: input)
            case "get_call_status":
                return executeGetCallStatus()
            case "get_phone_status":
                return executeGetPhoneStatus()
            case "say_to_caller":
                return executeSayToCaller(input: input)
            default:
                return errorJSON("Unknown tool: \(toolName)")
            }
        } catch {
            return errorJSON(error.localizedDescription)
        }
    }

    // MARK: - Tool Implementations

    private func executeDial(input: [String: Any]) throws -> String {
        guard let number = input["number"] as? String else {
            return errorJSON("Missing required parameter: number")
        }

        let sanitized = sanitizePhoneNumber(number)
        try device.dial(number: sanitized)

        // Try to connect audio proactively
        try? device.transferAudioToComputer()

        return successJSON([
            "status": "dialing",
            "number": sanitized,
        ])
    }

    private func executeAccept() throws -> String {
        try device.acceptCall()

        // Route audio to computer
        try? device.transferAudioToComputer()
        _ = audioRouter.routeToBluetoothDevice()

        return successJSON([
            "status": "answered",
        ])
    }

    private func executeEndCall() throws -> String {
        try device.endCall()

        // Restore audio routing
        audioRouter.restorePreviousRouting()

        return successJSON([
            "status": "ended",
        ])
    }

    private func executeSendDTMF(input: [String: Any]) throws -> String {
        guard let digit = input["digit"] as? String else {
            return errorJSON("Missing required parameter: digit")
        }

        try device.sendDTMF(digit)

        return successJSON([
            "status": "sent",
            "digit": digit,
        ])
    }

    private func executeGetCallStatus() -> String {
        let state = device.currentState

        var result: [String: Any] = [
            "call_state": state.call.rawValue,
            "audio_connected": state.audio == .connected,
        ]

        if let call = state.activeCall {
            result["direction"] = call.direction.rawValue
            result["number"] = call.number ?? "unknown"
            if let duration = call.durationDescription {
                result["duration"] = duration
            }
        }

        return successJSON(result)
    }

    private func executeGetPhoneStatus() -> String {
        let phone = device.currentState.phoneStatus

        return successJSON([
            "signal_strength": phone.signalStrength,
            "battery_level": phone.batteryLevel,
            "service_available": phone.serviceAvailable,
            "operator": phone.operatorName ?? "unknown",
            "roaming": phone.roaming,
        ] as [String: Any])
    }

    private func executeSayToCaller(input: [String: Any]) -> String {
        guard let text = input["text"] as? String else {
            return errorJSON("Missing required parameter: text")
        }

        guard let ttsPlayer = ttsPlayer else {
            return errorJSON("TTS not available — ELEVENLABS_API_KEY not set or audio pipeline not started")
        }

        // Fire TTS in a detached task so the tool returns immediately
        Task.detached { [logger] in
            do {
                try await ttsPlayer.speak(text)
                logger.info("TTS playback completed for: \(text.prefix(50))")
            } catch {
                logger.error("TTS playback failed: \(error)")
            }
        }

        return successJSON([
            "status": "speaking",
            "text": text,
        ])
    }

    // MARK: - Helpers

    private func sanitizePhoneNumber(_ number: String) -> String {
        // Keep digits, +, *, #
        return number.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
    }

    private func successJSON(_ data: [String: Any]) -> String {
        var result = data
        result["success"] = true
        return jsonString(result)
    }

    private func errorJSON(_ message: String) -> String {
        return jsonString(["success": false, "error": message])
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        // Manual JSON serialization to avoid Foundation's unordered output
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"success\":false,\"error\":\"JSON serialization failed\"}"
        }
        return str
    }
}