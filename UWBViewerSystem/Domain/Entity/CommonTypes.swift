import Foundation
import SwiftUI

// MARK: - 基本的な幾何学データ型

/// 3Dポイントを表すデータ構造
public struct Point3D: Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double  
    public let z: Double
    
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /// CGPointから2D情報を使って3Dポイントを作成
    public init(cgPoint: CGPoint, z: Double = 0.0) {
        self.x = Double(cgPoint.x)
        self.y = Double(cgPoint.y)
        self.z = z
    }
    
    /// CGPointに変換
    public var cgPoint: CGPoint {
        return CGPoint(x: x, y: y)
    }
    
    public static let zero = Point3D(x: 0, y: 0, z: 0)
}

// MARK: - アンテナ情報

/// アンテナ情報を表すデータ構造
public struct AntennaInfo: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let coordinates: Point3D
    public var rotation: Double = 0.0
    public var isActive: Bool = false
    
    public init(id: String, name: String, coordinates: Point3D, rotation: Double = 0.0, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.rotation = rotation
        self.isActive = isActive
    }
}

// MARK: - システム活動記録

/// システムの活動を記録するためのデータ構造
public struct SystemActivity: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let activityType: String
    public let activityDescription: String
    public let status: ActivityStatus
    public var additionalData: [String: String]?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        activityType: String,
        activityDescription: String,
        status: ActivityStatus = .completed,
        additionalData: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.activityType = activityType
        self.activityDescription = activityDescription
        self.status = status
        self.additionalData = additionalData
    }
}

// MARK: - Activity 関連のenum

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

// MARK: - システムキャリブレーション

/// システムキャリブレーションの結果
public struct SystemCalibrationResult: Codable {
    public let timestamp: Date
    public let wasSuccessful: Bool
    public let calibrationData: [String: Double]
    public let errorMessage: String?
    
    public init(
        timestamp: Date = Date(),
        wasSuccessful: Bool,
        calibrationData: [String: Double] = [:],
        errorMessage: String? = nil
    ) {
        self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful
        self.calibrationData = calibrationData
        self.errorMessage = errorMessage
    }
}

// MARK: - フロアマップ情報

/// フロアマップの基本情報
public struct FloorMapInfo: Codable, Identifiable {
    public let id: String
    public let name: String
    public let buildingName: String
    public let width: Double
    public let depth: Double
    public let createdAt: Date
    
    #if os(iOS)
    public var image: UIImage?
    #elseif os(macOS)
    public var image: NSImage?
    #endif
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        buildingName: String,
        width: Double,
        depth: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.buildingName = buildingName
        self.width = width
        self.depth = depth
        self.createdAt = createdAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, buildingName, width, depth, createdAt
    }
}

// MARK: - 実世界位置

/// 実世界での位置情報
public struct RealWorldPosition: Codable, Equatable {
    public let x: Double  // メートル
    public let y: Double  // メートル
    public let z: Double  // メートル
    
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y  
        self.z = z
    }
    
    public static let zero = RealWorldPosition(x: 0, y: 0, z: 0)
}

// MARK: - デバイス情報

/// デバイスの基本情報
public struct DeviceInfo: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let deviceType: String
    public var isConnected: Bool
    public var lastSeen: Date?
    
    public init(
        id: String,
        name: String,
        deviceType: String = "Android",
        isConnected: Bool = false,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.isConnected = isConnected
        self.lastSeen = lastSeen
    }
}

// MARK: - 接続済みデバイス情報

/// 接続済み端末の情報
public struct ConnectedDevice: Identifiable, Equatable {
    public let id = UUID()
    public let endpointId: String
    public let deviceName: String
    public let connectTime: Date
    public var lastMessageTime: Date?
    public var isActive: Bool = true

    public init(
        endpointId: String,
        deviceName: String,
        connectTime: Date = Date(),
        lastMessageTime: Date? = nil,
        isActive: Bool = true
    ) {
        self.endpointId = endpointId
        self.deviceName = deviceName
        self.connectTime = connectTime
        self.lastMessageTime = lastMessageTime
        self.isActive = isActive
    }

    public static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
        return lhs.id == rhs.id && lhs.endpointId == rhs.endpointId && lhs.deviceName == rhs.deviceName
            && lhs.connectTime == rhs.connectTime && lhs.lastMessageTime == rhs.lastMessageTime
            && lhs.isActive == rhs.isActive
    }
}

// MARK: - Nearby Connections 関連

/// 接続要求の情報  
public struct ConnectionRequest: Identifiable, Equatable {
    public let id = UUID()
    public let endpointId: String
    public let deviceName: String
    public let timestamp: Date
    public let context: Data
    public let responseHandler: (Bool) -> Void

    public init(
        endpointId: String,
        deviceName: String,
        timestamp: Date = Date(),
        context: Data,
        responseHandler: @escaping (Bool) -> Void
    ) {
        self.endpointId = endpointId
        self.deviceName = deviceName
        self.timestamp = timestamp
        self.context = context
        self.responseHandler = responseHandler
    }
    
    public static func == (lhs: ConnectionRequest, rhs: ConnectionRequest) -> Bool {
        return lhs.id == rhs.id && 
               lhs.endpointId == rhs.endpointId && 
               lhs.deviceName == rhs.deviceName && 
               lhs.timestamp == rhs.timestamp && 
               lhs.context == rhs.context
        // responseHandlerは関数なので比較から除外
    }
}

/// メッセージ情報
public struct Message: Identifiable {
    public let id = UUID()
    public let content: String
    public let timestamp: Date
    public let senderId: String
    public let senderName: String
    public let isOutgoing: Bool

    public init(
        content: String,
        timestamp: Date = Date(),
        senderId: String,
        senderName: String,
        isOutgoing: Bool
    ) {
        self.content = content
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
        self.isOutgoing = isOutgoing
    }
}