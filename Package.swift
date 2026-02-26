// swift-tools-version: 5.9
//
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

import PackageDescription

let package = Package(
    name: "PhoneBT",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PhoneBT", targets: ["PhoneBT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "2.2.0"),
    ],
    targets: [
        .target(
            name: "Shared",
            dependencies: []
        ),
        .target(
            name: "HFPCore",
            dependencies: ["Shared"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .target(
            name: "AudioPipeline",
            dependencies: ["Shared"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .target(
            name: "AgentBridge",
            dependencies: [
                "HFPCore",
                "AudioPipeline",
                "Shared",
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
            ]
        ),
        .executableTarget(
            name: "PhoneBT",
            dependencies: [
                "HFPCore",
                "AudioPipeline",
                "AgentBridge",
                "Shared",
            ]
        ),
        .testTarget(
            name: "HFPCoreTests",
            dependencies: ["HFPCore"]
        ),
        .testTarget(
            name: "AgentBridgeTests",
            dependencies: ["AgentBridge"]
        ),
    ]
)
