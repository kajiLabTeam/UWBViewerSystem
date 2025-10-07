import Foundation
import SwiftData

@testable import UWBViewerSystem

// MARK: - Mock Data Repository

@MainActor
public class MockDataRepository: DataRepositoryProtocol {

    // MARK: - Storage Properties

    public var calibrationDataStorage: [String: Data] = [:]
    public var shouldThrowError = false
    public var errorToThrow: Error = RepositoryError.saveFailed("Mock error")

    private var sensingSessionStorage: [SensingSession] = []
    private var antennaPositionStorage: [AntennaPositionData] = []
    private var antennaPairingStorage: [AntennaPairing] = []
    private var systemActivityStorage: [SystemActivity] = []
    private var boolSettingStorage: [String: Bool] = [:]
    private var generalDataStorage: [String: Any] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Calibration Methods

    public func saveCalibrationData(_ data: CalibrationData) async throws {
        if self.shouldThrowError {
            throw self.errorToThrow
        }
        // JSONエンコードして安全に保存
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)
        self.calibrationDataStorage[data.antennaId] = encodedData
    }

    public func loadCalibrationData() async throws -> [CalibrationData] {
        let decoder = JSONDecoder()
        return self.calibrationDataStorage.values.compactMap { data in
            try? decoder.decode(CalibrationData.self, from: data)
        }
    }

    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        guard let data = calibrationDataStorage[antennaId] else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CalibrationData.self, from: data)
    }

    public func deleteCalibrationData(for antennaId: String) async throws {
        self.calibrationDataStorage.removeValue(forKey: antennaId)
    }

    public func deleteAllCalibrationData() async throws {
        self.calibrationDataStorage.removeAll()
    }

    // MARK: - Sensing Session Methods

    nonisolated public func saveRecentSensingSessions(_ sessions: [SensingSession]) {
        Task { @MainActor in
            self.sensingSessionStorage = sessions
        }
    }

    nonisolated public func loadRecentSensingSessions() -> [SensingSession] {
        []  // テスト用のダミー実装
    }

    // MARK: - Antenna Methods

    nonisolated public func saveAntennaPositions(_ positions: [AntennaPositionData]) {
        Task { @MainActor in
            self.antennaPositionStorage = positions
        }
    }

    nonisolated public func loadAntennaPositions() -> [AntennaPositionData]? {
        []  // テスト用のダミー実装
    }

    nonisolated public func saveFieldAntennaConfiguration(_ antennas: [AntennaInfo]) {
        // Mock implementation
    }

    nonisolated public func loadFieldAntennaConfiguration() -> [AntennaInfo]? {
        [
            AntennaInfo(id: "test-antenna", name: "テストアンテナ", coordinates: Point3D(x: 0, y: 0, z: 0))
        ]
    }

    // MARK: - Pairing Methods

    nonisolated public func saveAntennaPairings(_ pairings: [AntennaPairing]) {
        Task { @MainActor in
            self.antennaPairingStorage = pairings
        }
    }

    nonisolated public func loadAntennaPairings() -> [AntennaPairing]? {
        []  // テスト用のダミー実装
    }

    nonisolated public func saveHasDeviceConnected(_ connected: Bool) {
        Task { @MainActor in
            self.boolSettingStorage["hasDeviceConnected"] = connected
        }
    }

    nonisolated public func loadHasDeviceConnected() -> Bool {
        false  // テスト用のダミー実装
    }

    // MARK: - Legacy Calibration Methods

    nonisolated public func saveCalibrationResults(_ results: Data) {
        // テスト用のダミー実装
    }

    nonisolated public func loadCalibrationResults() -> Data? {
        nil  // テスト用のダミー実装
    }

    // MARK: - Settings Methods

    nonisolated public func saveBoolSetting(key: String, value: Bool) {
        Task { @MainActor in
            self.boolSettingStorage[key] = value
        }
    }

    nonisolated public func loadBoolSetting(key: String) -> Bool {
        false  // テスト用のダミー実装
    }

    // MARK: - System Activity Methods

    nonisolated public func saveRecentSystemActivities(_ activities: [SystemActivity]) {
        Task { @MainActor in
            self.systemActivityStorage = activities
        }
    }

    nonisolated public func loadRecentSystemActivities() -> [SystemActivity]? {
        // nonisolatedからMainActorプロパティにアクセスできないため、空配列を返す
        []
    }

    // MARK: - General Data Methods

    nonisolated public func saveData(_ data: some Codable, forKey key: String) throws {
        // テスト用のダミー実装
    }

    nonisolated public func loadData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        // テスト用のダミー実装
        nil
    }
}

// MARK: - Mock SwiftData Repository

@MainActor
public class MockSwiftDataRepository: SwiftDataRepositoryProtocol {

    // MARK: - Storage Properties

    private var sensingSessionStorage: [SensingSession] = []
    private var antennaPositionStorage: [AntennaPositionData] = []
    private var antennaPairingStorage: [AntennaPairing] = []
    private var realtimeDataStorage: [String: [RealtimeData]] = [:]
    private var systemActivityStorage: [SystemActivity] = []
    private var receivedFileStorage: [ReceivedFile] = []
    private var floorMapStorage: [FloorMapInfo] = []
    private var projectProgressStorage: [ProjectProgress] = []
    private var calibrationDataStorage: [String: Data] = [:]
    private var mapCalibrationDataStorage: [String: MapCalibrationData] = [:]

    public var shouldThrowError = false
    public var errorToThrow: Error = RepositoryError.saveFailed("Mock error")

    // MARK: - Init

    public init() {}

    // MARK: - Sensing Session Methods

    public func saveSensingSession(_ session: SensingSession) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.sensingSessionStorage.append(session)
    }

    public func loadSensingSession(by id: String) async throws -> SensingSession? {
        self.sensingSessionStorage.first { $0.id == id }
    }

    public func loadAllSensingSessions() async throws -> [SensingSession] {
        self.sensingSessionStorage
    }

    public func deleteSensingSession(by id: String) async throws {
        self.sensingSessionStorage.removeAll { $0.id == id }
    }

    public func updateSensingSession(_ session: SensingSession) async throws {
        if let index = sensingSessionStorage.firstIndex(where: { $0.id == session.id }) {
            self.sensingSessionStorage[index] = session
        }
    }

    // MARK: - Antenna Position Methods

    public func saveAntennaPosition(_ position: AntennaPositionData) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.antennaPositionStorage.append(position)
    }

    public func loadAntennaPositions() async throws -> [AntennaPositionData] {
        self.antennaPositionStorage
    }

    public func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] {
        self.antennaPositionStorage.filter { $0.floorMapId == floorMapId }
    }

    public func deleteAntennaPosition(by id: String) async throws {
        self.antennaPositionStorage.removeAll { $0.antennaId == id }
    }

    public func updateAntennaPosition(_ position: AntennaPositionData) async throws {
        if let index = antennaPositionStorage.firstIndex(where: { $0.id == position.id }) {
            self.antennaPositionStorage[index] = position
        }
    }

    // MARK: - Antenna Pairing Methods

    public func saveAntennaPairing(_ pairing: AntennaPairing) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.antennaPairingStorage.append(pairing)
    }

    public func loadAntennaPairings() async throws -> [AntennaPairing] {
        self.antennaPairingStorage
    }

    public func deleteAntennaPairing(by id: String) async throws {
        self.antennaPairingStorage.removeAll { $0.id == id }
    }

    public func updateAntennaPairing(_ pairing: AntennaPairing) async throws {
        if let index = antennaPairingStorage.firstIndex(where: { $0.id == pairing.id }) {
            self.antennaPairingStorage[index] = pairing
        }
    }

    // MARK: - Realtime Data Methods

    public func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws {
        if self.shouldThrowError { throw self.errorToThrow }

        if self.realtimeDataStorage[sessionId] == nil {
            self.realtimeDataStorage[sessionId] = []
        }
        self.realtimeDataStorage[sessionId]?.append(data)
    }

    public func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] {
        self.realtimeDataStorage[sessionId] ?? []
    }

    public func deleteRealtimeData(by id: UUID) async throws {
        for sessionId in self.realtimeDataStorage.keys {
            self.realtimeDataStorage[sessionId]?.removeAll { $0.id == id }
        }
    }

    // MARK: - System Activity Methods

    public func saveSystemActivity(_ activity: SystemActivity) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.systemActivityStorage.append(activity)
    }

    public func loadRecentSystemActivities(limit: Int) async throws -> [SystemActivity] {
        Array(self.systemActivityStorage.suffix(limit))
    }

    public func deleteOldSystemActivities(olderThan date: Date) async throws {
        self.systemActivityStorage.removeAll { $0.timestamp < date }
    }

    // MARK: - Received File Methods

    public func saveReceivedFile(_ file: ReceivedFile) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.receivedFileStorage.append(file)
    }

    public func loadReceivedFiles() async throws -> [ReceivedFile] {
        self.receivedFileStorage
    }

    public func deleteReceivedFile(by id: UUID) async throws {
        self.receivedFileStorage.removeAll { $0.id == id }
    }

    public func deleteAllReceivedFiles() async throws {
        self.receivedFileStorage.removeAll()
    }

    // MARK: - Floor Map Methods

    public func saveFloorMap(_ floorMap: FloorMapInfo) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.floorMapStorage.append(floorMap)
    }

    public func loadAllFloorMaps() async throws -> [FloorMapInfo] {
        self.floorMapStorage
    }

    public func loadFloorMap(by id: String) async throws -> FloorMapInfo? {
        self.floorMapStorage.first { $0.id == id }
    }

    public func deleteFloorMap(by id: String) async throws {
        self.floorMapStorage.removeAll { $0.id == id }
    }

    public func setActiveFloorMap(id: String) async throws {
        // FloorMapInfoにisActiveプロパティがないため、テスト用のダミー実装
        // 実際の実装では別途アクティブなフロアマップを管理する
    }

    // MARK: - Project Progress Methods

    public func saveProjectProgress(_ progress: ProjectProgress) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        self.projectProgressStorage.append(progress)
    }

    public func loadProjectProgress(by id: String) async throws -> ProjectProgress? {
        self.projectProgressStorage.first { $0.id == id }
    }

    public func loadProjectProgress(for floorMapId: String) async throws -> ProjectProgress? {
        self.projectProgressStorage.first { $0.floorMapId == floorMapId }
    }

    public func loadAllProjectProgress() async throws -> [ProjectProgress] {
        self.projectProgressStorage
    }

    public func deleteProjectProgress(by id: String) async throws {
        self.projectProgressStorage.removeAll { $0.id == id }
    }

    public func updateProjectProgress(_ progress: ProjectProgress) async throws {
        if let index = projectProgressStorage.firstIndex(where: { $0.id == progress.id }) {
            self.projectProgressStorage[index] = progress
        }
    }

    // MARK: - Calibration Data Methods

    public func saveCalibrationData(_ data: CalibrationData) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        // JSONエンコードして安全に保存
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(data)
        self.calibrationDataStorage[data.antennaId] = encodedData
    }

    public func loadCalibrationData() async throws -> [CalibrationData] {
        let decoder = JSONDecoder()
        return self.calibrationDataStorage.values.compactMap { data in
            try? decoder.decode(CalibrationData.self, from: data)
        }
    }

    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        guard let data = calibrationDataStorage[antennaId] else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(CalibrationData.self, from: data)
    }

    public func deleteCalibrationData(for antennaId: String) async throws {
        self.calibrationDataStorage.removeValue(forKey: antennaId)
    }

    public func deleteAllCalibrationData() async throws {
        self.calibrationDataStorage.removeAll()
    }

    // MARK: - Map Calibration Data Methods

    public func saveMapCalibrationData(_ data: MapCalibrationData) async throws {
        if self.shouldThrowError { throw self.errorToThrow }
        let key = "\(data.antennaId)_\(data.floorMapId)"
        self.mapCalibrationDataStorage[key] = data
    }

    public func loadMapCalibrationData() async throws -> [MapCalibrationData] {
        Array(self.mapCalibrationDataStorage.values)
    }

    public func loadMapCalibrationData(for antennaId: String, floorMapId: String) async throws -> MapCalibrationData? {
        let key = "\(antennaId)_\(floorMapId)"
        return self.mapCalibrationDataStorage[key]
    }

    public func deleteMapCalibrationData(for antennaId: String, floorMapId: String) async throws {
        let key = "\(antennaId)_\(floorMapId)"
        self.mapCalibrationDataStorage.removeValue(forKey: key)
    }

    public func deleteAllMapCalibrationData() async throws {
        self.mapCalibrationDataStorage.removeAll()
    }

    // MARK: - Data Integrity Methods

    public func cleanupDuplicateAntennaPositions() async throws -> Int {
        // テスト用の実装：重複データを検出してクリーンアップ
        let grouped = Dictionary(grouping: antennaPositionStorage) { position in
            "\(position.antennaId)_\(position.floorMapId)"
        }

        var deletedCount = 0
        for (_, positions) in grouped {
            if positions.count > 1 {
                // 最新データ以外を削除
                let sorted = positions.sorted { $0.id > $1.id }
                let duplicates = Array(sorted.dropFirst())

                for duplicate in duplicates {
                    self.antennaPositionStorage.removeAll { $0.id == duplicate.id }
                    deletedCount += 1
                }
            }
        }

        return deletedCount
    }

    public func cleanupAllDuplicateData() async throws -> [String: Int] {
        var results: [String: Int] = [:]
        results["antennaPositions"] = try await self.cleanupDuplicateAntennaPositions()
        return results
    }

    public func validateDataIntegrity() async throws -> [String] {
        var issues: [String] = []

        // アンテナ位置データの重複チェック
        let duplicateGroups = Dictionary(grouping: antennaPositionStorage) { position in
            "\(position.antennaId)_\(position.floorMapId)"
        }.filter { $1.count > 1 }

        if !duplicateGroups.isEmpty {
            issues.append("重複するアンテナ位置データ: \(duplicateGroups.count)グループ")
        }

        // 無効なデータチェック
        let invalidPositions = self.antennaPositionStorage.filter { position in
            position.antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || position.antennaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || position.floorMapId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !invalidPositions.isEmpty {
            issues.append("無効なアンテナ位置データ: \(invalidPositions.count)件")
        }

        return issues
    }
}

// MARK: - Mock Preference Repository

public class MockPreferenceRepository: PreferenceRepositoryProtocol {

    // MARK: - Storage Properties

    private var storage: [String: Any] = [:]
    private let storageQueue = DispatchQueue(label: "MockPreferenceRepository.storage", attributes: .concurrent)

    // MARK: - Init

    public init() {}

    // MARK: - Thread-Safe Storage Access

    private func safeWrite(_ value: some Any, forKey key: String) {
        self.storageQueue.sync(flags: .barrier) {
            self.storage[key] = value
        }
    }

    private func safeRead<T>(forKey key: String, as type: T.Type) -> T? {
        self.storageQueue.sync {
            self.storage[key] as? T
        }
    }

    private func safeRemove(forKey key: String) {
        self.storageQueue.sync(flags: .barrier) {
            self.storage.removeValue(forKey: key)
        }
    }

    // MARK: - Floor Map Configuration Methods

    public func saveCurrentFloorMapInfo(_ info: FloorMapInfo) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(info)
            self.safeWrite(data, forKey: "currentFloorMapInfo")
        } catch {
            // Error encoding FloorMapInfo
        }
    }

    public func loadCurrentFloorMapInfo() -> FloorMapInfo? {
        guard let data = safeRead(forKey: "currentFloorMapInfo", as: Data.self) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(FloorMapInfo.self, from: data)
        } catch {
            // Error decoding FloorMapInfo
            return nil
        }
    }

    public func removeCurrentFloorMapInfo() {
        self.safeRemove(forKey: "currentFloorMapInfo")
    }

    public func saveLastFloorSettings(name: String, buildingName: String, width: Double, depth: Double) {
        self.safeWrite(name, forKey: "lastFloorName")
        self.safeWrite(buildingName, forKey: "lastBuildingName")
        self.safeWrite(width, forKey: "lastFloorWidth")
        self.safeWrite(depth, forKey: "lastFloorDepth")
    }

    public func loadLastFloorSettings() -> (name: String?, buildingName: String?, width: Double?, depth: Double?) {
        let name = self.safeRead(forKey: "lastFloorName", as: String.self)
        let buildingName = self.safeRead(forKey: "lastBuildingName", as: String.self)
        let width = self.safeRead(forKey: "lastFloorWidth", as: Double.self)
        let depth = self.safeRead(forKey: "lastFloorDepth", as: Double.self)
        return (name, buildingName, width, depth)
    }

    public func setHasFloorMapConfigured(_ configured: Bool) {
        self.safeWrite(configured, forKey: "hasFloorMapConfigured")
    }

    public func getHasFloorMapConfigured() -> Bool {
        self.safeRead(forKey: "hasFloorMapConfigured", as: Bool.self) ?? false
    }

    // MARK: - Antenna Configuration Methods

    public func saveConfiguredAntennaPositions(_ positions: [AntennaPositionData]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(positions)
            self.safeWrite(data, forKey: "configuredAntennaPositions")
        } catch {
            // Error encoding AntennaPositionData
        }
    }

    public func loadConfiguredAntennaPositions() -> [AntennaPositionData]? {
        guard let data = safeRead(forKey: "configuredAntennaPositions", as: Data.self) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([AntennaPositionData].self, from: data)
        } catch {
            // Error decoding AntennaPositionData
            return nil
        }
    }

    public func removeConfiguredAntennaPositions() {
        self.safeRemove(forKey: "configuredAntennaPositions")
    }

    // MARK: - Calibration Results Methods

    public func saveLastCalibrationResult(_ result: SystemCalibrationResult) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(result)
            self.safeWrite(data, forKey: "lastCalibrationResult")
        } catch {
            // Error encoding SystemCalibrationResult
        }
    }

    public func loadLastCalibrationResult() -> SystemCalibrationResult? {
        guard let data = safeRead(forKey: "lastCalibrationResult", as: Data.self) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(SystemCalibrationResult.self, from: data)
        } catch {
            // Error decoding SystemCalibrationResult
            return nil
        }
    }

    public func removeLastCalibrationResult() {
        self.safeRemove(forKey: "lastCalibrationResult")
    }

    // MARK: - Sensing Flow State Methods

    public func saveSensingFlowState(currentStep: String, completedSteps: [String], isCompleted: Bool) {
        self.safeWrite(currentStep, forKey: "sensingFlowCurrentStep")
        self.safeWrite(completedSteps, forKey: "sensingFlowCompletedSteps")
        self.safeWrite(isCompleted, forKey: "sensingFlowIsCompleted")
    }

    public func loadSensingFlowState() -> (currentStep: String?, completedSteps: [String], isCompleted: Bool) {
        let currentStep = self.safeRead(forKey: "sensingFlowCurrentStep", as: String.self)
        let completedSteps = self.safeRead(forKey: "sensingFlowCompletedSteps", as: [String].self) ?? []
        let isCompleted = self.safeRead(forKey: "sensingFlowIsCompleted", as: Bool.self) ?? false
        return (currentStep, completedSteps, isCompleted)
    }

    public func resetSensingFlowState() {
        self.safeRemove(forKey: "sensingFlowCurrentStep")
        self.safeRemove(forKey: "sensingFlowCompletedSteps")
        self.safeRemove(forKey: "sensingFlowIsCompleted")
    }

    public func setHasExecutedSensingSession(_ executed: Bool) {
        self.safeWrite(executed, forKey: "hasExecutedSensingSession")
    }

    public func getHasExecutedSensingSession() -> Bool {
        self.safeRead(forKey: "hasExecutedSensingSession", as: Bool.self) ?? false
    }

    // MARK: - Device Management Methods

    public func savePairedDevices(_ devices: [String]) {
        self.safeWrite(devices, forKey: "pairedDevices")
    }

    public func loadPairedDevices() -> [String]? {
        self.safeRead(forKey: "pairedDevices", as: [String].self)
    }

    public func removePairedDevices() {
        self.safeRemove(forKey: "pairedDevices")
    }

    public func saveConnectionStatistics(_ statistics: [String: Any]) {
        self.safeWrite(statistics, forKey: "connectionStatistics")
    }

    public func loadConnectionStatistics() -> [String: Any]? {
        self.safeRead(forKey: "connectionStatistics", as: [String: Any].self)
    }

    // MARK: - Migration Methods

    public func setMigrationCompleted(for key: String, completed: Bool) {
        self.safeWrite(completed, forKey: "migration_\(key)")
    }

    public func isMigrationCompleted(for key: String) -> Bool {
        self.safeRead(forKey: "migration_\(key)", as: Bool.self) ?? false
    }

    // MARK: - Generic Methods

    public func setBool(_ value: Bool, forKey key: String) {
        self.safeWrite(value, forKey: key)
    }

    public func getBool(forKey key: String) -> Bool {
        self.safeRead(forKey: key, as: Bool.self) ?? false
    }

    public func setString(_ value: String?, forKey key: String) {
        if let value {
            self.safeWrite(value, forKey: key)
        } else {
            self.safeRemove(forKey: key)
        }
    }

    public func getString(forKey key: String) -> String? {
        self.safeRead(forKey: key, as: String.self)
    }

    public func setDouble(_ value: Double, forKey key: String) {
        self.safeWrite(value, forKey: key)
    }

    public func getDouble(forKey key: String) -> Double {
        self.safeRead(forKey: key, as: Double.self) ?? 0.0
    }

    public func setData(_ value: some Codable, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        self.safeWrite(data, forKey: key)
    }

    public func getData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = safeRead(forKey: key, as: Data.self) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            // Error decoding data
            return nil
        }
    }

    public func removeObject(forKey key: String) {
        self.safeRemove(forKey: key)
    }
}
