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
    public var antennaPositions: [PersistentAntennaPosition]
    public var antennaPairings: [PersistentAntennaPairing]
    public var realtimeDataEntries: [PersistentRealtimeData]

    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        isActive: Bool = true,
        antennaPositions: [PersistentAntennaPosition] = [],
        antennaPairings: [PersistentAntennaPairing] = [],
        realtimeDataEntries: [PersistentRealtimeData] = []
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.antennaPositions = antennaPositions
        self.antennaPairings = antennaPairings
        self.realtimeDataEntries = realtimeDataEntries
    }

    // Entity層への変換メソッド
    public func toEntity() -> SensingSession {
        SensingSession(
            id: id,
            name: name,
            startTime: startTime,
            endTime: endTime,
            isActive: isActive
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
    public var session: PersistentSensingSession?

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        antennaName: String,
        x: Double,
        y: Double,
        z: Double,
        rotation: Double = 0.0,
        floorMapId: String,
        session: PersistentSensingSession? = nil
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.x = x
        self.y = y
        self.z = z
        self.rotation = rotation
        self.floorMapId = floorMapId
        self.session = session
    }

    public func toEntity() -> AntennaPositionData {
        AntennaPositionData(
            id: id,
            antennaId: antennaId,
            antennaName: antennaName,
            position: Point3D(x: x, y: y, z: z),
            rotation: rotation,
            floorMapId: floorMapId
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
    public var session: PersistentSensingSession?

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
        pairedAt: Date = Date(),
        session: PersistentSensingSession? = nil
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
        self.session = session
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
        return AntennaPairing(id: id, antenna: antenna, device: device, pairedAt: pairedAt)
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
    public var session: PersistentSensingSession?

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
        session: PersistentSensingSession? = nil
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
        self.session = session
    }

    public func toEntity() -> RealtimeData {
        RealtimeData(
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
            id: id,
            name: name,
            buildingName: buildingName,
            width: width,
            depth: depth,
            createdAt: createdAt
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
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: timestamp,
            activityType: activityType,
            activityDescription: activityDescription,
            status: ActivityStatus(rawValue: status) ?? .completed,
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
    public var completedStepsData: Data // Set<SetupStep>をJSONで保存
    public var stepData: Data // [String: Data]をJSONで保存
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
        if !completedStepsData.isEmpty {
            if let stepStrings = try? decoder.decode([String].self, from: completedStepsData) {
                completedSteps = Set(stepStrings.compactMap { SetupStep(rawValue: $0) })
            }
        }
        
        // stepDataの復元
        var projectStepData: [String: Data] = [:]
        if !stepData.isEmpty {
            if let decodedStepData = try? decoder.decode([String: Data].self, from: stepData) {
                projectStepData = decodedStepData
            }
        }

        return ProjectProgress(
            id: id,
            floorMapId: floorMapId,
            currentStep: SetupStep(rawValue: currentStep) ?? .floorMapSetting,
            completedSteps: completedSteps,
            stepData: projectStepData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// PersistentReceivedFileは単体ファイルで定義済み

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

// ReceivedFileのtoPersistent拡張はPersistentReceivedFile.swiftで定義済み
