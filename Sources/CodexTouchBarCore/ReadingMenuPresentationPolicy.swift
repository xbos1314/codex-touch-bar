import Foundation

public struct ReadingMenuPresentation: Equatable {
    public var fileTitle: String
    public var pathTitle: String
    public var progressTitle: String
    public var continueReadingTitle: String
    public var isReadingActive: Bool
    public var canContinueReading: Bool

    public init(
        fileTitle: String,
        pathTitle: String,
        progressTitle: String,
        continueReadingTitle: String,
        isReadingActive: Bool,
        canContinueReading: Bool
    ) {
        self.fileTitle = fileTitle
        self.pathTitle = pathTitle
        self.progressTitle = progressTitle
        self.continueReadingTitle = continueReadingTitle
        self.isReadingActive = isReadingActive
        self.canContinueReading = canContinueReading
    }
}

public enum ReadingMenuPresentationPolicy {
    public static func presentation(
        fileName: String?,
        filePath: String?,
        progressTitle: String,
        continueReadingFileName: String?,
        language: DisplayLanguage = .english
    ) -> ReadingMenuPresentation {
        let normalizedFileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFilePath = filePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContinueFileName = continueReadingFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayFileName = displayValue(normalizedFileName)
        let displayFilePath = displayValue(normalizedFilePath)
        let canContinueReading = normalizedContinueFileName?.isEmpty == false
        return ReadingMenuPresentation(
            fileTitle: language == .english ? "Reading File: \(displayFileName)" : "阅读文件：\(displayFileName)",
            pathTitle: language == .english ? "Reading Path: \(displayFilePath)" : "阅读路径：\(displayFilePath)",
            progressTitle: progressTitle,
            continueReadingTitle: canContinueReading
                ? (language == .english ? "Continue Reading: \(normalizedContinueFileName!)" : "继续阅读：\(normalizedContinueFileName!)")
                : (language == .english ? "Continue Reading" : "继续阅读"),
            isReadingActive: normalizedFileName?.isEmpty == false || normalizedFilePath?.isEmpty == false,
            canContinueReading: canContinueReading
        )
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }
}
