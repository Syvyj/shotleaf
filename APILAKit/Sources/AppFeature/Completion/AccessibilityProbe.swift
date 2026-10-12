import AppKit
import ApplicationServices

/// Developer run: `APILA --ax-probe <out>` (launched with `open -g`, so focus
/// stays where it is). Read-only: reports what the frontmost app's focused
/// field tells Accessibility — role, text, selection, caret bounds — to see
/// why inline completion does or doesn't work there. Types nothing.
@MainActor
public enum AccessibilityProbe {
    public static func run(out: URL) async {
        try? await Task.sleep(for: .seconds(1))
        var lines: [String] = []
        func line(_ s: String) { lines.append(s) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        line("app: \(app.localizedName ?? "?") \(app.bundleIdentifier ?? "?") trusted: \(AXIsProcessTrusted())")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            line("set \(name): \(AXUIElementSetAttributeValue(appElement, name as CFString, kCFBooleanTrue).rawValue)")
        }
        try? await Task.sleep(for: .milliseconds(500)) // let Chromium build its tree
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        line("focused element: error \(focusedError.rawValue)")
        guard let focusedRef else { return write(lines, out) }
        let element = focusedRef as! AXUIElement
        func attribute(_ name: String) -> (AXError, CFTypeRef?) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (error, value)
        }
        for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXRoleDescriptionAttribute] {
            line("\(name): \(attribute(name).1.map { "\($0)" } ?? "—")")
        }
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        line("attributes: \((names as? [String])?.joined(separator: ", ") ?? "—")")
        var parameterized: CFArray?
        AXUIElementCopyParameterizedAttributeNames(element, &parameterized)
        line("parameterized: \((parameterized as? [String])?.joined(separator: ", ") ?? "—")")
        var settable: DarwinBoolean = false
        line("value settable: \(AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable).rawValue) \(settable.boolValue)")
        let (valueError, value) = attribute(kAXValueAttribute)
        line("value: error \(valueError.rawValue), \((value as? String).map { "\($0.count) chars" } ?? "not a string")")
        let (rangeError, rangeRef) = attribute(kAXSelectedTextRangeAttribute)
        var range = CFRange()
        if let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() { AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) }
        line("selected range: error \(rangeError.rawValue), \(range.location)+\(range.length)")
        for (label, location, length) in [("char before caret", range.location - 1, 1), ("caret (empty)", range.location, 0)] {
            var r = CFRange(location: max(location, 0), length: length)
            var bounds: CFTypeRef?
            let error = AXValueCreate(.cfRange, &r).map {
                AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, $0, &bounds)
            }
            var rect = CGRect.zero
            if let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() { AXValueGetValue(bounds as! AXValue, .cgRect, &rect) }
            line("bounds for \(label): error \(error?.rawValue ?? -1), \(rect)")
        }
        let (_, position) = attribute(kAXPositionAttribute)
        let (_, size) = attribute(kAXSizeAttribute)
        line("frame: \(position.map { "\($0)" } ?? "—") \(size.map { "\($0)" } ?? "—")")
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        line("Shotleaf reads it as: \(FocusedField.current(excluding: [], screenTop: top).map { "ok, caret \($0.caret)" } ?? "nil — no completion here")")
        write(lines, out)
    }

    /// `--ax-watch <out> <seconds>`: for a while, one line per app/field the
    /// user types in — can APILA read the text and find the caret there?
    /// Read-only; the text itself is never logged, only its length.
    public static func watch(out: URL, seconds: Double) async {
        var seen: [String: String] = [:]
        let end = Date().addingTimeInterval(seconds)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        while Date() < end {
            if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                let system = AXUIElementCreateSystemWide()
                var focused: CFTypeRef?
                AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
                var summary = "no focused element"
                if let focused {
                    let element = focused as! AXUIElement
                    var role: CFTypeRef?, value: CFTypeRef?, rangeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                    AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
                    var range = CFRange()
                    if let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() { AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) }
                    var bounds = CGRect.zero
                    if range.location > 0 {
                        var r = CFRange(location: range.location - 1, length: 1)
                        var b: CFTypeRef?
                        if let q = AXValueCreate(.cfRange, &r),
                           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, q, &b) == .success,
                           let b, CFGetTypeID(b) == AXValueGetTypeID() { AXValueGetValue(b as! AXValue, .cgRect, &bounds) }
                    }
                    let field = FocusedField.current(excluding: [], screenTop: top)
                    summary = "\(role as? String ?? "?") text \((value as? String)?.count ?? -1) chars, cursor \(range.location)+\(range.length), "
                        + "caret box \(Int(bounds.width))×\(Int(bounds.height)) → Shotleaf: \(field == nil ? "NO" : "ok")"
                    if field == nil, (value as? String).map({ $0.count <= 1 }) ?? true { summary += "  [markers: " + FocusedField.markerDiagnosis(element) + "]" }
                }
                let key = app.bundleIdentifier ?? "?"
                // One line per app: only when "can APILA work here" changes, not per keystroke.
                let state = summary.contains("Shotleaf: ok") ? "ok"
                    : summary.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression)
                if seen[key] != state {
                    seen[key] = state
                    let stamp = Date().formatted(date: .omitted, time: .standard)
                    let line = "\(stamp)  \(app.localizedName ?? key) (\(key)): \(summary)\n"
                    if let handle = try? FileHandle(forWritingTo: out.appendingPathComponent("ax-watch.txt")) {
                        handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
                    } else {
                        try? line.write(to: out.appendingPathComponent("ax-watch.txt"), atomically: true, encoding: .utf8)
                    }
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func write(_ lines: [String], _ out: URL) {
        try? lines.joined(separator: "\n").write(to: out.appendingPathComponent("ax-probe.txt"), atomically: true, encoding: .utf8)
    }
}
