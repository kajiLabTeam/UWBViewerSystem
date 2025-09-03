import Foundation

// MARK: - 受信ファイルエンティティ

public struct ReceivedFile: Identifiable {
    public let id = UUID()
    public let fileName: String
    public let fileURL: URL
    public let deviceName: String
    public let receivedAt: Date
    public let fileSize: Int64
    
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: receivedAt)
    }
}