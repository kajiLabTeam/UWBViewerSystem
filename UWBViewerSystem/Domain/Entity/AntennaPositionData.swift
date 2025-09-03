import Foundation

// MARK: - アンテナ位置データエンティティ

public struct AntennaPositionData: Identifiable, Codable {
    public let id: String
    public let antennaId: String
    public let antennaName: String
    public let position: Point3D
    public let rotation: Double  // アンテナの向き（度数法）
    public let calibratedAt: Date

    public init(
        id: String = UUID().uuidString, antennaId: String, antennaName: String, position: Point3D,
        rotation: Double = 0.0, calibratedAt: Date = Date()
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.position = position
        self.rotation = rotation
        self.calibratedAt = calibratedAt
    }

    // 旧データとの互換性のための初期化メソッド
    @available(*, deprecated, message: "Use the new initializer with antennaId and antennaName")
    public init(
        id: String = UUID().uuidString, deviceId: String, deviceName: String, realWorldPosition: RealWorldPosition,
        fieldPosition: Point3D, calibratedAt: Date = Date()
    ) {
        self.id = id
        self.antennaId = deviceId
        self.antennaName = deviceName
        self.position = Point3D(x: realWorldPosition.x, y: realWorldPosition.y, z: realWorldPosition.z)
        self.rotation = 0.0
        self.calibratedAt = calibratedAt
    }
}

public struct RealWorldPosition: Codable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SystemActivity: Identifiable, Codable {
    public let id: String
    public let activityType: String  // SwiftDataとの整合性のため
    public let activityDescription: String
    public let timestamp: Date
    public let status: ActivityStatus

    public init(
        id: String = UUID().uuidString, activityType: String, activityDescription: String, timestamp: Date = Date(),
        status: ActivityStatus = .completed
    ) {
        self.id = id
        self.activityType = activityType
        self.activityDescription = activityDescription
        self.timestamp = timestamp
        self.status = status
    }

    // 旧データとの互換性のための初期化メソッド
    @available(*, deprecated, message: "Use the new initializer with activityType string")
    public init(
        id: String = UUID().uuidString, type: ActivityType, description: String, timestamp: Date = Date(),
        status: ActivityStatus = .completed
    ) {
        self.id = id
        self.activityType = type.rawValue
        self.activityDescription = description
        self.timestamp = timestamp
        self.status = status
    }

    public enum ActivityType: String, Codable {
        case connection = "connection"
        case sensing = "sensing"
        case calibration = "calibration"
        case dataTransfer = "data_transfer"
        case configuration = "configuration"
    }

    public enum ActivityStatus: String, Codable {
        case started = "started"
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
}
