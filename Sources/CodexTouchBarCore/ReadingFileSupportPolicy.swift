import Foundation

public enum ReadingFileSupportPolicy {
    private static let textutilExtensions: Set<String> = [
        "doc",
        "docx",
        "odt",
        "rtf",
        "rtfd"
    ]
    private static let markdownExtensions: Set<String> = [
        "md",
        "markdown",
        "mdown",
        "mkd"
    ]

    public static func prefersTextutilConversion(pathExtension: String) -> Bool {
        textutilExtensions.contains(pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func usesMarkdownCleanup(pathExtension: String) -> Bool {
        markdownExtensions.contains(pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
