import Foundation
import SwiftData

// MARK: - SwiftData用Repository

public protocol SwiftDataRepositoryProtocol {
    // センシングセッション関連
    func saveSensingSession(_ session: SensingSession) async throws
    func loadSensingSession(by id: String) async throws -> SensingSession?
    func loadAllSensingSessions() async throws -> [SensingSession]
    func deleteSensingSession(by id: String) async throws
    func updateSensingSession(_ session: SensingSession) async throws

    // アンテナ位置関連
    func saveAntennaPosition(_ position: AntennaPositionData) async throws
    func loadAntennaPositions() async throws -> [AntennaPositionData]
    func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData]
    func deleteAntennaPosition(by id: String) async throws
    func updateAntennaPosition(_ position: AntennaPositionData) async throws

    // ペアリング関連
    func saveAntennaPairing(_ pairing: AntennaPairing) async throws
    func loadAntennaPairings() async throws -> [AntennaPairing]
    func deleteAntennaPairing(by id: String) async throws
    func updateAntennaPairing(_ pairing: AntennaPairing) async throws

    // リアルタイムデータ関連
    func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws
    func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData]
    func deleteRealtimeData(by id: UUID) async throws

    // システム活動履歴関連
    func saveSystemActivity(_ activity: SystemActivity) async throws
    func loadRecentSystemActivities(limit: Int) async throws -> [SystemActivity]
    func deleteOldSystemActivities(olderThan date: Date) async throws

    // 受信ファイル関連
    func saveReceivedFile(_ file: ReceivedFile) async throws
    func loadReceivedFiles() async throws -> [ReceivedFile]
    func deleteReceivedFile(by id: UUID) async throws
    func deleteAllReceivedFiles() async throws

    // フロアマップ関連
    func saveFloorMap(_ floorMap: FloorMapInfo) async throws
    func loadAllFloorMaps() async throws -> [FloorMapInfo]
    func loadFloorMap(by id: String) async throws -> FloorMapInfo?
    func deleteFloorMap(by id: String) async throws
    func setActiveFloorMap(id: String) async throws

    // プロジェクト進行状況関連
    func saveProjectProgress(_ progress: ProjectProgress) async throws
    func loadProjectProgress(by id: String) async throws -> ProjectProgress?
    func loadProjectProgress(for floorMapId: String) async throws -> ProjectProgress?
    func loadAllProjectProgress() async throws -> [ProjectProgress]
    func deleteProjectProgress(by id: String) async throws
    func updateProjectProgress(_ progress: ProjectProgress) async throws

    // キャリブレーション関連
    func saveCalibrationData(_ data: CalibrationData) async throws
    func loadCalibrationData() async throws -> [CalibrationData]
    func loadCalibrationData(for antennaId: String) async throws -> CalibrationData?
    func deleteCalibrationData(for antennaId: String) async throws
    func deleteAllCalibrationData() async throws

    // MARK: - マップベースキャリブレーション関連

    func saveMapCalibrationData(_ data: MapCalibrationData) async throws
    func loadMapCalibrationData() async throws -> [MapCalibrationData]
    func loadMapCalibrationData(for antennaId: String, floorMapId: String) async throws -> MapCalibrationData?
    func deleteMapCalibrationData(for antennaId: String, floorMapId: String) async throws
    func deleteAllMapCalibrationData() async throws
}

@MainActor
@available(macOS 14, iOS 17, *)
public class SwiftDataRepository: SwiftDataRepositoryProtocol {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - センシングセッション関連

    public func saveSensingSession(_ session: SensingSession) async throws {
        let persistentSession = session.toPersistent()
        modelContext.insert(persistentSession)
        try modelContext.save()
    }

    public func loadSensingSession(by id: String) async throws -> SensingSession? {
        let predicate = #Predicate<PersistentSensingSession> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentSensingSession>(predicate: predicate)

        let sessions = try modelContext.fetch(descriptor)
        return sessions.first?.toEntity()
    }

    public func loadAllSensingSessions() async throws -> [SensingSession] {
        let descriptor = FetchDescriptor<PersistentSensingSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        let persistentSessions = try modelContext.fetch(descriptor)
        return persistentSessions.map { $0.toEntity() }
    }

    public func deleteSensingSession(by id: String) async throws {
        let predicate = #Predicate<PersistentSensingSession> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentSensingSession>(predicate: predicate)

        let sessions = try modelContext.fetch(descriptor)
        for session in sessions {
            modelContext.delete(session)
        }
        try modelContext.save()
    }

    public func updateSensingSession(_ session: SensingSession) async throws {
        let predicate = #Predicate<PersistentSensingSession> { $0.id == session.id }
        let descriptor = FetchDescriptor<PersistentSensingSession>(predicate: predicate)

        let existingSessions = try modelContext.fetch(descriptor)
        if let existingSession = existingSessions.first {
            existingSession.name = session.name
            existingSession.startTime = session.startTime
            existingSession.endTime = session.endTime
            existingSession.isActive = session.isActive
            try modelContext.save()
        }
    }

    // MARK: - アンテナ位置関連

    public func saveAntennaPosition(_ position: AntennaPositionData) async throws {
        let persistentPosition = position.toPersistent()
        modelContext.insert(persistentPosition)
        try modelContext.save()
    }

    public func loadAntennaPositions() async throws -> [AntennaPositionData] {
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(
            sortBy: [SortDescriptor(\.antennaName)]
        )

        let persistentPositions = try modelContext.fetch(descriptor)
        return persistentPositions.map { $0.toEntity() }
    }

    public func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] {
        let predicate = #Predicate<PersistentAntennaPosition> { $0.floorMapId == floorMapId }
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.antennaName)]
        )

        let persistentPositions = try modelContext.fetch(descriptor)
        return persistentPositions.map { $0.toEntity() }
    }

    public func deleteAntennaPosition(by id: String) async throws {
        // antennaIdで検索
        let predicate = #Predicate<PersistentAntennaPosition> { $0.antennaId == id }
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)

        let positions = try modelContext.fetch(descriptor)
        print("🗑️ SwiftDataRepository: アンテナID[\(id)]で検索、\(positions.count)件見つかりました")

        for position in positions {
            print("🗑️ SwiftDataRepository: 削除中 - ID: \(position.id), AntennaID: \(position.antennaId), Name: \(position.antennaName)")
            modelContext.delete(position)
        }
        try modelContext.save()
        print("🗑️ SwiftDataRepository: アンテナ位置削除完了")
    }

    public func updateAntennaPosition(_ position: AntennaPositionData) async throws {
        let predicate = #Predicate<PersistentAntennaPosition> { $0.id == position.id }
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)

        let existingPositions = try modelContext.fetch(descriptor)
        if let existingPosition = existingPositions.first {
            existingPosition.antennaId = position.antennaId
            existingPosition.antennaName = position.antennaName
            existingPosition.x = position.position.x
            existingPosition.y = position.position.y
            existingPosition.z = position.position.z
            existingPosition.rotation = position.rotation
            try modelContext.save()
        }
    }

    // MARK: - ペアリング関連

    public func saveAntennaPairing(_ pairing: AntennaPairing) async throws {
        let persistentPairing = pairing.toPersistent()
        modelContext.insert(persistentPairing)
        try modelContext.save()
    }

    public func loadAntennaPairings() async throws -> [AntennaPairing] {
        let descriptor = FetchDescriptor<PersistentAntennaPairing>(
            sortBy: [SortDescriptor(\.pairedAt, order: .reverse)]
        )

        let persistentPairings = try modelContext.fetch(descriptor)
        return persistentPairings.map { $0.toEntity() }
    }

    public func deleteAntennaPairing(by id: String) async throws {
        let predicate = #Predicate<PersistentAntennaPairing> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentAntennaPairing>(predicate: predicate)

        let pairings = try modelContext.fetch(descriptor)
        for pairing in pairings {
            modelContext.delete(pairing)
        }
        try modelContext.save()
    }

    public func updateAntennaPairing(_ pairing: AntennaPairing) async throws {
        let predicate = #Predicate<PersistentAntennaPairing> { $0.id == pairing.id }
        let descriptor = FetchDescriptor<PersistentAntennaPairing>(predicate: predicate)

        let existingPairings = try modelContext.fetch(descriptor)
        if let existingPairing = existingPairings.first {
            existingPairing.deviceName = pairing.device.name
            existingPairing.isConnected = pairing.device.isConnected
            try modelContext.save()
        }
    }

    // MARK: - リアルタイムデータ関連

    public func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws {
        let persistentData = data.toPersistent()

        // リレーションシップを削除したため、セッション関連付けはコメントアウト
        // let sessionPredicate = #Predicate<PersistentSensingSession> { $0.id == sessionId }
        // let sessionDescriptor = FetchDescriptor<PersistentSensingSession>(predicate: sessionPredicate)
        // let sessions = try modelContext.fetch(sessionDescriptor)

        // if let session = sessions.first {
        //     persistentData.session = session
        // }

        modelContext.insert(persistentData)
        try modelContext.save()
    }

    public func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] {
        // リレーションシップを削除したため、簡易的に全てのデータを返す（将来的にsessionIdフィールドで絞り込む）
        // let predicate = #Predicate<PersistentRealtimeData> { $0.session?.id == sessionId }
        let descriptor = FetchDescriptor<PersistentRealtimeData>(
            // predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let persistentData = try modelContext.fetch(descriptor)
        return persistentData.map { $0.toEntity() }
    }

    public func deleteRealtimeData(by id: UUID) async throws {
        let predicate = #Predicate<PersistentRealtimeData> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentRealtimeData>(predicate: predicate)

        let data = try modelContext.fetch(descriptor)
        for item in data {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    // MARK: - システム活動履歴関連

    public func saveSystemActivity(_ activity: SystemActivity) async throws {
        let persistentActivity = activity.toPersistent()
        modelContext.insert(persistentActivity)
        try modelContext.save()
    }

    public func loadRecentSystemActivities(limit: Int = 50) async throws -> [SystemActivity] {
        var descriptor = FetchDescriptor<PersistentSystemActivity>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let persistentActivities = try modelContext.fetch(descriptor)
        return persistentActivities.map { $0.toEntity() }
    }

    public func deleteOldSystemActivities(olderThan date: Date) async throws {
        let predicate = #Predicate<PersistentSystemActivity> { $0.timestamp < date }
        let descriptor = FetchDescriptor<PersistentSystemActivity>(predicate: predicate)

        let activities = try modelContext.fetch(descriptor)
        for activity in activities {
            modelContext.delete(activity)
        }
        try modelContext.save()
    }

    // MARK: - 受信ファイル関連

    public func saveReceivedFile(_ file: ReceivedFile) async throws {
        let persistentFile = file.toPersistent()
        modelContext.insert(persistentFile)
        try modelContext.save()
    }

    public func loadReceivedFiles() async throws -> [ReceivedFile] {
        let descriptor = FetchDescriptor<PersistentReceivedFile>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )

        let persistentFiles = try modelContext.fetch(descriptor)
        return persistentFiles.map { $0.toEntity() }
    }

    public func deleteReceivedFile(by id: UUID) async throws {
        let predicate = #Predicate<PersistentReceivedFile> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentReceivedFile>(predicate: predicate)

        let files = try modelContext.fetch(descriptor)
        for file in files {
            modelContext.delete(file)
        }
        try modelContext.save()
    }

    public func deleteAllReceivedFiles() async throws {
        let descriptor = FetchDescriptor<PersistentReceivedFile>()

        let files = try modelContext.fetch(descriptor)
        for file in files {
            modelContext.delete(file)
        }
        try modelContext.save()
    }

    // MARK: - フロアマップ関連

    public func saveFloorMap(_ floorMap: FloorMapInfo) async throws {
        let persistentFloorMap = floorMap.toPersistent()
        modelContext.insert(persistentFloorMap)
        try modelContext.save()

        // 保存の確認のためログ出力
        print("📊 SwiftDataRepository: フロアマップ保存完了 - ID: \(floorMap.id), Name: \(floorMap.name)")
    }

    public func loadAllFloorMaps() async throws -> [FloorMapInfo] {
        let descriptor = FetchDescriptor<PersistentFloorMap>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let persistentFloorMaps = try modelContext.fetch(descriptor)
        let floorMaps = persistentFloorMaps.map { $0.toEntity() }

        print("📊 SwiftDataRepository: フロアマップ読み込み完了 - \(floorMaps.count)件")
        for floorMap in floorMaps {
            print("  - ID: \(floorMap.id), Name: \(floorMap.name)")
        }

        return floorMaps
    }

    public func loadFloorMap(by id: String) async throws -> FloorMapInfo? {
        let predicate = #Predicate<PersistentFloorMap> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentFloorMap>(predicate: predicate)

        let floorMaps = try modelContext.fetch(descriptor)
        return floorMaps.first?.toEntity()
    }

    public func deleteFloorMap(by id: String) async throws {
        let predicate = #Predicate<PersistentFloorMap> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentFloorMap>(predicate: predicate)

        let floorMaps = try modelContext.fetch(descriptor)
        for floorMap in floorMaps {
            modelContext.delete(floorMap)
        }
        try modelContext.save()
    }

    public func setActiveFloorMap(id: String) async throws {
        // すべてのフロアマップを非アクティブに
        let allDescriptor = FetchDescriptor<PersistentFloorMap>()
        let allFloorMaps = try modelContext.fetch(allDescriptor)

        for floorMap in allFloorMaps {
            floorMap.isActive = (floorMap.id == id)
        }

        try modelContext.save()
    }

    // MARK: - プロジェクト進行状況関連

    public func saveProjectProgress(_ progress: ProjectProgress) async throws {
        let persistentProgress = progress.toPersistent()
        modelContext.insert(persistentProgress)
        try modelContext.save()
    }

    public func loadProjectProgress(by id: String) async throws -> ProjectProgress? {
        let predicate = #Predicate<PersistentProjectProgress> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentProjectProgress>(predicate: predicate)

        let progresses = try modelContext.fetch(descriptor)
        return progresses.first?.toEntity()
    }

    public func loadProjectProgress(for floorMapId: String) async throws -> ProjectProgress? {
        let predicate = #Predicate<PersistentProjectProgress> { $0.floorMapId == floorMapId }
        let descriptor = FetchDescriptor<PersistentProjectProgress>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let progresses = try modelContext.fetch(descriptor)
        return progresses.first?.toEntity()
    }

    public func loadAllProjectProgress() async throws -> [ProjectProgress] {
        let descriptor = FetchDescriptor<PersistentProjectProgress>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let persistentProgresses = try modelContext.fetch(descriptor)
        return persistentProgresses.map { $0.toEntity() }
    }

    public func deleteProjectProgress(by id: String) async throws {
        let predicate = #Predicate<PersistentProjectProgress> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentProjectProgress>(predicate: predicate)

        let progresses = try modelContext.fetch(descriptor)
        for progress in progresses {
            modelContext.delete(progress)
        }
        try modelContext.save()
    }

    public func updateProjectProgress(_ progress: ProjectProgress) async throws {
        let predicate = #Predicate<PersistentProjectProgress> { $0.id == progress.id }
        let descriptor = FetchDescriptor<PersistentProjectProgress>(predicate: predicate)

        let existingProgresses = try modelContext.fetch(descriptor)
        if let existingProgress = existingProgresses.first {
            // 既存のプロジェクト進行状況を更新
            existingProgress.currentStep = progress.currentStep.rawValue
            existingProgress.updatedAt = progress.updatedAt

            // completedStepsの更新
            let encoder = JSONEncoder()
            let stepStrings = progress.completedSteps.map { $0.rawValue }
            existingProgress.completedStepsData = (try? encoder.encode(stepStrings)) ?? Data()

            // stepDataの更新
            existingProgress.stepData = (try? encoder.encode(progress.stepData)) ?? Data()

            try modelContext.save()
        } else {
            // 存在しない場合は新規作成
            try await saveProjectProgress(progress)
        }
    }

    // MARK: - キャリブレーション関連

    public func saveCalibrationData(_ data: CalibrationData) async throws {
        // 既存のデータがあるかチェック
        let predicate = #Predicate<PersistentCalibrationData> { $0.antennaId == data.antennaId }
        let descriptor = FetchDescriptor<PersistentCalibrationData>(predicate: predicate)

        let existingData = try modelContext.fetch(descriptor).first

        if let existing = existingData {
            // 既存データを更新
            let encoder = JSONEncoder()

            existing.calibrationPointsData = (try? encoder.encode(data.calibrationPoints)) ?? Data()

            if let transform = data.transform {
                existing.transformData = try? encoder.encode(transform)
            } else {
                existing.transformData = nil
            }

            existing.updatedAt = data.updatedAt
            existing.isActive = data.isActive

            try modelContext.save()
        } else {
            // 新規作成
            let persistentData = data.toPersistent()
            modelContext.insert(persistentData)
            try modelContext.save()
        }
    }

    public func loadCalibrationData() async throws -> [CalibrationData] {
        let descriptor = FetchDescriptor<PersistentCalibrationData>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let persistentData = try modelContext.fetch(descriptor)
        return persistentData.map { $0.toEntity() }
    }

    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? {
        let predicate = #Predicate<PersistentCalibrationData> {
            $0.antennaId == antennaId && $0.isActive == true
        }
        let descriptor = FetchDescriptor<PersistentCalibrationData>(predicate: predicate)

        let persistentData = try modelContext.fetch(descriptor)
        return persistentData.first?.toEntity()
    }

    public func deleteCalibrationData(for antennaId: String) async throws {
        let predicate = #Predicate<PersistentCalibrationData> { $0.antennaId == antennaId }
        let descriptor = FetchDescriptor<PersistentCalibrationData>(predicate: predicate)

        let dataToDelete = try modelContext.fetch(descriptor)
        for data in dataToDelete {
            modelContext.delete(data)
        }
        try modelContext.save()
    }

    public func deleteAllCalibrationData() async throws {
        let descriptor = FetchDescriptor<PersistentCalibrationData>()
        let allData = try modelContext.fetch(descriptor)

        for data in allData {
            modelContext.delete(data)
        }
        try modelContext.save()
    }

    // MARK: - マップベースキャリブレーション関連

    public func saveMapCalibrationData(_ data: MapCalibrationData) async throws {
        // 既存データをチェック
        let predicate = #Predicate<PersistentMapCalibrationData> {
            $0.antennaId == data.antennaId && $0.floorMapId == data.floorMapId
        }
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>(predicate: predicate)

        let existingData = try modelContext.fetch(descriptor)

        if let existing = existingData.first {
            // 既存データを更新
            let encoder = JSONEncoder()
            existing.calibrationPointsData = (try? encoder.encode(data.calibrationPoints)) ?? Data()

            if let transform = data.affineTransform {
                existing.affineTransformData = try? encoder.encode(transform)
            } else {
                existing.affineTransformData = nil
            }
            existing.updatedAt = data.updatedAt
            existing.isActive = data.isActive
        } else {
            // 新規データを挿入
            let persistentData = data.toPersistent()
            modelContext.insert(persistentData)
        }

        try modelContext.save()

        print("🗄️ SwiftDataRepository: マップキャリブレーションデータ保存完了 - アンテナ: \(data.antennaId), フロアマップ: \(data.floorMapId)")
    }

    public func loadMapCalibrationData() async throws -> [MapCalibrationData] {
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let persistentData = try modelContext.fetch(descriptor)
        let mapCalibrationData = persistentData.map { $0.toEntity() }

        print("🗄️ SwiftDataRepository: マップキャリブレーションデータ読み込み完了 - \(mapCalibrationData.count)件")
        return mapCalibrationData
    }

    public func loadMapCalibrationData(for antennaId: String, floorMapId: String) async throws -> MapCalibrationData? {
        let predicate = #Predicate<PersistentMapCalibrationData> {
            $0.antennaId == antennaId && $0.floorMapId == floorMapId
        }
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>(predicate: predicate)

        let results = try modelContext.fetch(descriptor)
        return results.first?.toEntity()
    }

    public func deleteMapCalibrationData(for antennaId: String, floorMapId: String) async throws {
        let predicate = #Predicate<PersistentMapCalibrationData> {
            $0.antennaId == antennaId && $0.floorMapId == floorMapId
        }
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>(predicate: predicate)

        let dataToDelete = try modelContext.fetch(descriptor)
        for data in dataToDelete {
            modelContext.delete(data)
        }
        try modelContext.save()
    }

    public func deleteAllMapCalibrationData() async throws {
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>()
        let allData = try modelContext.fetch(descriptor)

        for data in allData {
            modelContext.delete(data)
        }
        try modelContext.save()
    }
}

// MARK: - Dummy Repository for Initialization

/// ViewModelの初期化時に使用するダミーリポジトリ
/// 実際のModelContextが利用可能になったら実装されたリポジトリに置き換える
@available(macOS 14, iOS 17, *)
public class DummySwiftDataRepository: SwiftDataRepositoryProtocol {
    public init() {}

    public func saveSensingSession(_ session: SensingSession) async throws {}
    public func loadSensingSession(by id: String) async throws -> SensingSession? { nil }
    public func loadAllSensingSessions() async throws -> [SensingSession] { [] }
    public func deleteSensingSession(by id: String) async throws {}
    public func updateSensingSession(_ session: SensingSession) async throws {}
    public func saveAntennaPosition(_ position: AntennaPositionData) async throws {}
    public func loadAntennaPositions() async throws -> [AntennaPositionData] { [] }
    public func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] { [] }
    public func deleteAntennaPosition(by id: String) async throws {}
    public func updateAntennaPosition(_ position: AntennaPositionData) async throws {}
    public func saveAntennaPairing(_ pairing: AntennaPairing) async throws {}
    public func loadAntennaPairings() async throws -> [AntennaPairing] { [] }
    public func deleteAntennaPairing(by id: String) async throws {}
    public func updateAntennaPairing(_ pairing: AntennaPairing) async throws {}
    public func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws {}
    public func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] { [] }
    public func deleteRealtimeData(by id: UUID) async throws {}
    public func saveSystemActivity(_ activity: SystemActivity) async throws {}
    public func loadRecentSystemActivities(limit: Int) async throws -> [SystemActivity] { [] }
    public func deleteOldSystemActivities(olderThan date: Date) async throws {}
    public func saveReceivedFile(_ file: ReceivedFile) async throws {}
    public func loadReceivedFiles() async throws -> [ReceivedFile] { [] }
    public func deleteReceivedFile(by id: UUID) async throws {}
    public func deleteAllReceivedFiles() async throws {}
    public func saveFloorMap(_ floorMap: FloorMapInfo) async throws {}
    public func loadAllFloorMaps() async throws -> [FloorMapInfo] { [] }
    public func loadFloorMap(by id: String) async throws -> FloorMapInfo? { nil }
    public func deleteFloorMap(by id: String) async throws {}
    public func setActiveFloorMap(id: String) async throws {}
    public func saveProjectProgress(_ progress: ProjectProgress) async throws {}
    public func loadProjectProgress(by id: String) async throws -> ProjectProgress? { nil }
    public func loadProjectProgress(for floorMapId: String) async throws -> ProjectProgress? { nil }
    public func loadAllProjectProgress() async throws -> [ProjectProgress] { [] }
    public func deleteProjectProgress(by id: String) async throws {}
    public func updateProjectProgress(_ progress: ProjectProgress) async throws {}

    // キャリブレーション関連
    public func saveCalibrationData(_ data: CalibrationData) async throws {}
    public func loadCalibrationData() async throws -> [CalibrationData] { [] }
    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? { nil }
    public func deleteCalibrationData(for antennaId: String) async throws {}
    public func deleteAllCalibrationData() async throws {}

    // マップベースキャリブレーション関連
    public func saveMapCalibrationData(_ data: MapCalibrationData) async throws {}
    public func loadMapCalibrationData() async throws -> [MapCalibrationData] { [] }
    public func loadMapCalibrationData(for antennaId: String, floorMapId: String) async throws -> MapCalibrationData? { nil }
    public func deleteMapCalibrationData(for antennaId: String, floorMapId: String) async throws {}
    public func deleteAllMapCalibrationData() async throws {}
}
