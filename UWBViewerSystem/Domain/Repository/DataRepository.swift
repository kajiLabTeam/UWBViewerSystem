import Foundation

// MARK: - データ保存用Repository

public protocol DataRepositoryProtocol {
    // センシングセッション関連
    func saveRecentSensingSessions(_ sessions: [SensingSession])
    func loadRecentSensingSessions() -> [SensingSession]
    
    // アンテナ関連
    func saveAntennaPositions(_ positions: [AntennaPositionData])
    func loadAntennaPositions() -> [AntennaPositionData]?
    func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo])
    func loadFieldAntennaConfiguration() -> [AntennaInfo]?
    
    // ペアリング関連
    func saveAntennaPairings(_ pairings: [AntennaPairing])
    func loadAntennaPairings() -> [AntennaPairing]?
    func saveHasDeviceConnected(_ connected: Bool)
    func loadHasDeviceConnected() -> Bool
    
    // キャリブレーション関連
    func saveCalibrationResults(_ results: Data)
    func loadCalibrationResults() -> Data?
    
    // 設定関連
    func saveBoolSetting(key: String, value: Bool)
    func loadBoolSetting(key: String) -> Bool
    
    // システム活動履歴
    func saveRecentSystemActivities(_ activities: [SystemActivity])
    func loadRecentSystemActivities() -> [SystemActivity]?
    
    // 一般的なデータ保存
    func saveData<T: Codable>(_ data: T, forKey key: String) throws
    func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T?
}

public class DataRepository: DataRepositoryProtocol {
    private let userDefaults = UserDefaults.standard
    
    public init() {}
    
    // MARK: - センシングセッション関連
    
    public func saveRecentSensingSessions(_ sessions: [SensingSession]) {
        if let encoded = try? JSONEncoder().encode(sessions) {
            userDefaults.set(encoded, forKey: "RecentSensingSessions")
        }
    }
    
    public func loadRecentSensingSessions() -> [SensingSession] {
        guard let data = userDefaults.data(forKey: "RecentSensingSessions"),
              let sessions = try? JSONDecoder().decode([SensingSession].self, from: data) else {
            return []
        }
        return sessions
    }
    
    // MARK: - アンテナ関連
    
    public func saveAntennaPositions(_ positions: [AntennaPositionData]) {
        if let encoded = try? JSONEncoder().encode(positions) {
            userDefaults.set(encoded, forKey: "AntennaPositions")
        }
    }
    
    public func loadAntennaPositions() -> [AntennaPositionData]? {
        guard let data = userDefaults.data(forKey: "AntennaPositions") else { return nil }
        return try? JSONDecoder().decode([AntennaPositionData].self, from: data)
    }
    
    public func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo]) {
        if let encoded = try? JSONEncoder().encode(antennas) {
            userDefaults.set(encoded, forKey: "FieldAntennaConfiguration")
        }
    }
    
    public func loadFieldAntennaConfiguration() -> [AntennaInfo]? {
        guard let data = userDefaults.data(forKey: "FieldAntennaConfiguration") else { return nil }
        return try? JSONDecoder().decode([AntennaInfo].self, from: data)
    }
    
    // MARK: - ペアリング関連
    
    public func saveAntennaPairings(_ pairings: [AntennaPairing]) {
        if let encoded = try? JSONEncoder().encode(pairings) {
            userDefaults.set(encoded, forKey: "AntennaPairings")
        }
    }
    
    public func loadAntennaPairings() -> [AntennaPairing]? {
        guard let data = userDefaults.data(forKey: "AntennaPairings") else { return nil }
        return try? JSONDecoder().decode([AntennaPairing].self, from: data)
    }
    
    public func saveHasDeviceConnected(_ connected: Bool) {
        userDefaults.set(connected, forKey: "hasDeviceConnected")
    }
    
    public func loadHasDeviceConnected() -> Bool {
        return userDefaults.bool(forKey: "hasDeviceConnected")
    }
    
    // MARK: - キャリブレーション関連
    
    public func saveCalibrationResults(_ results: Data) {
        userDefaults.set(results, forKey: "CalibrationResults")
    }
    
    public func loadCalibrationResults() -> Data? {
        return userDefaults.data(forKey: "CalibrationResults")
    }
    
    // MARK: - 設定関連
    
    public func saveBoolSetting(key: String, value: Bool) {
        userDefaults.set(value, forKey: key)
    }
    
    public func loadBoolSetting(key: String) -> Bool {
        return userDefaults.bool(forKey: key)
    }
    
    // MARK: - システム活動履歴
    
    public func saveRecentSystemActivities(_ activities: [SystemActivity]) {
        if let encoded = try? JSONEncoder().encode(activities) {
            userDefaults.set(encoded, forKey: "RecentSystemActivities")
        }
    }
    
    public func loadRecentSystemActivities() -> [SystemActivity]? {
        guard let data = userDefaults.data(forKey: "RecentSystemActivities") else { return nil }
        return try? JSONDecoder().decode([SystemActivity].self, from: data)
    }
    
    // MARK: - 一般的なデータ保存
    
    public func saveData<T: Codable>(_ data: T, forKey key: String) throws {
        let encoded = try JSONEncoder().encode(data)
        userDefaults.set(encoded, forKey: key)
    }
    
    public func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}