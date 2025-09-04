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
    public var session: PersistentSensingSession?

    public init(
        id: String = UUID().uuidString,
        antennaId: String,
        antennaName: String,
        x: Double,
        y: Double,
        z: Double,
        rotation: Double = 0.0,
        session: PersistentSensingSession? = nil
    ) {
        self.id = id
        self.antennaId = antennaId
        self.antennaName = antennaName
        self.x = x
        self.y = y
        self.z = z
        self.rotation = rotation
        self.session = session
    }

    public func toEntity() -> AntennaPositionData {
        AntennaPositionData(
            id: id,
            antennaId: antennaId,
            antennaName: antennaName,
            position: Point3D(x: x, y: y, z: z),
            rotation: rotation
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
        return AntennaPairing(antenna: antenna, device: device)
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
            rotation: rotation
        )
    }
}

extension AntennaPairing {
    public func toPersistent() -> PersistentAntennaPairing {
        PersistentAntennaPairing(
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

// ReceivedFileのtoPersistent拡張はPersistentReceivedFile.swiftで定義済み
