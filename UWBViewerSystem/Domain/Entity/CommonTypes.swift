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
        x = Double(cgPoint.x)
        y = Double(cgPoint.y)
        self.z = z
    }

    /// CGPointに変換
    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
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

// MARK: - フロアマップ情報

/// フロアマップ情報を表すデータ構造
public struct FloorMapInfo: Codable {
    public let id: String
    public let name: String
    public let buildingName: String
    public let width: Double
    public let depth: Double
    public let createdAt: Date

    // imageプロパティはCodableに含めない（ファイルシステムに別途保存）

    public init(id: String, name: String, buildingName: String, width: Double, depth: Double, createdAt: Date) {
        self.id = id
        self.name = name
        self.buildingName = buildingName
        self.width = width
        self.depth = depth
        self.createdAt = createdAt
    }

    // アスペクト比を計算
    public var aspectRatio: Double {
        depth > 0 ? width / depth : 1.0
    }
}

// MARK: - プロジェクト進行状況管理

/// セットアップフローのステップを定義
public enum SetupStep: String, Codable, CaseIterable {
    case floorMapSetting = "floor_map_setting"  // フロアマップ設定
    case antennaConfiguration = "antenna_configuration"  // アンテナ配置
    case devicePairing = "device_pairing"  // デバイスペアリング
    case dataCollection = "data_collection"  // データ収集
    case completed = "completed"  // 完了

    public var displayName: String {
        switch self {
        case .floorMapSetting:
            return "フロアマップ設定"
        case .antennaConfiguration:
            return "アンテナ配置"
        case .devicePairing:
            return "デバイスペアリング"
        case .dataCollection:
            return "データ収集"
        case .completed:
            return "完了"
        }
    }

    public var order: Int {
        switch self {
        case .floorMapSetting: return 1
        case .antennaConfiguration: return 2
        case .devicePairing: return 3
        case .dataCollection: return 4
        case .completed: return 5
        }
    }
}

/// プロジェクトの進行状況を表すデータ構造
public struct ProjectProgress: Codable {
    public let id: String
    public let floorMapId: String
    public var currentStep: SetupStep
    public var completedSteps: Set<SetupStep>
    public var stepData: [String: Data]  // 各ステップの詳細データ
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        floorMapId: String,
        currentStep: SetupStep = .floorMapSetting,
        completedSteps: Set<SetupStep> = [],
        stepData: [String: Data] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.floorMapId = floorMapId
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.stepData = stepData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var completionPercentage: Double {
        let totalSteps = SetupStep.allCases.count - 1  // completedを除く
        let completed = completedSteps.filter { $0 != .completed }.count
        return Double(completed) / Double(totalSteps)
    }

    public var isCompleted: Bool {
        currentStep == .completed
    }
}

// FloorMapInfo用のプラットフォーム固有拡張
#if os(macOS)
    extension FloorMapInfo {
        public var image: NSImage? {
            get {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let imageURL = documentsDirectory.appendingPathComponent("\(id).jpg")
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    return NSImage(contentsOf: imageURL)
                }
                return nil
            }
            set {
                // 画像の設定は別のメソッドで処理
            }
        }
    }
#elseif os(iOS)
    extension FloorMapInfo {
        public var image: UIImage? {
            get {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let imageURL = documentsDirectory.appendingPathComponent("\(id).jpg")
                if FileManager.default.fileExists(atPath: imageURL.path),
                   let data = try? Data(contentsOf: imageURL)
                {
                    return UIImage(data: data)
                }
                return nil
            }
            set {
                // 画像の設定は別のメソッドで処理
            }
        }
    }
#endif

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
        lhs.id == rhs.id && lhs.endpointId == rhs.endpointId && lhs.deviceName == rhs.deviceName
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
        lhs.id == rhs.id && lhs.endpointId == rhs.endpointId && lhs.deviceName == rhs.deviceName
            && lhs.timestamp == rhs.timestamp && lhs.context == rhs.context
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

// MARK: - キャリブレーション関連

/// キャリブレーション用の測定点データ
public struct CalibrationPoint: Codable, Identifiable, Equatable {
    public let id: String
    public let referencePosition: Point3D  // 正解座標（実際の位置）
    public let measuredPosition: Point3D  // 測定座標（センサーが測定した位置）
    public let timestamp: Date
    public let antennaId: String

    public init(
        id: String = UUID().uuidString,
        referencePosition: Point3D,
        measuredPosition: Point3D,
        timestamp: Date = Date(),
        antennaId: String
    ) {
        self.id = id
        self.referencePosition = referencePosition
        self.measuredPosition = measuredPosition
        self.timestamp = timestamp
        self.antennaId = antennaId
    }
}

/// キャリブレーション変換行列データ
public struct CalibrationTransform: Codable, Equatable {
    /// 平行移動ベクトル
    public let translation: Point3D
    /// 回転角度（ラジアン）
    public let rotation: Double
    /// スケール係数
    public let scale: Point3D
    /// 変換行列作成時刻
    public let timestamp: Date
    /// 変換精度（RMSE）
    public let accuracy: Double

    public init(
        translation: Point3D,
        rotation: Double,
        scale: Point3D,
        timestamp: Date = Date(),
        accuracy: Double
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
        self.timestamp = timestamp
        self.accuracy = accuracy
    }

    public static let identity = CalibrationTransform(
        translation: .zero,
        rotation: 0.0,
        scale: Point3D(x: 1.0, y: 1.0, z: 1.0),
        accuracy: 0.0
    )
}

/// アンテナごとのキャリブレーションデータ
public struct CalibrationData: Codable, Identifiable, Equatable {
    public let id: String
    public let antennaId: String
    public var calibrationPoints: [CalibrationPoint]
    public var transform: CalibrationTransform?
    public let createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        calibrationPoints: [CalibrationPoint] = [],
        transform: CalibrationTransform? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.antennaId = antennaId
        self.calibrationPoints = calibrationPoints
        self.transform = transform
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }

    /// キャリブレーション完了しているか
    public var isCalibrated: Bool {
        transform != nil && calibrationPoints.count >= 3
    }

    /// キャリブレーション精度を取得
    public var accuracy: Double? {
        transform?.accuracy
    }
}

/// キャリブレーション処理の結果
public struct CalibrationResult: Codable {
    public let success: Bool
    public let transform: CalibrationTransform?
    public let errorMessage: String?
    public let processedPoints: [CalibrationPoint]
    public let timestamp: Date

    public init(
        success: Bool,
        transform: CalibrationTransform? = nil,
        errorMessage: String? = nil,
        processedPoints: [CalibrationPoint] = [],
        timestamp: Date = Date()
    ) {
        self.success = success
        self.transform = transform
        self.errorMessage = errorMessage
        self.processedPoints = processedPoints
        self.timestamp = timestamp
    }
}

/// キャリブレーション状態を表す列挙型
public enum CalibrationStatus: String, Codable, CaseIterable {
    case notStarted = "not_started"  // 未開始
    case collecting = "collecting"  // データ収集中
    case calculating = "calculating"  // 計算中
    case completed = "completed"  // 完了
    case failed = "failed"  // 失敗

    public var displayName: String {
        switch self {
        case .notStarted:
            return "未開始"
        case .collecting:
            return "データ収集中"
        case .calculating:
            return "計算中"
        case .completed:
            return "完了"
        case .failed:
            return "失敗"
        }
    }
}

/// マップベースキャリブレーション用のデータ点
public struct MapCalibrationPoint: Codable, Identifiable, Equatable {
    public let id: String
    public let mapCoordinate: Point3D  // マップ上の座標（ピクセル座標系）
    public let realWorldCoordinate: Point3D  // 実世界座標（メートル）
    public let antennaId: String
    public let timestamp: Date
    public let pointIndex: Int  // 基準点のインデックス（1-3）

    public init(
        id: String = UUID().uuidString,
        mapCoordinate: Point3D,
        realWorldCoordinate: Point3D,
        antennaId: String,
        timestamp: Date = Date(),
        pointIndex: Int
    ) {
        self.id = id
        self.mapCoordinate = mapCoordinate
        self.realWorldCoordinate = realWorldCoordinate
        self.antennaId = antennaId
        self.timestamp = timestamp
        self.pointIndex = pointIndex
    }
}

/// アフィン変換行列構造体
public struct AffineTransformMatrix: Codable, Equatable {
    /// 2D変換行列 (3x3行列の上2行を表現)
    /// [a c tx]
    /// [b d ty]
    /// [0 0  1]
    public let a: Double  // X軸スケール・X軸回転成分
    public let b: Double  // Y軸回転成分
    public let c: Double  // X軸回転成分
    public let d: Double  // Y軸スケール・Y軸回転成分
    public let tx: Double  // X軸平行移動
    public let ty: Double  // Y軸平行移動

    /// Z軸変換（3D用）
    public let scaleZ: Double
    public let translateZ: Double

    /// 変換精度
    public let accuracy: Double
    public let timestamp: Date

    public init(
        a: Double, b: Double, c: Double, d: Double,
        tx: Double, ty: Double,
        scaleZ: Double = 1.0, translateZ: Double = 0.0,
        accuracy: Double = 0.0,
        timestamp: Date = Date()
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
        self.scaleZ = scaleZ
        self.translateZ = translateZ
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    /// 単位行列
    public static let identity = AffineTransformMatrix(
        a: 1.0, b: 0.0, c: 0.0, d: 1.0,
        tx: 0.0, ty: 0.0
    )

    /// 行列の行列式（スケール成分の確認用）
    public var determinant: Double {
        a * d - b * c
    }

    /// 変換が有効かチェック
    public var isValid: Bool {
        abs(determinant) > 1e-10 && [a, b, c, d, tx, ty, scaleZ, translateZ].allSatisfy { $0.isFinite }
    }
}

/// マップベースキャリブレーションデータ
public struct MapCalibrationData: Codable, Identifiable, Equatable {
    public let id: String
    public let antennaId: String
    public let floorMapId: String
    public var calibrationPoints: [MapCalibrationPoint]  // 3つの基準座標
    public var affineTransform: AffineTransformMatrix?
    public let createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        floorMapId: String,
        calibrationPoints: [MapCalibrationPoint] = [],
        affineTransform: AffineTransformMatrix? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.antennaId = antennaId
        self.floorMapId = floorMapId
        self.calibrationPoints = calibrationPoints
        self.affineTransform = affineTransform
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }

    /// キャリブレーション完了しているか（3点設定済み）
    public var isCalibrated: Bool {
        affineTransform != nil && calibrationPoints.count == 3
    }

    /// キャリブレーション精度を取得
    public var accuracy: Double? {
        affineTransform?.accuracy
    }
}

// MARK: - Point3D拡張（キャリブレーション用）

extension Point3D {
    /// 2点間の距離を計算
    public func distance(to other: Point3D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// ベクトルの長さを計算
    public var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    /// 正規化されたベクトルを取得
    public var normalized: Point3D {
        let mag = magnitude
        guard mag > 0 else { return .zero }
        return Point3D(x: x / mag, y: y / mag, z: z / mag)
    }

    /// ベクトルの加算
    public static func + (lhs: Point3D, rhs: Point3D) -> Point3D {
        Point3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    /// ベクトルの減算
    public static func - (lhs: Point3D, rhs: Point3D) -> Point3D {
        Point3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    /// スカラー倍
    public static func * (lhs: Point3D, rhs: Double) -> Point3D {
        Point3D(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}
