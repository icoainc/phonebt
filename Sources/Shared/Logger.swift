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
import os

public enum LogCategory: String {
    case bluetooth = "Bluetooth"
    case hfp = "HFP"
    case audio = "Audio"
    case agent = "Agent"
    case app = "App"
}

public struct PhoneBTLogger {
    private let logger: os.Logger

    public init(category: LogCategory) {
        self.logger = os.Logger(subsystem: "com.phonebt", category: category.rawValue)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }
}