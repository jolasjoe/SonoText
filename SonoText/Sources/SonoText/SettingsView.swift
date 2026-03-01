import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine = PersonalizationEngine.shared
    @State private var openAIApiKey: String = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
    
    let styles = ["Neutral", "Professional", "Casual", "Enthusiastic"]
    
    var body: some View {
        TabView {
            // General Settings
            Form {
                SecureField("OpenAI API Key", text: $openAIApiKey)
                    .onChange(of: openAIApiKey) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "OPENAI_API_KEY")
                        settingsLogger.notice("OpenAI API key updated. chars=\(newValue.count, privacy: .public)")
                    }
                    .help("Optional: only required for GPT-4o text polishing.")
            }
            .padding()
            .tabItem { Text("General") }
            
            // Dictionary
            Form {
                Text("Add uncommon names, industry terms, or specific spellings separated by commas.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $engine.customDictionaryStr)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
                    .onChange(of: engine.customDictionaryStr) { _, newValue in
                        let entries = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        settingsLogger.debug("Dictionary updated. entries=\(entries.count, privacy: .public)")
                    }
            }
            .padding()
            .tabItem { Text("Dictionary") }
            
            // Snippets
            Form {
                Text("Format: `cue:template text|cue2:template text 2`. Example: `intro:Hi, thanks for reaching out!`")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $engine.customSnippetsStr)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3))
                    .onChange(of: engine.customSnippetsStr) { _, newValue in
                        let entries = newValue
                            .split(separator: "|")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        settingsLogger.debug("Snippets updated. entries=\(entries.count, privacy: .public)")
                    }
            }
            .padding()
            .tabItem { Text("Snippets") }
            
            // Styles
            Form {
                Picker("Writing Style", selection: $engine.activeStyle) {
                    ForEach(styles, id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
                .onChange(of: engine.activeStyle) { _, style in
                    settingsLogger.notice("Writing style changed: \(style, privacy: .public)")
                }
            }
            .padding()
            .tabItem { Text("Styles") }
        }
        .frame(width: 450, height: 300)
    }
}
