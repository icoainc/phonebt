# PhoneBT

A macOS Bluetooth Hands-Free Profile (HFP) client that connects to an iPhone or Android phone, allowing a Claude AI agent to make and receive phone calls through the phone's cellular connection.

The Mac acts as the Hands-Free (HF) unit; the phone acts as the Audio Gateway (AG).

## How It Works

PhoneBT uses Apple's `IOBluetoothHandsFreeDevice` framework to establish an HFP Service Level Connection with a paired phone. Once connected, it can:

- **Dial numbers** and place outgoing calls
- **Answer or reject** incoming calls
- **Send DTMF tones** for navigating phone menus
- **Route audio** through the Mac's speakers and microphone via Bluetooth SCO
- **Hear callers** via on-device speech-to-text (Apple `SFSpeechRecognizer`)
- **Speak to callers** via text-to-speech (ElevenLabs API)
- **Report phone status** including signal strength, battery level, and carrier

In AI agent mode, Claude controls the phone through a tool-use conversation loop — you describe what you want in natural language, and Claude executes the appropriate phone commands. During active calls, Claude can hear what the caller says (via real-time transcription) and speak back to them (via TTS), enabling fully autonomous phone conversations.

## Requirements

- macOS 13 (Ventura) or later
- A Bluetooth-paired iPhone or Android phone
- Swift 5.9+
- `ANTHROPIC_API_KEY` environment variable (for AI agent mode)
- `ELEVENLABS_API_KEY` environment variable (optional, for TTS during calls)

## Building

```bash
swift build
```

## Running

```bash
swift run PhoneBT
```

### Interactive CLI

```
phonebt> paired           # List paired Bluetooth devices
phonebt> connect 2        # Connect to device at index 2
phonebt> dial +15551234567 # Place a call
phonebt> answer           # Answer an incoming call
phonebt> hangup           # End the current call
phonebt> dtmf 1           # Send a DTMF tone
phonebt> status           # Show call status
phonebt> phone            # Show phone status (signal, battery, carrier)
phonebt> audio            # List Bluetooth audio devices
phonebt> agent            # Enter AI agent mode
phonebt> quit             # Exit
```

### AI Agent Mode

Set your API keys and enter agent mode after connecting to a phone:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export ELEVENLABS_API_KEY=xi-...    # optional, enables TTS
swift run PhoneBT
```

```
phonebt> paired
phonebt> connect 2
phonebt> agent

agent> Call my voicemail
Agent: I'll dial *86 for you now.
[tool_use: dial_number(*86)]
Agent: Your voicemail is ringing. I'll let you know when it connects.

agent> Check the phone battery
Agent: Your phone is at 4/5 battery with 1/5 signal strength on T-Mobile.

agent> exit
```

The agent automatically receives incoming call notifications and can answer or reject them on your behalf.

### Real-Time Voice Conversations

When `ELEVENLABS_API_KEY` is set and a call is active with SCO audio connected, the audio pipeline starts automatically:

1. **Caller speech** is transcribed in real-time via Apple's on-device `SFSpeechRecognizer`
2. Transcriptions appear as `[CALLER SPEECH]` events in agent mode
3. Claude responds using the `say_to_caller` tool, which converts text to speech via ElevenLabs
4. The caller hears Claude's response through the phone

```
🔊 Audio connected
🗣️  Caller: "Hi, I'm calling about my appointment"
Agent: [tool_use: say_to_caller("Hello! I'd be happy to help with your appointment. Could you give me your name?")]
🗣️  Caller: "Sure, it's John Smith"
```

Speech recognition authorization is requested on first launch. Echo cancellation is enabled automatically on macOS 14+.

## Project Structure

```
Sources/
├── PhoneBT/main.swift              # CLI entry point
├── HFPCore/
│   ├── BluetoothManager.swift      # Device discovery & pairing
│   ├── HFPDevice.swift             # IOBluetoothHandsFreeDevice wrapper
│   ├── HFPStateMachine.swift       # Connection/call/audio state tracking
│   ├── HFPDelegate.swift           # HFP delegate → event stream
│   ├── HFPEvents.swift             # AsyncStream-based event distribution
│   └── ATCommandExtensions.swift   # AT response parsers (CLCC, COPS, CLIP)
├── AudioPipeline/
│   ├── AudioSessionManager.swift   # Shared AVAudioEngine for full-duplex BT audio
│   ├── AudioCapture.swift          # STT via SFSpeechRecognizer (on-device)
│   ├── TTSPlayer.swift             # TTS via ElevenLabs API
│   ├── AudioRouter.swift           # SCO ↔ CoreAudio bridge
│   └── AudioDeviceManager.swift    # System audio device management
├── AgentBridge/
│   ├── ClaudeAgent.swift           # Tool-use conversation loop
│   ├── PhoneTools.swift            # Tool definitions for Claude
│   └── ToolExecutor.swift          # Tool call → HFP command dispatch
└── Shared/
    ├── CallState.swift             # Call info model
    └── Logger.swift                # os_log wrapper
```

## Testing

```bash
swift test
```

30 tests covering the HFP state machine and tool executor (including `say_to_caller`).

## Known Limitations

- **SCO audio routing** depends on macOS exposing the Bluetooth SCO channel as a CoreAudio device, which may not work with all phone/Mac combinations. The `transferAudioToComputer()` API is attempted first, with manual CoreAudio routing as a fallback.
- **Entitlements**: On newer macOS versions, Bluetooth access may require specific entitlements or code signing. If device discovery fails, try running from Xcode with the Bluetooth entitlement enabled.
- **Speech recognition** requires user authorization on first use. The app requests this at startup. On-device recognition is preferred when available.
- **Echo cancellation** uses `AVAudioEngine` voice processing on macOS 14+. On macOS 13, input may pick up TTS playback.
- The AI agent uses Claude 3.7 Sonnet by default. You can change the model in `ClaudeAgent.swift`.

## License

Copyright 2026 ICOA Inc.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
