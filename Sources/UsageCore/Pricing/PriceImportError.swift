import Foundation

/// Why an import, a removal or an export failed. `description` is the
/// user-facing reason shown in the preview sheet or an alert (FR-024).
public enum PriceImportError: Error, Equatable, CustomStringConvertible {
    case network(String)
    case httpStatus(Int)
    case timeout
    case tooLarge
    case notJSON
    case noUsableEntries(ImportKind)
    case missingHeader
    case missingColumns([String])
    case noValidRows
    case unreadableFile(String)
    case saveFailed(String)

    public var description: String {
        switch self {
        case .network(let reason):
            return "The price list could not be downloaded: \(reason)"
        case .httpStatus(let code):
            return "The price list server answered with HTTP \(code)."
        case .timeout:
            return "The price list download timed out after 30 seconds."
        case .tooLarge:
            return "The price list is larger than 20 MB and was not imported."
        case .notJSON:
            return "The price list is not a JSON object."
        case .noUsableEntries(let kind):
            return "The price list has no usable \(kind.displayName) prices."
        case .missingHeader:
            return "Missing header: the file is empty or has no header row."
        case .missingColumns(let columns):
            return "Missing columns: \(columns.joined(separator: ", "))."
        case .noValidRows:
            return "The file has no valid rows."
        case .unreadableFile(let reason):
            return "The file could not be read: \(reason)"
        case .saveFailed(let reason):
            return "The imported prices could not be saved: \(reason)"
        }
    }
}
