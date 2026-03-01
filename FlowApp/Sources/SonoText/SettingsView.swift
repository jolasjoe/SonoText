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
                    .onChange(of: openAIApiKey) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "OPENAI_API_KEY")
                    }
                    .help("Required for Whisper and GPT-4o processing.")
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
            }
            .padding()
            .tabItem { Text("Styles") }
        }
        .frame(width: 450, height: 300)
    }
}
