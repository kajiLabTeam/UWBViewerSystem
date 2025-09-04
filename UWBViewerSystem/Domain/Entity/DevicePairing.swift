import Foundation

// MARK: - Androidデバイスエンティティ

public struct AndroidDevice: Identifiable, Codable {
    public let id: String  // endpointId
    public var name: String
    public var isConnected: Bool
    public var lastSeen: Date
    public let isNearbyDevice: Bool  // NearBy Connectionで発見されたデバイスかどうか

    init(id: String = UUID().uuidString, name: String, isConnected: Bool = false, isNearbyDevice: Bool = true) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.lastSeen = Date()
        self.isNearbyDevice = isNearbyDevice
    }
}

// MARK: - アンテナペアリングエンティティ

public struct AntennaPairing: Identifiable, Codable {
    public let id: String
    public let antenna: AntennaInfo
    public let device: AndroidDevice
    public let pairedAt: Date

    init(antenna: AntennaInfo, device: AndroidDevice) {
        self.id = UUID().uuidString
        self.antenna = antenna
        self.device = device
        self.pairedAt = Date()
    }
}

// AntennaInfo、Point3DはCommonTypes.swiftで定義済み
