import Foundation

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

    public init(
        id: UUID = UUID(), deviceName: String, timestamp: TimeInterval, elevation: Double, azimuth: Double,
        distance: Double, nlos: Int, rssi: Double, seqCount: Int
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
