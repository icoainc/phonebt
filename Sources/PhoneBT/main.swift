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
import AgentBridge
import Shared

// MARK: - CLI Application

let logger = PhoneBTLogger(category: .app)

func printBanner() {
    print("""

    ╔══════════════════════════════════════╗
    ║          PhoneBT v0.1.0             ║
    ║  Bluetooth HFP Client for macOS    ║
    ║  AI-Driven Phone Call Management   ║
    ╚══════════════════════════════════════╝
    """)
}

func printHelp() {
    print("""
    Commands:
      scan          - Scan for Bluetooth devices
      paired        - List paired devices
      connect <idx> - Connect to device by index
      disconnect    - Disconnect current device
      dial <number> - Dial a phone number
      answer        - Answer incoming call
      hangup        - End current call
      dtmf <digit>  - Send DTMF tone
      status        - Show call status
      phone         - Show phone status
      audio         - Show audio devices
      agent         - Enter AI agent mode
      help          - Show this help
      quit          - Exit PhoneBT
    """)
}

// MARK: - Global State

let bluetoothManager = BluetoothManager()
let audioRouter = AudioRouter()
var hfpDevice: HFPDevice?
var claudeAgent: ClaudeAgent?
var eventListenerTask: Task<Void, Never>?
var discoveredDevices: [DiscoveredDevice] = []
var isRunning = true

// MARK: - Signal Handling

signal(SIGINT) { _ in
    print("\nShutting down...")
    isRunning = false
    hfpDevice?.disconnect()
    audioRouter.restorePreviousRouting()
    exit(0)
}

signal(SIGTERM) { _ in
    hfpDevice?.disconnect()
    audioRouter.restorePreviousRouting()
    exit(0)
}

// MARK: - Command Handlers

func handleScan() async {
    print("Scanning for Bluetooth devices (10 seconds)...")
    do {
        discoveredDevices = try await bluetoothManager.scanForDevices(duration: 10)
        if discoveredDevices.isEmpty {
            print("No devices found. Try 'paired' to see already-paired devices.")
        } else {
            printDeviceList(discoveredDevices)
        }
    } catch {
        print("Scan error: \(error.localizedDescription)")
    }
}

func handlePaired() {
    discoveredDevices = bluetoothManager.getPairedPhones()
    if discoveredDevices.isEmpty {
        print("No paired devices found.")
    } else {
        printDeviceList(discoveredDevices)
    }
}

func printDeviceList(_ devices: [DiscoveredDevice]) {
    print("\nFound \(devices.count) device(s):")
    for (i, device) in devices.enumerated() {
        let hfp = device.isHandsFreeGateway ? " [HFP]" : ""
        print("  [\(i)] \(device.name) (\(device.address))\(hfp)")
    }
    print()
}

func handleConnect(indexStr: String) async {
    guard let index = Int(indexStr), index >= 0, index < discoveredDevices.count else {
        print("Invalid device index. Run 'scan' or 'paired' first.")
        return
    }

    let selected = discoveredDevices[index]
    guard let btDevice = bluetoothManager.device(forAddress: selected.address) else {
        print("Could not find device with address \(selected.address)")
        return
    }

    guard let device = HFPDevice(bluetoothDevice: btDevice) else {
        print("Failed to create HFP device for \(selected.name)")
        return
    }
    hfpDevice = device

    print("Connecting to \(selected.name)...")
    do {
        try await device.connect()
        print("Connected to \(selected.name)")

        // Start event monitoring
        let stream = device.eventStream.makeStream()
        Task {
            for await event in stream {
                handleEvent(event)
            }
        }
    } catch {
        print("Connection failed: \(error.localizedDescription)")
        hfpDevice = nil
    }
}

func handleEvent(_ event: HFPEvent) {
    switch event {
    case .incomingCall(let number):
        print("\n📞 Incoming call from \(number ?? "unknown")")
        print("Type 'answer' to accept or 'hangup' to reject")
    case .callEnded:
        print("\n📱 Call ended")
    case .callActive:
        print("\n📱 Call active")
    case .scoConnected:
        print("\n🔊 Audio connected")
        _ = audioRouter.routeToBluetoothDevice()
    case .scoDisconnected:
        print("\n🔇 Audio disconnected")
        audioRouter.restorePreviousRouting()
    case .disconnected:
        print("\n⚠️  Device disconnected")
        hfpDevice = nil
    default:
        break
    }
}

func handleDial(number: String) {
    guard let device = hfpDevice else {
        print("Not connected. Use 'connect' first.")
        return
    }
    do {
        try device.dial(number: number)
        print("Dialing \(number)...")
        try? device.transferAudioToComputer()
    } catch {
        print("Dial failed: \(error.localizedDescription)")
    }
}

func handleAnswer() {
    guard let device = hfpDevice else {
        print("Not connected.")
        return
    }
    do {
        try device.acceptCall()
        try? device.transferAudioToComputer()
        _ = audioRouter.routeToBluetoothDevice()
        print("Call answered")
    } catch {
        print("Answer failed: \(error.localizedDescription)")
    }
}

func handleHangup() {
    guard let device = hfpDevice else {
        print("Not connected.")
        return
    }
    do {
        try device.endCall()
        audioRouter.restorePreviousRouting()
        print("Call ended")
    } catch {
        print("Hangup failed: \(error.localizedDescription)")
    }
}

func handleDTMF(digit: String) {
    guard let device = hfpDevice else {
        print("Not connected.")
        return
    }
    do {
        try device.sendDTMF(digit)
    } catch {
        print("DTMF failed: \(error.localizedDescription)")
    }
}

func handleStatus() {
    guard let device = hfpDevice else {
        print("Not connected.")
        return
    }
    let state = device.currentState
    print("Connection: \(state.connection.rawValue)")
    print("Call: \(state.call.rawValue)")
    print("Audio: \(state.audio.rawValue)")
    if let call = state.activeCall {
        print("  Direction: \(call.direction.rawValue)")
        print("  Number: \(call.number ?? "unknown")")
        if let duration = call.durationDescription {
            print("  Duration: \(duration)")
        }
    }
}

func handlePhoneStatus() {
    guard let device = hfpDevice else {
        print("Not connected.")
        return
    }
    let phone = device.currentState.phoneStatus
    print("Signal: \(phone.signalStrength)/5")
    print("Battery: \(phone.batteryLevel)/5")
    print("Service: \(phone.serviceAvailable ? "available" : "unavailable")")
    print("Operator: \(phone.operatorName ?? "unknown")")
    print("Roaming: \(phone.roaming ? "yes" : "no")")
}

func handleAudioDevices() {
    let devices = audioRouter.listBluetoothDevices()
    if devices.isEmpty {
        print("No Bluetooth audio devices found.")
    } else {
        print("Bluetooth audio devices:")
        for device in devices {
            print("  \(device.name) [id=\(device.id), in=\(device.hasInput), out=\(device.hasOutput)]")
        }
    }
}

func handleAgentMode() async {
    guard let device = hfpDevice else {
        print("Not connected. Connect to a phone first.")
        return
    }

    guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
        print("ANTHROPIC_API_KEY environment variable not set.")
        print("Export it with: export ANTHROPIC_API_KEY=your-key-here")
        return
    }

    let executor = ToolExecutor(device: device, audioRouter: audioRouter)
    let agent = ClaudeAgent(apiKey: apiKey, toolExecutor: executor, eventStream: device.eventStream)
    claudeAgent = agent

    // Start event listener
    eventListenerTask = agent.startEventListener { response in
        print("\nAgent: \(response)")
        print("agent> ", terminator: "")
        fflush(stdout)
    }

    print("\nAI Agent Mode — type natural language commands")
    print("Type 'exit' to return to manual mode\n")

    while isRunning {
        print("agent> ", terminator: "")
        fflush(stdout)

        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else {
            continue
        }

        if line.lowercased() == "exit" {
            eventListenerTask?.cancel()
            eventListenerTask = nil
            claudeAgent = nil
            print("Exiting agent mode.")
            break
        }

        do {
            let response = try await agent.processMessage(line)
            print("Agent: \(response)")
        } catch {
            print("Agent error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Main Loop

printBanner()
printHelp()

// Run the main loop
let mainTask = Task {
    while isRunning {
        print("phonebt> ", terminator: "")
        fflush(stdout)

        guard let line = readLine() else {
            // EOF — stdin closed (e.g., piped input exhausted)
            break
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1] : ""

        switch command {
        case "scan":
            await handleScan()
        case "paired":
            handlePaired()
        case "connect":
            await handleConnect(indexStr: argument)
        case "disconnect":
            hfpDevice?.disconnect()
            hfpDevice = nil
            print("Disconnected.")
        case "dial", "call":
            handleDial(number: argument)
        case "answer", "accept":
            handleAnswer()
        case "hangup", "end":
            handleHangup()
        case "dtmf":
            handleDTMF(digit: argument)
        case "status":
            handleStatus()
        case "phone":
            handlePhoneStatus()
        case "audio":
            handleAudioDevices()
        case "agent", "ai":
            await handleAgentMode()
        case "help":
            printHelp()
        case "quit", "exit", "q":
            print("Goodbye!")
            isRunning = false
            hfpDevice?.disconnect()
            audioRouter.restorePreviousRouting()
            exit(0)
        default:
            print("Unknown command: \(command). Type 'help' for available commands.")
        }
    }
}

// Keep the run loop alive for Bluetooth callbacks
RunLoop.main.run()