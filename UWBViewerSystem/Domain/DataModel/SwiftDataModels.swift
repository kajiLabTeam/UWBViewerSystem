import Foundation
import SwiftData

// MARK: - SwiftDataモデル

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentSensingSession {
    public var id: String
    public var name: String
    public var startTime: Date
    public var endTime: Date?
    public var isActive: Bool
    // リレーションシップを一旦削除してシンプル化
    // public var antennaPositions: [PersistentAntennaPosition]
    // public var antennaPairings: [PersistentAntennaPairing]
    // public var realtimeDataEntries: [PersistentRealtimeData]

    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
    }

    // Entity層への変換メソッド
    public func toEntity() -> SensingSession {
        SensingSession(
            id: self.id,
            name: self.name,
            startTime: self.startTime,
            endTime: self.endTime,
            isActive: self.isActive
        )
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentAntennaPosition {
    public var id: String
    public var antennaId: String
    public var antennaName: String
    public var x: Double
    public var y: Double
    public var z: Double
    public var rotation: Double  // 新規追加: アンテナの向き（角度）
    public var floorMapId: String  // どのフロアマップに属するかを識別
    // public var session: PersistentSensingSession?  // リレーションシップを一旦削除

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        antennaName: String,
        x: Double,
        y: Double,
        z: Double,
        rotation: Double = 0.0,
        floorMapId: String
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.x = x
        self.y = y
        self.z = z
        self.rotation = rotation
        self.floorMapId = floorMapId
    }

    public func toEntity() -> AntennaPositionData {
        AntennaPositionData(
            id: self.id,
            antennaId: self.antennaId,
            antennaName: self.antennaName,
            position: Point3D(x: self.x, y: self.y, z: self.z),
            rotation: self.rotation,
            floorMapId: self.floorMapId
        )
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentAntennaPairing {
    public var id: String
    public var antennaId: String
    public var antennaName: String
    public var antennaX: Double
    public var antennaY: Double
    public var antennaZ: Double
    public var deviceId: String
    public var deviceName: String
    public var isConnected: Bool
    public var pairedAt: Date
    // public var session: PersistentSensingSession?  // リレーションシップを一旦削除

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        antennaName: String,
        antennaX: Double,
        antennaY: Double,
        antennaZ: Double,
        deviceId: String,
        deviceName: String,
        isConnected: Bool = false,
        pairedAt: Date = Date()
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.antennaX = antennaX
        self.antennaY = antennaY
        self.antennaZ = antennaZ
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.pairedAt = pairedAt
    }

    public func toEntity() -> AntennaPairing {
        let antenna = AntennaInfo(
            id: antennaId,
            name: antennaName,
            coordinates: Point3D(x: antennaX, y: antennaY, z: antennaZ)
        )
        let device = AndroidDevice(
            id: deviceId,
            name: deviceName,
            isConnected: isConnected
        )
        return AntennaPairing(id: self.id, antenna: antenna, device: device, pairedAt: self.pairedAt)
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentRealtimeData {
    public var id: UUID
    public var deviceName: String
    public var timestamp: TimeInterval
    public var elevation: Double
    public var azimuth: Double
    public var distance: Double
    public var nlos: Int
    public var rssi: Double
    public var seqCount: Int
    // public var session: PersistentSensingSession?  // リレーションシップを一旦削除

    public init(
        id: UUID = UUID(),
        deviceName: String,
        timestamp: TimeInterval,
        elevation: Double,
        azimuth: Double,
        distance: Double,
        nlos: Int,
        rssi: Double,
        seqCount: Int,
        // session: PersistentSensingSession? = nil  // リレーションシップを一旦削除
    ) {
        self.id = id
        self.deviceName = deviceName
        self.timestamp = timestamp
        self.elevation = elevation
        self.azimuth = azimuth
        self.distance = distance
        self.nlos = nlos
        self.rssi = rssi
        self.seqCount = seqCount
        // self.session = session  // リレーションシップを一旦削除
    }

    public func toEntity() -> RealtimeData {
        RealtimeData(
            id: self.id,
            deviceName: self.deviceName,
            timestamp: self.timestamp,
            elevation: self.elevation,
            azimuth: self.azimuth,
            distance: self.distance,
            nlos: self.nlos,
            rssi: self.rssi,
            seqCount: self.seqCount
        )
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentFloorMap {
    public var id: String
    public var name: String
    public var buildingName: String
    public var width: Double
    public var depth: Double
    public var createdAt: Date
    public var isActive: Bool
    public var antennaPositions: [PersistentAntennaPosition] = []

    public init(
        id: String = UUID().uuidString,
        name: String,
        buildingName: String,
        width: Double,
        depth: Double,
        createdAt: Date = Date(),
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.buildingName = buildingName
        self.width = width
        self.depth = depth
        self.createdAt = createdAt
        self.isActive = isActive
    }

    public func toEntity() -> FloorMapInfo {
        FloorMapInfo(
            id: self.id,
            name: self.name,
            buildingName: self.buildingName,
            width: self.width,
            depth: self.depth,
            createdAt: self.createdAt
        )
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentSystemActivity {
    public var id: String
    public var activityType: String
    public var activityDescription: String
    public var status: String
    public var timestamp: Date
    public var metadata: Data?  // JSON data for additional information

    public init(
        id: String = UUID().uuidString,
        activityType: String,
        activityDescription: String,
        status: String = "completed",
        timestamp: Date = Date(),
        metadata: Data? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.activityDescription = activityDescription
        self.status = status
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public func toEntity() -> SystemActivity {
        var additionalData: [String: String]?
        if let metadataData = metadata {
            additionalData = try? JSONSerialization.jsonObject(with: metadataData) as? [String: String]
        }

        return SystemActivity(
            id: UUID(uuidString: self.id) ?? UUID(),
            timestamp: self.timestamp,
            activityType: self.activityType,
            activityDescription: self.activityDescription,
            status: ActivityStatus(rawValue: self.status) ?? .completed,
            additionalData: additionalData
        )
    }
}

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentProjectProgress {
    public var id: String
    public var floorMapId: String
    public var currentStep: String
    public var completedStepsData: Data  // Set<SetupStep>をJSONで保存
    public var stepData: Data  // [String: Data]をJSONで保存
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        floorMapId: String,
        currentStep: String = "floor_map_setting",
        completedStepsData: Data = Data(),
        stepData: Data = Data(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.floorMapId = floorMapId
        self.currentStep = currentStep
        self.completedStepsData = completedStepsData
        self.stepData = stepData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func toEntity() -> ProjectProgress {
        let decoder = JSONDecoder()

        // completedStepsの復元
        var completedSteps: Set<SetupStep> = []
        if !self.completedStepsData.isEmpty {
            if let stepStrings = try? decoder.decode([String].self, from: completedStepsData) {
                completedSteps = Set(stepStrings.compactMap { SetupStep(rawValue: $0) })
            }
        }

        // stepDataの復元
        var projectStepData: [String: Data] = [:]
        if !self.stepData.isEmpty {
            if let decodedStepData = try? decoder.decode([String: Data].self, from: stepData) {
                projectStepData = decodedStepData
            }
        }

        return ProjectProgress(
            id: self.id,
            floorMapId: self.floorMapId,
            currentStep: SetupStep(rawValue: self.currentStep) ?? .floorMapSetting,
            completedSteps: completedSteps,
            stepData: projectStepData,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}

// PersistentReceivedFileは単体ファイルで定義済み

@available(macOS 14, iOS 17, *)
@Model
public final class PersistentCalibrationData {
    public var id: String
    public var antennaId: String
    public var calibrationPointsData: Data  // [CalibrationPoint]をJSONで保存
    public var transformData: Data?  // CalibrationTransformをJSONで保存
    public var createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        calibrationPointsData: Data = Data(),
        transformData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.antennaId = antennaId
        self.calibrationPointsData = calibrationPointsData
        self.transformData = transformData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }

    public func toEntity() -> CalibrationData {
        let decoder = JSONDecoder()

        // CalibrationPointsの復元
        var calibrationPoints: [CalibrationPoint] = []
        if !self.calibrationPointsData.isEmpty {
            calibrationPoints = (try? decoder.decode([CalibrationPoint].self, from: self.calibrationPointsData)) ?? []
        }

        // CalibrationTransformの復元
        var transform: CalibrationTransform?
        if let transformData, !transformData.isEmpty {
            transform = try? decoder.decode(CalibrationTransform.self, from: transformData)
        }

        return CalibrationData(
            id: self.id,
            antennaId: self.antennaId,
            calibrationPoints: calibrationPoints,
            transform: transform,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            isActive: self.isActive
        )
    }
}

// MARK: - Entity拡張（SwiftDataモデルへの変換）

extension SensingSession {
    public func toPersistent() -> PersistentSensingSession {
        PersistentSensingSession(
            id: id,
            name: name,
            startTime: startTime,
            endTime: endTime,
            isActive: isActive
        )
    }
}

extension AntennaPositionData {
    public func toPersistent() -> PersistentAntennaPosition {
        PersistentAntennaPosition(
            id: id,
            antennaId: antennaId,
            antennaName: antennaName,
            x: position.x,
            y: position.y,
            z: position.z,
            rotation: rotation,
            floorMapId: floorMapId
        )
    }
}

extension FloorMapInfo {
    public func toPersistent() -> PersistentFloorMap {
        PersistentFloorMap(
            id: id,
            name: name,
            buildingName: buildingName,
            width: width,
            depth: depth,
            createdAt: createdAt,
            isActive: false
        )
    }
}

extension AntennaPairing {
    public func toPersistent() -> PersistentAntennaPairing {
        PersistentAntennaPairing(
            id: id,
            antennaId: antenna.id,
            antennaName: antenna.name,
            antennaX: antenna.coordinates.x,
            antennaY: antenna.coordinates.y,
            antennaZ: antenna.coordinates.z,
            deviceId: device.id,
            deviceName: device.name,
            isConnected: device.isConnected,
            pairedAt: pairedAt
        )
    }
}

extension RealtimeData {
    public func toPersistent() -> PersistentRealtimeData {
        PersistentRealtimeData(
            id: id,
            deviceName: deviceName,
            timestamp: timestamp,
            elevation: elevation,
            azimuth: azimuth,
            distance: distance,
            nlos: nlos,
            rssi: rssi,
            seqCount: seqCount
        )
    }
}

extension SystemActivity {
    public func toPersistent() -> PersistentSystemActivity {
        let metadataData = try? JSONSerialization.data(withJSONObject: additionalData ?? [:])
        return PersistentSystemActivity(
            id: id.uuidString,
            activityType: activityType,
            activityDescription: activityDescription,
            status: status.rawValue,
            timestamp: timestamp,
            metadata: metadataData
        )
    }
}

extension ProjectProgress {
    public func toPersistent() -> PersistentProjectProgress {
        let encoder = JSONEncoder()

        // completedStepsをData型に変換
        let stepStrings = completedSteps.map { $0.rawValue }
        let completedStepsData = (try? encoder.encode(stepStrings)) ?? Data()

        // stepDataをData型に変換
        let stepDataEncoded = (try? encoder.encode(stepData)) ?? Data()

        return PersistentProjectProgress(
            id: id,
            floorMapId: floorMapId,
            currentStep: currentStep.rawValue,
            completedStepsData: completedStepsData,
            stepData: stepDataEncoded,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CalibrationData {
    public func toPersistent() -> PersistentCalibrationData {
        let encoder = JSONEncoder()

        // CalibrationPointsをData型に変換
        let calibrationPointsData = (try? encoder.encode(calibrationPoints)) ?? Data()

        // CalibrationTransformをData型に変換
        var transformData: Data?
        if let transform {
            transformData = try? encoder.encode(transform)
        }

        return PersistentCalibrationData(
            id: id,
            antennaId: antennaId,
            calibrationPointsData: calibrationPointsData,
            transformData: transformData,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive
        )
    }
}

/// マップベースキャリブレーションデータの永続化モデル
@Model
public final class PersistentMapCalibrationData {
    public var id: String
    public var antennaId: String
    public var floorMapId: String
    public var calibrationPointsData: Data  // [MapCalibrationPoint]をJSONで保存
    public var affineTransformData: Data?  // AffineTransformMatrixをJSONで保存
    public var createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool

    public init(
        id: String,
        antennaId: String,
        floorMapId: String,
        calibrationPointsData: Data = Data(),
        affineTransformData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.antennaId = antennaId
        self.floorMapId = floorMapId
        self.calibrationPointsData = calibrationPointsData
        self.affineTransformData = affineTransformData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }

    /// PersistentからEntityへの変換
    public func toEntity() -> MapCalibrationData {
        let decoder = JSONDecoder()

        // MapCalibrationPointsの復元
        var calibrationPoints: [MapCalibrationPoint] = []
        if !self.calibrationPointsData.isEmpty {
            calibrationPoints =
                (try? decoder.decode([MapCalibrationPoint].self, from: self.calibrationPointsData)) ?? []
        }

        // AffineTransformMatrixの復元
        var affineTransform: AffineTransformMatrix?
        if let transformData = affineTransformData {
            affineTransform = try? decoder.decode(AffineTransformMatrix.self, from: transformData)
        }

        return MapCalibrationData(
            id: self.id,
            antennaId: self.antennaId,
            floorMapId: self.floorMapId,
            calibrationPoints: calibrationPoints,
            affineTransform: affineTransform,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            isActive: self.isActive
        )
    }
}

/// MapCalibrationDataのPersistent変換拡張
extension MapCalibrationData {
    public func toPersistent() -> PersistentMapCalibrationData {
        let encoder = JSONEncoder()

        // MapCalibrationPointsをData型に変換
        let calibrationPointsData = (try? encoder.encode(calibrationPoints)) ?? Data()

        // AffineTransformMatrixをData型に変換
        var affineTransformData: Data?
        if let transform = affineTransform {
            affineTransformData = try? encoder.encode(transform)
        }

        return PersistentMapCalibrationData(
            id: id,
            antennaId: antennaId,
            floorMapId: floorMapId,
            calibrationPointsData: calibrationPointsData,
            affineTransformData: affineTransformData,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive
        )
    }
}

// ReceivedFileのtoPersistent拡張はPersistentReceivedFile.swiftで定義済み
