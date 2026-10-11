import SwiftUI
import AppKit

/// macOS owns semantic colors and accessibility adaptations, not a fixed palette.
struct FrameletTheme {
    let dark: Bool // Kept for source compatibility; effective appearance is system-owned.
    var surface: Color {Color(nsColor:.windowBackgroundColor)}
    var canvas: Color {Color(nsColor:.underPageBackgroundColor)}
    var inset: Color {Color(nsColor:.controlBackgroundColor)}
    var accent: Color {Color.accentColor}
    var primaryFill: Color {Color.accentColor}
    var line: Color {Color(nsColor:.separatorColor)}
}
