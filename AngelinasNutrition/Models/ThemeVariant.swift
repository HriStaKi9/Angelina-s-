import Foundation

/// The two looks of the app: Rose (the original) and Steel (cooler slate and blue).
enum ThemeVariant: String, Codable, CaseIterable, Identifiable {
    case rose, steel

    var id: String { rawValue }

    /// Read by every themed color at draw time; RootView rebuilds the view tree when it changes.
    nonisolated(unsafe) static var current: ThemeVariant = .rose
}
