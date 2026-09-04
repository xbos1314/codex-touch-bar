import Foundation

public enum PrivateTouchBarPresentationSurface: Equatable, Sendable {
    case systemModal
    case controlStripEntry
}

public enum PrivateTouchBarPresentationPolicy {
    public static let surface: PrivateTouchBarPresentationSurface = .controlStripEntry
    public static let controlStripEntryIsBordered = false
    public static let controlStripEntryDrawsBackground = true
    public static let controlStripEntryCornerRadius: Double = 0
    public static let controlStripEntryUsesNativeButtonActivation = true
    public static let showsCloseButton = false
    public static let reappliesCloseButtonPolicyAfterPresent = true
}
