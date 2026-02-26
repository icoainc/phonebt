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
import SwiftAnthropic

/// Tool definitions for the Claude agent to control phone calls
public enum PhoneTools {

    public static let allTools: [MessageParameter.Tool] = [
        dialNumberTool,
        acceptCallTool,
        endCallTool,
        sendDTMFTool,
        getCallStatusTool,
        getPhoneStatusTool,
        sayToCallerTool,
    ]

    public static let dialNumberTool: MessageParameter.Tool = .function(
        name: "dial_number",
        description: "Dial a phone number to make an outgoing call. The number should be in a valid format (digits, optional + prefix, optional dashes/spaces).",
        inputSchema: JSONSchema(
            type: .object,
            properties: [
                "number": JSONSchema.Property(
                    type: .string,
                    description: "The phone number to dial, e.g. '+15551234567' or '555-123-4567'"
                ),
            ],
            required: ["number"]
        )
    )

    public static let acceptCallTool: MessageParameter.Tool = .function(
        name: "accept_call",
        description: "Accept/answer an incoming phone call.",
        inputSchema: JSONSchema(
            type: .object,
            properties: [:]
        )
    )

    public static let endCallTool: MessageParameter.Tool = .function(
        name: "end_call",
        description: "End/hang up the current active call.",
        inputSchema: JSONSchema(
            type: .object,
            properties: [:]
        )
    )

    public static let sendDTMFTool: MessageParameter.Tool = .function(
        name: "send_dtmf",
        description: "Send a DTMF tone (touch-tone digit) during an active call. Used for navigating phone menus (IVR systems).",
        inputSchema: JSONSchema(
            type: .object,
            properties: [
                "digit": JSONSchema.Property(
                    type: .string,
                    description: "A single DTMF digit: 0-9, *, or #"
                ),
            ],
            required: ["digit"]
        )
    )

    public static let getCallStatusTool: MessageParameter.Tool = .function(
        name: "get_call_status",
        description: "Get the current call status including call state, direction, duration, and phone number.",
        inputSchema: JSONSchema(
            type: .object,
            properties: [:]
        )
    )

    public static let getPhoneStatusTool: MessageParameter.Tool = .function(
        name: "get_phone_status",
        description: "Get the phone's status including signal strength, battery level, service availability, operator name, and roaming status.",
        inputSchema: JSONSchema(
            type: .object,
            properties: [:]
        )
    )

    public static let sayToCallerTool: MessageParameter.Tool = .function(
        name: "say_to_caller",
        description: "Speak text to the caller during an active phone call using text-to-speech. The caller will hear your spoken words through the phone.",
        inputSchema: JSONSchema(
            type: .object,
            properties: [
                "text": JSONSchema.Property(
                    type: .string,
                    description: "The text to speak to the caller"
                ),
            ],
            required: ["text"]
        )
    )
}