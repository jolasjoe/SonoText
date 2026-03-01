import Foundation
import WhisperKit

class LocalWhisperService: ObservableObject {
    static let shared = LocalWhisperService()
    
    @Published var isModelReady = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = "Waiting to download model..."
    @Published var isDownloading = false
    
    private var whisperKit: WhisperKit?
    
    // Use "base" model — best mid-power balance: 145MB, accurate for English + decent multilingual
    let modelName = "base"
    
    var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SonoText/Models")
    }
    
    func checkModelExists() -> Bool {
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(modelName)")
        let exists = FileManager.default.fileExists(atPath: modelPath.path)
        whisperLogger.debug("Model check at \(modelPath.path, privacy: .public): exists=\(exists, privacy: .public)")
        return exists
    }
    
    func downloadAndInitialize() async {
        let modelExists = checkModelExists()
        whisperLogger.notice("Whisper initialize requested. model=\(self.modelName, privacy: .public) cached=\(modelExists, privacy: .public)")
        
        await MainActor.run {
            self.isDownloading = !modelExists
            self.statusMessage = modelExists ? "Warming up AI Engine..." : "Downloading Whisper \(modelName) model..."
            self.downloadProgress = modelExists ? 0.5 : 0.1
        }
        
        do {
            // Create model directory if needed
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            whisperLogger.debug("Model directory ready at \(self.modelDirectory.path, privacy: .public)")
            
            await MainActor.run { self.downloadProgress = modelExists ? 0.6 : 0.2 }
            
            whisperLogger.notice("Starting WhisperKit init: \(self.modelName, privacy: .public)")
            
            // WhisperKit auto-downloads the model on first init
            let config = WhisperKitConfig(
                model: modelName,
                downloadBase: modelDirectory,
                verbose: true
            )
            
            await MainActor.run {
                self.statusMessage = modelExists ? "Initializing CoreML..." : "Downloading model files (~145 MB)..."
                self.downloadProgress = modelExists ? 0.7 : 0.3
            }
            
            let kit = try await WhisperKit(config)
            
            await MainActor.run {
                self.downloadProgress = 0.9
                self.statusMessage = "Engine active!"
            }
            
            self.whisperKit = kit
            
            await MainActor.run {
                self.downloadProgress = 1.0
                self.isModelReady = true
                self.isDownloading = false
                self.statusMessage = "Ready"
                whisperLogger.notice("WhisperKit ready")
            }
        } catch {
            whisperLogger.error("WhisperKit init failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.statusMessage = "Error: \(error.localizedDescription)"
                self.isDownloading = false
                self.downloadProgress = 0
            }
        }
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        guard let kit = whisperKit else {
            whisperLogger.error("Transcribe requested before model ready")
            throw NSError(domain: "SonoText", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper model not loaded"])
        }
        
        whisperLogger.notice("Transcribe start: \(audioURL.lastPathComponent, privacy: .public)")
        let startedAt = Date()
        
        let results = try await kit.transcribe(audioPath: audioURL.path)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        whisperLogger.notice("Transcribe finished in \(elapsedMs, privacy: .public)ms. chars=\(text.count, privacy: .public)")
        return text
    }
}
