import Foundation

// MARK: - 設定・プリファレンス管理用Repository

public protocol PreferenceRepositoryProtocol {
    // MARK: - フロアマップ設定関連

    func saveCurrentFloorMapInfo(_ info: FloorMapInfo)
    func loadCurrentFloorMapInfo() -> FloorMapInfo?
    func removeCurrentFloorMapInfo()

    func saveLastFloorSettings(name: String, buildingName: String, width: Double, depth: Double)
    func loadLastFloorSettings() -> (name: String?, buildingName: String?, width: Double?, depth: Double?)

    func setHasFloorMapConfigured(_ configured: Bool)
    func getHasFloorMapConfigured() -> Bool

    // MARK: - アンテナ設定関連

    func saveConfiguredAntennaPositions(_ positions: [AntennaPositionData])
    func loadConfiguredAntennaPositions() -> [AntennaPositionData]?
    func removeConfiguredAntennaPositions()

    // MARK: - キャリブレーション関連

    func saveLastCalibrationResult(_ result: SystemCalibrationResult)
    func loadLastCalibrationResult() -> SystemCalibrationResult?
    func removeLastCalibrationResult()

    // MARK: - センシングフロー関連

    func saveSensingFlowState(currentStep: String, completedSteps: [String], isCompleted: Bool)
    func loadSensingFlowState() -> (currentStep: String?, completedSteps: [String], isCompleted: Bool)
    func resetSensingFlowState()

    func setHasExecutedSensingSession(_ executed: Bool)
    func getHasExecutedSensingSession() -> Bool

    // MARK: - デバイス管理関連

    func savePairedDevices(_ devices: [String])
    func loadPairedDevices() -> [String]?
    func removePairedDevices()

    func saveConnectionStatistics(_ statistics: [String: Any])
    func loadConnectionStatistics() -> [String: Any]?

    // MARK: - データ移行関連

    func setMigrationCompleted(for key: String, completed: Bool)
    func isMigrationCompleted(for key: String) -> Bool

    // MARK: - 汎用設定メソッド

    func setBool(_ value: Bool, forKey key: String)
    func getBool(forKey key: String) -> Bool

    func setString(_ value: String?, forKey key: String)
    func getString(forKey key: String) -> String?

    func setDouble(_ value: Double, forKey key: String)
    func getDouble(forKey key: String) -> Double

    func setData<T: Codable>(_ value: T, forKey key: String) throws
    func getData<T: Codable>(_ type: T.Type, forKey key: String) -> T?

    func removeObject(forKey key: String)
}

public class PreferenceRepository: PreferenceRepositoryProtocol {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - フロアマップ設定関連

    public func saveCurrentFloorMapInfo(_ info: FloorMapInfo) {
        do {
            try setData(info, forKey: "currentFloorMapInfo")
        } catch {
            print("❌ フロアマップ情報の保存に失敗: \(error)")
        }
    }

    public func loadCurrentFloorMapInfo() -> FloorMapInfo? {
        getData(FloorMapInfo.self, forKey: "currentFloorMapInfo")
    }

    public func removeCurrentFloorMapInfo() {
        removeObject(forKey: "currentFloorMapInfo")
    }

    public func saveLastFloorSettings(name: String, buildingName: String, width: Double, depth: Double) {
        setString(name, forKey: "lastFloorName")
        setString(buildingName, forKey: "lastBuildingName")
        setDouble(width, forKey: "lastFloorWidth")
        setDouble(depth, forKey: "lastFloorDepth")
    }

    public func loadLastFloorSettings() -> (name: String?, buildingName: String?, width: Double?, depth: Double?) {
        let name = getString(forKey: "lastFloorName")
        let buildingName = getString(forKey: "lastBuildingName")
        let width = userDefaults.object(forKey: "lastFloorWidth") as? Double
        let depth = userDefaults.object(forKey: "lastFloorDepth") as? Double
        return (name, buildingName, width, depth)
    }

    public func setHasFloorMapConfigured(_ configured: Bool) {
        setBool(configured, forKey: "hasFloorMapConfigured")
    }

    public func getHasFloorMapConfigured() -> Bool {
        getBool(forKey: "hasFloorMapConfigured")
    }

    // MARK: - アンテナ設定関連

    public func saveConfiguredAntennaPositions(_ positions: [AntennaPositionData]) {
        do {
            try setData(positions, forKey: "configuredAntennaPositions")
        } catch {
            print("❌ アンテナ位置情報の保存に失敗: \(error)")
        }
    }

    public func loadConfiguredAntennaPositions() -> [AntennaPositionData]? {
        getData([AntennaPositionData].self, forKey: "configuredAntennaPositions")
    }

    public func removeConfiguredAntennaPositions() {
        removeObject(forKey: "configuredAntennaPositions")
    }

    // MARK: - キャリブレーション関連

    public func saveLastCalibrationResult(_ result: SystemCalibrationResult) {
        do {
            try setData(result, forKey: "lastCalibrationResult")
        } catch {
            print("❌ キャリブレーション結果の保存に失敗: \(error)")
        }
    }

    public func loadLastCalibrationResult() -> SystemCalibrationResult? {
        getData(SystemCalibrationResult.self, forKey: "lastCalibrationResult")
    }

    public func removeLastCalibrationResult() {
        removeObject(forKey: "lastCalibrationResult")
    }

    // MARK: - センシングフロー関連

    public func saveSensingFlowState(currentStep: String, completedSteps: [String], isCompleted: Bool) {
        do {
            try setData(currentStep, forKey: "sensingFlowCurrentStep")
            try setData(completedSteps, forKey: "sensingFlowCompletedSteps")
            setBool(isCompleted, forKey: "sensingFlowCompleted")
        } catch {
            print("❌ センシングフロー状態の保存に失敗: \(error)")
        }
    }

    public func loadSensingFlowState() -> (currentStep: String?, completedSteps: [String], isCompleted: Bool) {
        let currentStep = getData(String.self, forKey: "sensingFlowCurrentStep")
        let completedSteps = getData([String].self, forKey: "sensingFlowCompletedSteps") ?? []
        let isCompleted = getBool(forKey: "sensingFlowCompleted")
        return (currentStep, completedSteps, isCompleted)
    }

    public func resetSensingFlowState() {
        removeObject(forKey: "sensingFlowCurrentStep")
        removeObject(forKey: "sensingFlowCompletedSteps")
        removeObject(forKey: "sensingFlowCompleted")
    }

    public func setHasExecutedSensingSession(_ executed: Bool) {
        setBool(executed, forKey: "hasExecutedSensingSession")
    }

    public func getHasExecutedSensingSession() -> Bool {
        getBool(forKey: "hasExecutedSensingSession")
    }

    // MARK: - デバイス管理関連

    public func savePairedDevices(_ devices: [String]) {
        do {
            try setData(devices, forKey: "pairedDevices")
        } catch {
            print("❌ ペアリングデバイス情報の保存に失敗: \(error)")
        }
    }

    public func loadPairedDevices() -> [String]? {
        getData([String].self, forKey: "pairedDevices")
    }

    public func removePairedDevices() {
        removeObject(forKey: "pairedDevices")
    }

    public func saveConnectionStatistics(_ statistics: [String: Any]) {
        userDefaults.set(statistics, forKey: "ConnectionStatistics")
    }

    public func loadConnectionStatistics() -> [String: Any]? {
        userDefaults.dictionary(forKey: "ConnectionStatistics")
    }

    // MARK: - データ移行関連

    public func setMigrationCompleted(for key: String, completed: Bool) {
        setBool(completed, forKey: key)
    }

    public func isMigrationCompleted(for key: String) -> Bool {
        getBool(forKey: key)
    }

    // MARK: - 汎用設定メソッド

    public func setBool(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getBool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    public func setString(_ value: String?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getString(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func setDouble(_ value: Double, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getDouble(forKey key: String) -> Double {
        userDefaults.double(forKey: key)
    }

    public func setData(_ value: some Codable, forKey key: String) throws {
        let encoded = try JSONEncoder().encode(value)
        userDefaults.set(encoded, forKey: key)
    }

    public func getData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}