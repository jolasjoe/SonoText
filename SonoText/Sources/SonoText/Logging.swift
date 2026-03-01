import Foundation
import os.log

let appSubsystem = "com.sonotext.mac"

let logger = Logger(subsystem: appSubsystem, category: "App")
let audioLogger = Logger(subsystem: appSubsystem, category: "AudioRecorder")
let whisperLogger = Logger(subsystem: appSubsystem, category: "Whisper")
let keystrokeLogger = Logger(subsystem: appSubsystem, category: "Keystroke")
let openAILogger = Logger(subsystem: appSubsystem, category: "OpenAI")
let settingsLogger = Logger(subsystem: appSubsystem, category: "Settings")
let personalizationLogger = Logger(subsystem: appSubsystem, category: "Personalization")
