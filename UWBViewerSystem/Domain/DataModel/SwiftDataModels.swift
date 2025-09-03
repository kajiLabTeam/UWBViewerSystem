import Foundation
import SwiftData

// MARK: - SwiftDataモデル

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
        return SensingSession(
            id: self.id,
            name: self.name,
            startTime: self.startTime,
            endTime: self.endTime,
            isActive: self.isActive
        )
    }
}

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
        return AntennaPositionData(
            id: self.id,
            antennaId: self.antennaId,
            antennaName: self.antennaName,
            position: Point3D(x: self.x, y: self.y, z: self.z),
            rotation: self.rotation
        )
    }
}

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
            id: self.antennaId,
            name: self.antennaName,
            coordinates: Point3D(x: self.antennaX, y: self.antennaY, z: self.antennaZ)
        )
        let device = AndroidDevice(
            id: self.deviceId,
            name: self.deviceName,
            isConnected: self.isConnected
        )
        return AntennaPairing(antenna: antenna, device: device)
    }
}

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
        return RealtimeData(
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

@Model
public final class PersistentSystemActivity {
    public var id: String
    public var activityType: String
    public var activityDescription: String
    public var timestamp: Date
    public var metadata: Data?  // JSON data for additional information

    public init(
        id: String = UUID().uuidString,
        activityType: String,
        activityDescription: String,
        timestamp: Date = Date(),
        metadata: Data? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.activityDescription = activityDescription
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public func toEntity() -> SystemActivity {
        return SystemActivity(
            id: self.id,
            activityType: self.activityType,
            activityDescription: self.activityDescription,
            timestamp: self.timestamp
        )
    }
}

@Model
public final class PersistentReceivedFile {
    public var id: UUID
    public var fileName: String
    public var filePath: String  // FileURLの代わりにパスを保存
    public var deviceName: String
    public var receivedAt: Date
    public var fileSize: Int64

    public init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        deviceName: String,
        receivedAt: Date = Date(),
        fileSize: Int64
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.deviceName = deviceName
        self.receivedAt = receivedAt
        self.fileSize = fileSize
    }

    public func toEntity() -> ReceivedFile {
        return ReceivedFile(
            id: self.id,
            fileName: self.fileName,
            fileURL: URL(fileURLWithPath: self.filePath),
            deviceName: self.deviceName,
            receivedAt: self.receivedAt,
            fileSize: self.fileSize
        )
    }
}

// MARK: - Entity拡張（SwiftDataモデルへの変換）

extension SensingSession {
    public func toPersistent() -> PersistentSensingSession {
        return PersistentSensingSession(
            id: self.id,
            name: self.name,
            startTime: self.startTime,
            endTime: self.endTime,
            isActive: self.isActive
        )
    }
}

extension AntennaPositionData {
    public func toPersistent() -> PersistentAntennaPosition {
        return PersistentAntennaPosition(
            id: self.id,
            antennaId: self.antennaId,
            antennaName: self.antennaName,
            x: self.position.x,
            y: self.position.y,
            z: self.position.z,
            rotation: self.rotation
        )
    }
}

extension AntennaPairing {
    public func toPersistent() -> PersistentAntennaPairing {
        return PersistentAntennaPairing(
            antennaId: self.antenna.id,
            antennaName: self.antenna.name,
            antennaX: self.antenna.coordinates.x,
            antennaY: self.antenna.coordinates.y,
            antennaZ: self.antenna.coordinates.z,
            deviceId: self.device.id,
            deviceName: self.device.name,
            isConnected: self.device.isConnected,
            pairedAt: self.pairedAt
        )
    }
}

extension RealtimeData {
    public func toPersistent() -> PersistentRealtimeData {
        return PersistentRealtimeData(
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

extension SystemActivity {
    public func toPersistent() -> PersistentSystemActivity {
        return PersistentSystemActivity(
            id: self.id,
            activityType: self.activityType,
            activityDescription: self.activityDescription,
            timestamp: self.timestamp
        )
    }
}

extension ReceivedFile {
    public func toPersistent() -> PersistentReceivedFile {
        return PersistentReceivedFile(
            id: self.id,
            fileName: self.fileName,
            filePath: self.fileURL.path,
            deviceName: self.deviceName,
            receivedAt: self.receivedAt,
            fileSize: self.fileSize
        )
    }
}
