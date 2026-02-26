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
import HFPCore
import Shared

/// Claude AI agent that manages phone calls via tool-use conversation loop
public final class ClaudeAgent: @unchecked Sendable {
    private let service: AnthropicService
    private let toolExecutor: ToolExecutor
    private let eventStream: HFPEventStream
    private let logger = PhoneBTLogger(category: .agent)

    private var conversationHistory: [MessageParameter.Message] = []
    private let model: Model = .claude37Sonnet

    private let systemPrompt = """
        You are a phone call assistant. You can make and receive phone calls through \
        a Bluetooth-connected phone. You have tools to dial numbers, accept/end calls, \
        send DTMF tones, and check call/phone status.

        When a user asks you to call someone, use the dial_number tool. \
        When an incoming call arrives, inform the user and ask if they want to answer. \
        Provide helpful status updates about ongoing calls.

        Be concise in your responses. Report tool results clearly.
        """

    public init(apiKey: String, toolExecutor: ToolExecutor, eventStream: HFPEventStream) {
        self.service = AnthropicServiceFactory.service(apiKey: apiKey, betaHeaders: nil)
        self.toolExecutor = toolExecutor
        self.eventStream = eventStream
    }

    /// Process a user message through the agent loop, returning the final text response
    public func processMessage(_ userMessage: String) async throws -> String {
        conversationHistory.append(
            .init(role: .user, content: .text(userMessage))
        )

        return try await runAgentLoop()
    }

    /// Inject a system event (e.g., incoming call notification) into the conversation
    public func injectEvent(_ eventDescription: String) async throws -> String {
        let message = "[PHONE EVENT] \(eventDescription)"
        conversationHistory.append(
            .init(role: .user, content: .text(message))
        )

        return try await runAgentLoop()
    }

    /// Start listening for HFP events and forwarding them to the agent
    public func startEventListener(onResponse: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        let stream = eventStream.makeStream()

        return Task { [weak self] in
            for await event in stream {
                guard let self = self else { break }

                let description: String?
                switch event {
                case .incomingCall(let number):
                    description = "Incoming call from \(number ?? "unknown number")"
                case .callEnded:
                    description = "Call has ended"
                case .callActive:
                    description = "Call is now active"
                case .scoConnected:
                    description = "Audio connected — you can now hear and speak"
                case .scoDisconnected:
                    description = "Audio disconnected"
                default:
                    description = nil
                }

                if let desc = description {
                    do {
                        let response = try await self.injectEvent(desc)
                        onResponse(response)
                    } catch {
                        self.logger.error("Failed to inject event: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func runAgentLoop() async throws -> String {
        var iterations = 0
        let maxIterations = 10

        while iterations < maxIterations {
            iterations += 1

            let parameters = MessageParameter(
                model: model,
                messages: conversationHistory,
                maxTokens: 1024,
                system: .text(systemPrompt),
                tools: PhoneTools.allTools
            )

            let response = try await service.createMessage(parameters)

            // Convert response content to message content objects for history
            let contentObjects = response.content.map { responseContentToMessageContent($0) }
            conversationHistory.append(
                .init(role: .assistant, content: .list(contentObjects))
            )

            // Check if we need to handle tool calls
            if response.stopReason == "tool_use" {
                var toolResults: [MessageParameter.Message.Content.ContentObject] = []

                for content in response.content {
                    if case .toolUse(let toolUse) = content {
                        logger.info("Tool call: \(toolUse.name)")

                        // Convert DynamicContent input to [String: Any]
                        let inputDict = dynamicContentToDict(toolUse.input)
                        let result = toolExecutor.execute(toolName: toolUse.name, input: inputDict)

                        toolResults.append(
                            .toolResult(toolUse.id, result)
                        )
                    }
                }

                // Add tool results as user message
                conversationHistory.append(
                    .init(role: .user, content: .list(toolResults))
                )

                // Continue the loop to get the model's response to tool results
                continue
            }

            // No more tool calls — extract text response
            return extractTextResponse(from: response.content)
        }

        return "Agent reached maximum iterations without completing."
    }

    /// Convert a response Content to a message ContentObject for conversation history
    private func responseContentToMessageContent(
        _ content: MessageResponse.Content
    ) -> MessageParameter.Message.Content.ContentObject {
        switch content {
        case .text(let text, _):
            return .text(text)
        case .toolUse(let toolUse):
            return .toolUse(toolUse.id, toolUse.name, toolUse.input)
        case .thinking(let thinking):
            return .thinking(thinking.thinking, thinking.signature ?? "")
        default:
            return .text("")
        }
    }

    private func extractTextResponse(from content: [MessageResponse.Content]) -> String {
        var texts: [String] = []
        for item in content {
            if case .text(let text, _) = item {
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n")
    }

    private func dynamicContentToDict(
        _ input: [String: MessageResponse.Content.DynamicContent]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in input {
            result[key] = dynamicContentToAny(value)
        }
        return result
    }

    private func dynamicContentToAny(_ value: MessageResponse.Content.DynamicContent) -> Any {
        switch value {
        case .string(let s): return s
        case .integer(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { dynamicContentToAny($0) }
        case .dictionary(let dict): return dynamicContentToDict(dict)
        }
    }
}