import Cocoa
import CoreGraphics

class KeystrokeSynthesizer {
    static let shared = KeystrokeSynthesizer()
    
    var isAccessibilityGranted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let granted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        keystrokeLogger.debug("Accessibility check: granted=\(granted, privacy: .public)")
        return granted
    }
    
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        keystrokeLogger.notice("Requested Accessibility permission prompt")
    }
    
    func copySelectedText() -> String? {
        let pb = NSPasteboard.general
        let prevCount = pb.changeCount
        keystrokeLogger.debug("Copy selected text requested")
        
        simulateKeystroke(keyCode: 8, usingCommand: true)
        Thread.sleep(forTimeInterval: 0.15)
        
        if pb.changeCount > prevCount {
            let copied = pb.string(forType: .string)
            keystrokeLogger.debug("Copy detected clipboard change. chars=\(copied?.count ?? 0, privacy: .public)")
            return copied
        }
        keystrokeLogger.debug("Copy found no new clipboard content")
        return nil
    }
    
    func pasteText(_ text: String, afterDelay delay: TimeInterval = 0.4) {
        // Set clipboard immediately
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        keystrokeLogger.debug("Paste text staged. chars=\(text.count, privacy: .public) delay=\(delay, format: .fixed(precision: 2))s")
        
        // Delay allows the previous app to regain focus before we simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.simulateKeystroke(keyCode: 9, usingCommand: true)
            keystrokeLogger.notice("Paste keystroke sent")
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
        keystrokeLogger.debug("Posted keystroke keyCode=\(keyCode, privacy: .public) cmd=\(usingCommand, privacy: .public)")
    }
}
