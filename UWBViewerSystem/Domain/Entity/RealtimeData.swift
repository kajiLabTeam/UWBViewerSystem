import Foundation

// MARK: - タグ表示モード

/// タグの位置表示モード
public enum TagDisplayMode: String, CaseIterable {
    case individual = "individual"  // 各アンテナからの個別位置を表示
    case integrated = "integrated"  // 統合位置（重心）のみを表示

    public var displayName: String {
        switch self {
        case .individual:
            return "個別表示"
        case .integrated:
            return "統合表示"
        }
    }

    public var description: String {
        switch self {
        case .individual:
            return "各アンテナからの観測位置を全て表示"
        case .integrated:
            return "NLOSを考慮した重心位置を表示"
        }
    }
}

// MARK: - リアルタイムデータエンティティ

public struct RealtimeData: Identifiable, Codable {
    public let id: UUID
    public let deviceName: String
    public let timestamp: TimeInterval
    public let elevation: Double
    public let azimuth: Double
    public let distance: Double
    public let nlos: Int
    public let rssi: Double
    public let seqCount: Int
    public let antennaId: String  // デバイスに紐づくアンテナID

    public init(
        id: UUID = UUID(), deviceName: String, timestamp: TimeInterval, elevation: Double, azimuth: Double,
        distance: Double, nlos: Int, rssi: Double, seqCount: Int, antennaId: String = ""
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
        self.antennaId = antennaId
    }

    public var formattedTime: String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - デバイス別リアルタイムデータ

public class DeviceRealtimeData: Identifiable, ObservableObject {
    public let id = UUID()
    public let deviceName: String
    @Published public var latestData: RealtimeData?
    @Published public var dataHistory: [RealtimeData] = []
    @Published public var lastUpdateTime: Date = Date()
    @Published public var isActive: Bool = true

    public var isRecentlyUpdated: Bool {
        Date().timeIntervalSince(self.lastUpdateTime) < 5.0  // 5秒以内の更新
    }

    public var hasData: Bool {
        self.latestData != nil
    }

    public var isDataStale: Bool {
        guard let latestData else { return true }
        let dataTime = Date(timeIntervalSince1970: latestData.timestamp / 1000)
        return Date().timeIntervalSince(dataTime) > 10.0
    }

    public var hasIssue: Bool {
        !self.hasData || self.isDataStale || !self.isRecentlyUpdated
    }

    public init(
        deviceName: String, latestData: RealtimeData? = nil, dataHistory: [RealtimeData] = [],
        lastUpdateTime: Date = Date(), isActive: Bool = true
    ) {
        self.deviceName = deviceName
        self.latestData = latestData
        self.dataHistory = dataHistory
        self.lastUpdateTime = lastUpdateTime
        self.isActive = isActive
    }

    public func addData(_ data: RealtimeData) {
        self.latestData = data
        self.dataHistory.append(data)
        self.lastUpdateTime = Date()
        self.isActive = true

        // 最新20件のデータのみ保持
        if self.dataHistory.count > 20 {
            self.dataHistory.removeFirst()
        }
    }

    public func clearData() {
        self.latestData = nil
        self.dataHistory.removeAll()
        self.lastUpdateTime = Date.distantPast
    }
}

// MARK: - タグ観測データ

/// 単一アンテナからの観測データ
public struct TagObservation: Identifiable {
    public let id = UUID()
    public let antennaId: String
    public let deviceName: String
    public let coordinate: Point3D
    public let isNLOS: Bool
    public let timestamp: Date

    public init(
        antennaId: String,
        deviceName: String,
        coordinate: Point3D,
        isNLOS: Bool,
        timestamp: Date
    ) {
        self.antennaId = antennaId
        self.deviceName = deviceName
        self.coordinate = coordinate
        self.isNLOS = isNLOS
        self.timestamp = timestamp
    }
}

// MARK: - 統合タグ位置

/// 複数アンテナからの観測を統合したタグの位置情報
public struct IntegratedTagPosition: Identifiable {
    public let id = UUID()
    public let tagId: String
    public let integratedCoordinate: Point3D
    public let confidence: Double
    public let observations: [TagObservation]
    public let hasNLOSOnly: Bool

    public init(
        tagId: String,
        integratedCoordinate: Point3D,
        confidence: Double,
        observations: [TagObservation],
        hasNLOSOnly: Bool
    ) {
        self.tagId = tagId
        self.integratedCoordinate = integratedCoordinate
        self.confidence = confidence
        self.observations = observations
        self.hasNLOSOnly = hasNLOSOnly
    }

    /// LOSの観測数
    public var losCount: Int {
        self.observations.filter { !$0.isNLOS }.count
    }

    /// NLOSの観測数
    public var nlosCount: Int {
        self.observations.filter { $0.isNLOS }.count
    }
}

// MARK: - JSONパース用の構造体

public struct RealtimeDataMessage: Codable {
    public let type: String
    public let deviceName: String
    public let timestamp: TimeInterval
    public let data: RealtimeDataPayload

    public struct RealtimeDataPayload: Codable {
        public let elevation: Double
        public let azimuth: Double
        public let distance: Int
        public let nlos: Int
        public let rssi: Double
        public let seqCount: Int
        public let elevationFom: Int?
        public let pDoA1: Double?
        public let pDoA2: Double?
    }
}
