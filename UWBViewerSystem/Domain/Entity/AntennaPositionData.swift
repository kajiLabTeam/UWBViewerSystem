import Foundation

// MARK: - アンテナ位置データエンティティ

public struct AntennaPositionData: Identifiable, Codable {
    public let id: String
    public let antennaId: String
    public let antennaName: String
    public let position: Point3D
    public let rotation: Double  // アンテナの向き（度数法）
    public let calibratedAt: Date
    public let floorMapId: String  // どのフロアマップに属するかを識別

    public init(
        id: String = UUID().uuidString, antennaId: String, antennaName: String, position: Point3D,
        rotation: Double = 0.0, calibratedAt: Date = Date(), floorMapId: String
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.position = position
        self.rotation = rotation
        self.calibratedAt = calibratedAt
        self.floorMapId = floorMapId
    }

    // 旧データとの互換性のための初期化メソッド
    @available(*, deprecated, message: "Use the new initializer with antennaId and antennaName")
    public init(
        id: String = UUID().uuidString, deviceId: String, deviceName: String, realWorldPosition: RealWorldPosition,
        fieldPosition: Point3D, calibratedAt: Date = Date(), floorMapId: String = ""
    ) {
        self.id = id
        antennaId = deviceId
        antennaName = deviceName
        position = Point3D(x: realWorldPosition.x, y: realWorldPosition.y, z: realWorldPosition.z)
        rotation = 0.0
        self.calibratedAt = calibratedAt
        self.floorMapId = floorMapId
    }
}

// RealWorldPosition、SystemActivity、ActivityType、ActivityStatusはCommonTypes.swiftで定義済み
