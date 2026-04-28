import SwiftUI
import AppKit

/// A read-only NSTextView wrapper for displaying large text content without UI stuttering.
/// SwiftUI's `Text` measures the entire string synchronously, causing freezes with large content.
/// `NSTextView` handles this natively with efficient text layout.
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = font
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.usesFindBar = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            textView.font = font
        }
    }
}
