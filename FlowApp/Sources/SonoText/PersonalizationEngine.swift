import Foundation
import SwiftUI

class PersonalizationEngine: ObservableObject {
    static let shared = PersonalizationEngine()
    
    @AppStorage("customDictionary") var customDictionaryStr: String = ""
    @AppStorage("customSnippets") var customSnippetsStr: String = ""
    @AppStorage("activeStyle") var activeStyle: String = "Neutral"
    
    // Format for snippets string: "key1:value1|key2:value2"
    // Format for dictionary string: "word1,word2,word3"
    
    func getSystemPromptExtensions() -> String {
        var extensions = ""
        
        if !customDictionaryStr.isEmpty {
            extensions += "\nUser's Personal Dictionary (Favor these spellings):\n"
            let words = customDictionaryStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            extensions += words.joined(separator: ", ") + "\n"
        }
        
        if !customSnippetsStr.isEmpty {
            extensions += "\nUser's Snippets (If the user explicitly asks for a snippet cue, expand it to the associated template):\n"
            let snippets = customSnippetsStr.split(separator: "|")
            for snippet in snippets {
                let parts = snippet.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    extensions += "- Cue: `\(parts[0])` -> Expansion: `\(parts[1])`\n"
                }
            }
        }
        
        if activeStyle != "Neutral" {
            extensions += "\nOutput Style/Tone: \(activeStyle). Adjust the final text to match this tone.\n"
        }
        
        return extensions
    }
}
