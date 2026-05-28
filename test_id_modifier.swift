// Just a mental check. In SwiftUI, .id() is usually used for ScrollViewReader,
// but it DOES NOT stop the view from re-rendering if its properties change.
// However, if the struct is Equatable, it might skip. MessageBubble is not Equatable.
