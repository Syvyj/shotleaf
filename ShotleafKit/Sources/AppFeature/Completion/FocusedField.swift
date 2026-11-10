import AppKit
import ApplicationServices

/// The text field that has the keyboard, read through Accessibility.
/// Immutable; the AX element is a CF reference, safe to pass between threads.
struct FocusedField: @unchecked Sendable {
    let element: AXUIElement
    let beforeCursor: String
    /// The character before the caret, in AppKit screen coordinates.
    let caret: CGRect
    /// The field's right edge (screen x): suggestions stop there.
    let rightEdge: CGFloat
    let pid: pid_t
    let bundleID: String
    let appName: String?
    let windowTitle: String
    /// The rest of the line after the cursor ("" at the end of a line).
    let afterCursor: String
    /// How it was read: "value" or "markers" (for the log).
    let via: String
    /// The raw caret box from Accessibility (top-left coordinates, for the log).
    let axCaret: CGRect

    /// nil when there's no editable, non-secure field with an empty selection
    /// (or the app is excluded / Shotleaf itself).
    /// Safe off the main thread; `screenTop` is the main screen's top (AppKit).
    static func current(excluding excluded: Set<String>, screenTop top: CGFloat) -> FocusedField? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2) // a hung app must not freeze typing
        guard let element: AXUIElement = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              !excluded.contains(app.bundleIdentifier ?? "")
        else { return nil }
        if let subrole: String = attribute(element, kAXSubroleAttribute), subrole == kAXSecureTextFieldSubrole { return nil }
        // Plain fields (Cocoa, Qt…) expose their text as a value; web editors
        // (Chromium, Electron — Claude, Slack, Notion) only through text markers.
        let byValue = viaValue(element)
        guard let read = byValue ?? viaTextMarkers(element) else { return nil }
        let bounds = read.caret
        // AX uses top-left global coordinates; AppKit — bottom-left of the main screen.
        let caret = CGRect(x: bounds.minX, y: top - bounds.maxY, width: bounds.width, height: bounds.height)
        var rightEdge = caret.maxX + 600
        if let position: AXValue = attribute(element, kAXPositionAttribute), let size: AXValue = attribute(element, kAXSizeAttribute) {
            var origin = CGPoint.zero, extent = CGSize.zero
            if AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent), extent.width > 0 {
                rightEdge = origin.x + extent.width
            }
        }
        var title = ""
        if let window: AXUIElement = attribute(element, kAXWindowAttribute), let t: String = attribute(window, kAXTitleAttribute) { title = t }
        return FocusedField(element: element, beforeCursor: read.before, caret: caret, rightEdge: rightEdge,
                            pid: pid, bundleID: app.bundleIdentifier ?? "", appName: app.localizedName, windowTitle: title,
                            afterCursor: read.after, via: byValue != nil ? "value" : "markers", axCaret: bounds)
    }

    /// Text before / after the cursor (rest of the line) and the box of the
    /// character before it (AX coordinates).
    private typealias Read = (before: String, after: String, caret: CGRect)

    /// The field's value and selected range, and the bounds of a character range.
    private static func viaValue(_ element: AXUIElement) -> Read? {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
              let value: String = attribute(element, kAXValueAttribute),
              let rangeValue: AXValue = attribute(element, kAXSelectedTextRangeAttribute)
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length == 0, range.location > 0 else { return nil }
        let text = value as NSString
        guard range.location <= text.length else { return nil }
        var charRange = CFRange(location: range.location - 1, length: 1)
        guard let query = AXValueCreate(.cfRange, &charRange),
              let bounds = rect(parameterized(element, kAXBoundsForRangeParameterizedAttribute, query)), bounds.height > 2
        else { return nil }
        let rest = text.substring(from: range.location)
        return (text.substring(to: range.location), CompletionText.restOfLine(rest), bounds)
    }

    /// Web editors: the selection as a text-marker range, the text from the
    /// start to it, and the bounds of the character just before it.
    private static func viaTextMarkers(_ element: AXUIElement) -> Read? {
        guard let selection = marker(element, "AXSelectedTextMarkerRange", AXTextMarkerRangeGetTypeID()).map({ $0 as! AXTextMarkerRange }),
              let start = marker(element, "AXStartTextMarker", AXTextMarkerGetTypeID()).map({ $0 as! AXTextMarker }),
              let end = marker(element, "AXEndTextMarker", AXTextMarkerGetTypeID()).map({ $0 as! AXTextMarker })
        else { return nil }
        let caretStart = AXTextMarkerRangeCopyStartMarker(selection)
        let caretEnd = AXTextMarkerRangeCopyEndMarker(selection)
        func string(_ from: AXTextMarker, _ to: AXTextMarker) -> String? {
            parameterized(element, "AXStringForTextMarkerRange", AXTextMarkerRangeCreate(nil, from, to)) as? String
        }
        guard string(caretStart, caretEnd)?.isEmpty != false, // no selection, just a cursor
              let before = string(start, caretStart), !before.isEmpty,
              let previousRef = parameterized(element, "AXPreviousTextMarkerForTextMarker", caretStart),
              CFGetTypeID(previousRef) == AXTextMarkerGetTypeID()
        else { return nil }
        let previous = previousRef as! AXTextMarker
        guard let bounds = rect(parameterized(element, "AXBoundsForTextMarkerRange", AXTextMarkerRangeCreate(nil, previous, caretStart))),
              bounds.height > 2
        else { return nil }
        let after = string(caretEnd, end) ?? ""
        return (before, CompletionText.restOfLine(after), bounds)
    }

    /// For the AX watch: each step of the text-marker read on `element` and
    /// its editable ancestors / web area — where does it stop?
    static func markerDiagnosis(_ element: AXUIElement) -> String {
        var candidates: [(String, AXUIElement)] = [("focused", element)]
        for name in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
            if let e: AXUIElement = attribute(element, name) { candidates.append((name, e)) }
        }
        var walker: AXUIElement? = element
        for _ in 0..<30 {
            guard let current = walker else { break }
            if let role: String = attribute(current, kAXRoleAttribute), role == "AXWebArea" { candidates.append(("web area", current)); break }
            walker = attribute(current, kAXParentAttribute)
        }
        return candidates.map { label, e in
            let selection = marker(e, "AXSelectedTextMarkerRange", AXTextMarkerRangeGetTypeID())
            let start = marker(e, "AXStartTextMarker", AXTextMarkerGetTypeID())
            var parts = ["\(label): selection \(selection != nil), start \(start != nil)"]
            if let selection, let start {
                let caret = AXTextMarkerRangeCopyStartMarker(selection as! AXTextMarkerRange)
                let before = parameterized(e, "AXStringForTextMarkerRange", AXTextMarkerRangeCreate(nil, start as! AXTextMarker, caret)) as? String
                parts.append("before \(before?.count ?? -1) chars")
                if let previous = parameterized(e, "AXPreviousTextMarkerForTextMarker", caret), CFGetTypeID(previous) == AXTextMarkerGetTypeID() {
                    let bounds = rect(parameterized(e, "AXBoundsForTextMarkerRange", AXTextMarkerRangeCreate(nil, previous as! AXTextMarker, caret)))
                    parts.append("caret box \(bounds.map { "\(Int($0.width))×\(Int($0.height))" } ?? "none")")
                } else {
                    parts.append("no previous marker")
                }
            }
            return parts.joined(separator: ", ")
        }.joined(separator: " | ")
    }

    private static func marker(_ element: AXUIElement, _ name: String, _ type: CFTypeID) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value, CFGetTypeID(value) == type
        else { return nil }
        return value
    }

    private static func parameterized(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else { return nil }
        return value
    }

    private static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
