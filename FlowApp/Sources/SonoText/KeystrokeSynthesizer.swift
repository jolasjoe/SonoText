import Cocoa
import CoreGraphics

class KeystrokeSynthesizer {
    static let shared = KeystrokeSynthesizer()
    
    var isAccessibilityGranted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func copySelectedText() -> String? {
        let pb = NSPasteboard.general
        let prevCount = pb.changeCount
        
        simulateKeystroke(keyCode: 8, usingCommand: true)
        Thread.sleep(forTimeInterval: 0.15)
        
        if pb.changeCount > prevCount {
            return pb.string(forType: .string)
        }
        return nil
    }
    
    func pasteText(_ text: String, afterDelay delay: TimeInterval = 0.4) {
        // Set clipboard immediately
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        
        // Delay allows the previous app to regain focus before we simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.simulateKeystroke(keyCode: 9, usingCommand: true)
            logger.notice("🟢 Paste keystroke sent (delay: \(delay)s)")
        }
    }
    
    private func simulateKeystroke(keyCode: CGKeyCode, usingCommand: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        if usingCommand {
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
        }
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
