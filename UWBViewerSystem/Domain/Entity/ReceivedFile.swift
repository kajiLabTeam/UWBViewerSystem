import Foundation

// MARK: - 受信ファイルエンティティ

public struct ReceivedFile: Identifiable {
    public let id: UUID
    public let fileName: String
    public let fileURL: URL
    public let deviceName: String
    public let receivedAt: Date
    public let fileSize: Int64

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileURL: URL,
        deviceName: String,
        receivedAt: Date,
        fileSize: Int64
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.deviceName = deviceName
        self.receivedAt = receivedAt
        self.fileSize = fileSize
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self.fileSize)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: self.receivedAt)
    }
}
