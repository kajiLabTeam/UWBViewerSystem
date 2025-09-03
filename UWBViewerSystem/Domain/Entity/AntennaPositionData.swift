import Foundation

// MARK: - アンテナ位置データエンティティ

public struct AntennaPositionData: Identifiable, Codable {
    public let id: String
    public let deviceId: String
    public let deviceName: String
    public let realWorldPosition: RealWorldPosition
    public let fieldPosition: Point3D
    public let calibratedAt: Date
    
    public init(id: String = UUID().uuidString, deviceId: String, deviceName: String, realWorldPosition: RealWorldPosition, fieldPosition: Point3D, calibratedAt: Date = Date()) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.realWorldPosition = realWorldPosition
        self.fieldPosition = fieldPosition
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
    public let type: ActivityType
    public let description: String
    public let timestamp: Date
    public let status: ActivityStatus
    
    public init(id: String = UUID().uuidString, type: ActivityType, description: String, timestamp: Date = Date(), status: ActivityStatus = .completed) {
        self.id = id
        self.type = type
        self.description = description
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