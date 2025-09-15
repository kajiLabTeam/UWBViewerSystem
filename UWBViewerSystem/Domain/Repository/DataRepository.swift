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

    // 新しいキャリブレーション機能
    func saveCalibrationData(_ data: CalibrationData) async throws
    func loadCalibrationData() async throws -> [CalibrationData]
    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData?
    func deleteCalibrationData(for antennaId: String) async throws
    func deleteAllCalibrationData() async throws

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
              let sessions = try? JSONDecoder().decode([SensingSession].self, from: data)
        else {
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
        userDefaults.bool(forKey: "hasDeviceConnected")
    }

    // MARK: - キャリブレーション関連

    public func saveCalibrationResults(_ results: Data) {
        userDefaults.set(results, forKey: "CalibrationResults")
    }

    public func loadCalibrationResults() -> Data? {
        userDefaults.data(forKey: "CalibrationResults")
    }

    // MARK: - 新しいキャリブレーション機能

    public func saveCalibrationData(_ data: CalibrationData) async throws {
        let encoded = try JSONEncoder().encode(data)
        userDefaults.set(encoded, forKey: "CalibrationData_\(data.antennaId)")

        // 全体のキャリブレーションデータリストも更新
        var allData = (try? await loadCalibrationData()) ?? []
        allData.removeAll { $0.antennaId == data.antennaId }
        allData.append(data)

        let allEncoded = try JSONEncoder().encode(allData)
        userDefaults.set(allEncoded, forKey: "AllCalibrationData")
    }

    public func loadCalibrationData() async throws -> [CalibrationData] {
        guard let data = userDefaults.data(forKey: "AllCalibrationData") else {
            return []
        }
        return try JSONDecoder().decode([CalibrationData].self, from: data)
    }

    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        guard let data = userDefaults.data(forKey: "CalibrationData_\(antennaId)") else {
            return nil
        }
        return try JSONDecoder().decode(CalibrationData.self, from: data)
    }

    public func deleteCalibrationData(for antennaId: String) async throws {
        userDefaults.removeObject(forKey: "CalibrationData_\(antennaId)")

        // 全体のリストからも削除
        var allData = (try? await loadCalibrationData()) ?? []
        allData.removeAll { $0.antennaId == antennaId }

        if allData.isEmpty {
            userDefaults.removeObject(forKey: "AllCalibrationData")
        } else {
            let allEncoded = try JSONEncoder().encode(allData)
            userDefaults.set(allEncoded, forKey: "AllCalibrationData")
        }
    }

    public func deleteAllCalibrationData() async throws {
        let allData = (try? await loadCalibrationData()) ?? []

        // 個別のキャリブレーションデータを全て削除
        for data in allData {
            userDefaults.removeObject(forKey: "CalibrationData_\(data.antennaId)")
        }

        // 全体のリストも削除
        userDefaults.removeObject(forKey: "AllCalibrationData")
    }

    // MARK: - 設定関連

    public func saveBoolSetting(key: String, value: Bool) {
        userDefaults.set(value, forKey: key)
    }

    public func loadBoolSetting(key: String) -> Bool {
        userDefaults.bool(forKey: key)
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

    public func saveData(_ data: some Codable, forKey key: String) throws {
        let encoded = try JSONEncoder().encode(data)
        userDefaults.set(encoded, forKey: key)
    }

    public func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
