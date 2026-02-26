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
import AVFoundation
import Shared

/// Plays TTS audio via ElevenLabs API through the shared AVAudioEngine
public final class TTSPlayer: @unchecked Sendable {
    private let sessionManager: AudioSessionManager
    private let apiKey: String
    private let voiceID: String
    private let logger = PhoneBTLogger(category: .audio)
    private let urlSession = URLSession.shared

    private let sampleRate: Double = 16000
    private let outputFormat = "pcm_16000"

    public init(sessionManager: AudioSessionManager, apiKey: String, voiceID: String = "21m00Tcm4TlvDq8ikWAM") {
        self.sessionManager = sessionManager
        self.apiKey = apiKey
        self.voiceID = voiceID
    }

    /// Synthesize and play text through the audio engine's player node
    public func speak(_ text: String) async throws {
        let pcmData = try await synthesize(text)
        let buffer = try createPCMBuffer(from: pcmData)

        let playerNode = sessionManager.playerNode
        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Schedule buffer and wait for completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
        }
    }

    /// Cancel any currently playing TTS audio
    public func cancelCurrentPlayback() {
        sessionManager.playerNode.stop()
        sessionManager.playerNode.play() // re-arm for next buffer
        logger.info("TTS playback cancelled")
    }

    // MARK: - Private

    private func synthesize(_ text: String) async throws -> Data {
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=\(outputFormat)"
        guard let url = URL(string: urlString) else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("TTS request: \(text.prefix(50))...")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw TTSError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        logger.info("TTS received \(data.count) bytes of PCM audio")
        return data
    }

    private func createPCMBuffer(from pcmData: Data) throws -> AVAudioPCMBuffer {
        // ElevenLabs pcm_16000 returns raw 16-bit signed LE mono PCM at 16kHz
        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!

        let frameCount = UInt32(pcmData.count / MemoryLayout<Int16>.size)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
            throw TTSError.bufferCreationFailed
        }
        pcmBuffer.frameLength = frameCount

        // Copy raw PCM data into the buffer
        pcmData.withUnsafeBytes { rawPtr in
            let src = rawPtr.bindMemory(to: Int16.self)
            pcmBuffer.int16ChannelData![0].update(from: src.baseAddress!, count: Int(frameCount))
        }

        // Convert to the player node's output format if needed
        let playerFormat = sessionManager.engine.outputNode.inputFormat(forBus: 0)
        if pcmFormat.sampleRate == playerFormat.sampleRate
            && pcmFormat.channelCount == playerFormat.channelCount
            && pcmFormat.commonFormat == playerFormat.commonFormat {
            return pcmBuffer
        }

        guard let converter = AVAudioConverter(from: pcmFormat, to: playerFormat) else {
            throw TTSError.converterCreationFailed
        }

        let ratio = playerFormat.sampleRate / pcmFormat.sampleRate
        let convertedFrameCount = UInt32(Double(frameCount) * ratio)
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: playerFormat,
            frameCapacity: convertedFrameCount
        ) else {
            throw TTSError.bufferCreationFailed
        }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let error = error {
            throw TTSError.conversionFailed(error.localizedDescription)
        }

        return convertedBuffer
    }
}

public enum TTSError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case bufferCreationFailed
    case converterCreationFailed
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid ElevenLabs API URL"
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        case .apiError(let code, let message):
            return "ElevenLabs API error (\(code)): \(message)"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        case .conversionFailed(let reason):
            return "Audio format conversion failed: \(reason)"
        }
    }
}
