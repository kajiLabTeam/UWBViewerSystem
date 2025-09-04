import Foundation
import SwiftData

// MARK: - 受信ファイルの永続化モデル

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentReceivedFile {
    @Attribute(.unique) public var id: UUID
    public var fileName: String
    public var fileURLString: String
    public var deviceName: String
    public var receivedAt: Date
    public var fileSize: Int64

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileURLString: String,
        deviceName: String,
        receivedAt: Date,
        fileSize: Int64
    ) {
        self.id = id
        self.fileName = fileName
        self.fileURLString = fileURLString
        self.deviceName = deviceName
        self.receivedAt = receivedAt
        self.fileSize = fileSize
    }

    // MARK: - 変換メソッド

    public func toEntity() -> ReceivedFile {
        return ReceivedFile(
            id: id,
            fileName: fileName,
            fileURL: URL(fileURLWithPath: fileURLString),
            deviceName: deviceName,
            receivedAt: receivedAt,
            fileSize: fileSize
        )
    }
}

// MARK: - ReceivedFileの拡張

extension ReceivedFile {
    public func toPersistent() -> PersistentReceivedFile {
        return PersistentReceivedFile(
            id: id,
            fileName: fileName,
            fileURLString: fileURL.path,
            deviceName: deviceName,
            receivedAt: receivedAt,
            fileSize: fileSize
        )
    }
}
