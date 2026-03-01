import Foundation

enum OpenAIError: LocalizedError {
    case httpError(statusCode: Int, message: String)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg):
            if code == 401 { return "Invalid API key (401). Re-enter your key." }
            if code == 429 { return "Rate limit or quota exceeded (429)." }
            if code == 413 { return "Audio too long (413). Try a shorter clip." }
            return "API error \(code): \(msg)"
        case .parseError:
            return "Could not parse API response."
        }
    }
}

class OpenAIService {
    static let shared = OpenAIService()
    var apiKey: String {
        return UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
    
    init() {}
    
    func transcribeAudio(fileURL: URL) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("whisper-1\r\n".data(using: .utf8)!)
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        let audioData = try Data(contentsOf: fileURL)
        data.append(audioData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        
        guard statusCode == 200 else {
            let rawMsg = String(data: responseData, encoding: .utf8) ?? "No body"
            // Try to extract OpenAI's error.message from JSON
            let friendlyMsg = extractOpenAIError(from: responseData) ?? rawMsg
            logger.error("🔴 Whisper error \(statusCode): \(rawMsg)")
            throw OpenAIError.httpError(statusCode: statusCode, message: friendlyMsg)
        }
        
        guard let jsonResult = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let text = jsonResult["text"] as? String else {
            throw OpenAIError.parseError
        }
        
        return text
    }
    
    func polishTranscription(draft: String, context: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an intelligent dictation assistant. Your job is to take raw, potentially messy voice transcriptions and output perfectly polished, written text.
        Rules:
        1. Remove filler words (um, uh, like).
        2. Format lists properly if the user says numbers.
        3. Catch punctuation naturally from tone.
        4. Understand verbal corrections (e.g. "Let's meet at 2... actually 3" -> "Let's meet at 3").
        5. Spell names correctly using the provided context.
        
        Context surrounding the cursor:
        \"\"\"
        \(context)
        \"\"\"
        
        Personalization directives:
        \(PersonalizationEngine.shared.getSystemPromptExtensions())
        
        ONLY output the corrected text. No explanations. No conversational responses.
        """
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": draft]
            ],
            "temperature": 0.3
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: jsonData)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        
        guard statusCode == 200 else {
            let rawMsg = String(data: responseData, encoding: .utf8) ?? "No body"
            let friendlyMsg = extractOpenAIError(from: responseData) ?? rawMsg
            logger.error("🔴 GPT-4o error \(statusCode): \(rawMsg)")
            throw OpenAIError.httpError(statusCode: statusCode, message: friendlyMsg)
        }
        
        guard let jsonResult = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = jsonResult["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let polishedText = message["content"] as? String else {
            throw OpenAIError.parseError
        }
        
        return polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractOpenAIError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }
}
