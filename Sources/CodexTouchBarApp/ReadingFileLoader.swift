import CodexTouchBarCore
import Foundation

enum ReadingFileLoaderError: LocalizedError {
    case unreadableText
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "无法按文本读取该文件"
        case .conversionFailed(let detail):
            return detail.isEmpty ? "无法转换该文件" : detail
        }
    }
}

enum ReadingFileLoader {
    static func load(from url: URL) throws -> ReadingDocument {
        let text = ReadingFileSupportPolicy.prefersTextutilConversion(pathExtension: url.pathExtension)
            ? try convertedText(from: url)
            : try directText(from: url) ?? convertedText(from: url)
        let normalized = normalizedText(
            ReadingFileSupportPolicy.usesMarkdownCleanup(pathExtension: url.pathExtension)
                ? ReadingMarkdownTextFormatter.displayText(from: text)
                : text
        )
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let size = values?.fileSize ?? 0
        return ReadingDocument(
            id: "\(url.path)|\(modifiedAt)|\(size)",
            fileURL: url,
            fileName: url.lastPathComponent,
            text: normalized.isEmpty ? "文件为空" : normalized
        )
    }

    private static func directText(from url: URL) throws -> String? {
        var encoding = String.Encoding.utf8
        do {
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
                return nil
            }
            return text
        } catch {
            return nil
        }
    }

    private static func convertedText(from url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw ReadingFileLoaderError.unreadableText
        }
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ReadingFileLoaderError.conversionFailed(detail)
        }

        if let text = String(data: outputData, encoding: .utf8) {
            return text
        }
        if let text = String(data: outputData, encoding: .unicode) {
            return text
        }
        throw ReadingFileLoaderError.unreadableText
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
