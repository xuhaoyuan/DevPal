import SwiftUI

/// A horizontal split view that persists the sidebar width in UserDefaults.
struct PersistentSplitView<Sidebar: View, Content: View>: View {
    let id: String
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let defaultWidth: CGFloat
    let sidebar: () -> Sidebar
    let content: () -> Content

    @State private var sidebarWidth: CGFloat

    init(
        id: String,
        minWidth: CGFloat = 120,
        maxWidth: CGFloat = 300,
        defaultWidth: CGFloat = 150,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.id = id
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.defaultWidth = defaultWidth
        self.sidebar = sidebar
        self.content = content

        let saved = UserDefaults.standard.double(forKey: "splitWidth.\(id)")
        _sidebarWidth = State(initialValue: saved > 0 ? CGFloat(saved) : defaultWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: sidebarWidth)

            // Draggable divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .overlay(
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .cursor(.resizeLeftRight)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let newWidth = sidebarWidth + value.translation.width
                                    sidebarWidth = min(max(newWidth, minWidth), maxWidth)
                                }
                                .onEnded { _ in
                                    UserDefaults.standard.set(Double(sidebarWidth), forKey: "splitWidth.\(id)")
                                }
                        )
                )

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Cursor modifier

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
