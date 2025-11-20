import Foundation
import SwiftData

// MARK: - SwiftData用Repository

// MARK: - Repository Errors

/// リポジトリ層のエラー定義
public enum RepositoryError: LocalizedError {
    case invalidData(String)
    case duplicateEntry(String)
    case notFound(String)
    case saveFailed(String)
    case deleteFailed(String)
    case loadFailed(String)
    case connectionFailed(String)
    case transactionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData(let message):
            return "無効なデータ: \(message)"
        case .duplicateEntry(let message):
            return "重複エントリ: \(message)"
        case .notFound(let message):
            return "データが見つかりません: \(message)"
        case .saveFailed(let message):
            return "保存に失敗しました: \(message)"
        case .deleteFailed(let message):
            return "削除に失敗しました: \(message)"
        case .loadFailed(let message):
            return "読み込みに失敗しました: \(message)"
        case .connectionFailed(let message):
            return "接続に失敗しました: \(message)"
        case .transactionFailed(let message):
            return "トランザクション処理に失敗しました: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidData:
            return "入力データを確認してください。"
        case .duplicateEntry:
            return "既存のデータを確認して重複を解消してください。"
        case .notFound:
            return "データが存在するか確認してください。"
        case .saveFailed, .deleteFailed, .loadFailed:
            return "操作を再試行するか、アプリケーションを再起動してください。"
        case .connectionFailed:
            return "データベース接続を確認してください。"
        case .transactionFailed:
            return "処理を再試行してください。"
        }
    }
}

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

    // MARK: - データ整合性機能

    func cleanupDuplicateAntennaPositions() async throws -> Int
    func cleanupAllDuplicateData() async throws -> [String: Int]
    func validateDataIntegrity() async throws -> [String]
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
        guard !session.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("センシングセッションIDが空です")
        }

        guard !session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("センシングセッション名が空です")
        }

        do {
            // 重複チェック
            let existingSession = try await loadSensingSession(by: session.id)
            if existingSession != nil {
                throw RepositoryError.duplicateEntry("IDが重複するセンシングセッションが既に存在します: \(session.id)")
            }

            let persistentSession = session.toPersistent()
            self.modelContext.insert(persistentSession)

            try self.modelContext.save()
            #if DEBUG
                print("✅ センシングセッション保存完了: \(session.name) (ID: \(session.id))")
            #endif
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.saveFailed("センシングセッションの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    public func loadSensingSession(by id: String) async throws -> SensingSession? {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("センシングセッションIDが空です")
        }

        do {
            let predicate = #Predicate<PersistentSensingSession> { $0.id == id }
            let descriptor = FetchDescriptor<PersistentSensingSession>(predicate: predicate)

            let sessions = try modelContext.fetch(descriptor)
            if sessions.count > 1 {
                #if DEBUG
                    print("⚠️ 重複するセンシングセッションが見つかりました: \(sessions.count)件")
                #endif
            }

            return sessions.first?.toEntity()
        } catch {
            throw RepositoryError.loadFailed("センシングセッションの読み込みに失敗しました: \(error.localizedDescription)")
        }
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
            self.modelContext.delete(session)
        }
        try self.modelContext.save()
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
            try self.modelContext.save()
        }
    }

    // MARK: - アンテナ位置関連

    public func saveAntennaPosition(_ position: AntennaPositionData) async throws {
        guard !position.antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("アンテナIDが空です")
        }

        guard !position.antennaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("アンテナ名が空です")
        }

        guard !position.floorMapId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("フロアマップIDが空です")
        }

        do {
            // 同じアンテナID + フロアマップIDの組み合わせをすべて検索
            let predicate = #Predicate<PersistentAntennaPosition> {
                $0.antennaId == position.antennaId && $0.floorMapId == position.floorMapId
            }
            let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)
            let existingPositions = try modelContext.fetch(descriptor)

            if !existingPositions.isEmpty {
                // 重複データが存在する場合
                if existingPositions.count > 1 {
                    #if DEBUG
                        print("⚠️ 重複するアンテナ位置データが見つかりました: \(existingPositions.count)件。最新データ以外を削除します。")
                    #endif

                    // 最新データを保持し、他は削除
                    let sortedPositions = existingPositions.sorted { pos1, pos2 in
                        // idの文字列比較で最新を判定（UUIDの場合、より良い方法があれば変更可能）
                        pos1.id > pos2.id
                    }

                    let latestPosition = sortedPositions.first!
                    let duplicatesToDelete = Array(sortedPositions.dropFirst())

                    for duplicate in duplicatesToDelete {
                        #if DEBUG
                            print("🗑️ 重複データを削除: ID=\(duplicate.id), Name=\(duplicate.antennaName)")
                        #endif
                        self.modelContext.delete(duplicate)
                    }

                    // 最新データを更新
                    latestPosition.antennaName = position.antennaName
                    latestPosition.x = position.position.x
                    latestPosition.y = position.position.y
                    latestPosition.z = position.position.z
                    latestPosition.rotation = position.rotation

                    try self.modelContext.save()
                    #if DEBUG
                        print("🔄 アンテナ位置を更新しました（重複削除後）: \(position.antennaName)")
                    #endif
                } else {
                    // 単一の既存データを更新
                    let existingPosition = existingPositions.first!
                    existingPosition.antennaName = position.antennaName
                    existingPosition.x = position.position.x
                    existingPosition.y = position.position.y
                    existingPosition.z = position.position.z
                    existingPosition.rotation = position.rotation

                    try self.modelContext.save()
                    #if DEBUG
                        print("🔄 アンテナ位置を更新しました: \(position.antennaName)")
                    #endif
                }
            } else {
                // 新規データとして保存
                let persistentPosition = position.toPersistent()
                self.modelContext.insert(persistentPosition)

                try self.modelContext.save()
                #if DEBUG
                    print("✅ アンテナ位置保存完了: \(position.antennaName) (ID: \(position.antennaId))")
                #endif
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.saveFailed("アンテナ位置の保存に失敗しました: \(error.localizedDescription)")
        }
    }

    public func loadAntennaPositions() async throws -> [AntennaPositionData] {
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(
            sortBy: [SortDescriptor(\.antennaName)]
        )

        let persistentPositions = try modelContext.fetch(descriptor)
        return persistentPositions.map { $0.toEntity() }
    }

    public func loadAntennaPositions(for floorMapId: String) async throws -> [AntennaPositionData] {
        guard !floorMapId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("フロアマップIDが空です")
        }

        do {
            let predicate = #Predicate<PersistentAntennaPosition> { $0.floorMapId == floorMapId }
            let descriptor = FetchDescriptor<PersistentAntennaPosition>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.antennaName)]
            )

            let persistentPositions = try modelContext.fetch(descriptor)
            let positions = persistentPositions.compactMap { persistentPosition -> AntennaPositionData? in
                // データ整合性チェック
                guard !persistentPosition.antennaId.isEmpty,
                      !persistentPosition.antennaName.isEmpty,
                      !persistentPosition.floorMapId.isEmpty
                else {
                    #if DEBUG
                        print("⚠️ 無効なアンテナ位置データをスキップしました: ID=\(persistentPosition.id)")
                    #endif
                    return nil
                }

                return persistentPosition.toEntity()
            }

            #if DEBUG
                print("✅ アンテナ位置データ読み込み完了: \(positions.count)件 (フロアマップ: \(floorMapId))")
            #endif
            return positions
        } catch {
            throw RepositoryError.loadFailed("アンテナ位置データの読み込みに失敗しました: \(error.localizedDescription)")
        }
    }

    public func deleteAntennaPosition(by id: String) async throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("アンテナIDが空です")
        }

        do {
            // idで検索（antennaIdではなく）
            let predicate = #Predicate<PersistentAntennaPosition> { $0.id == id }
            let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)

            let positions = try modelContext.fetch(descriptor)

            guard !positions.isEmpty else {
                throw RepositoryError.notFound("指定されたID[\(id)]のデータが見つかりません")
            }

            #if DEBUG
                print("🗑️ SwiftDataRepository: ID[\(id)]で検索、\(positions.count)件見つかりました")
            #endif

            if positions.count > 1 {
                #if DEBUG
                    print("⚠️ 重複するアンテナ位置データが見つかりました: \(positions.count)件")
                #endif
            }

            for position in positions {
                #if DEBUG
                    print(
                        "🗑️ SwiftDataRepository: 削除中 - ID: \(position.id), AntennaID: \(position.antennaId), Name: \(position.antennaName)"
                    )
                #endif
                self.modelContext.delete(position)
            }

            try self.modelContext.save()
            #if DEBUG
                print("✅ アンテナ位置削除完了: \(positions.count)件")
            #endif
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.deleteFailed("アンテナ位置の削除に失敗しました: \(error.localizedDescription)")
        }
    }

    public func deleteAllAntennaPositions(for floorMapId: String) async throws {
        let predicate = #Predicate<PersistentAntennaPosition> { $0.floorMapId == floorMapId }
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)
        let positions = try modelContext.fetch(descriptor)

        #if DEBUG
            print("🗑️ SwiftDataRepository: フロアマップ[\(floorMapId)]のアンテナ位置データを一括削除: \(positions.count)件")
        #endif

        for position in positions {
            self.modelContext.delete(position)
        }

        try self.modelContext.save()

        #if DEBUG
            print("✅ アンテナ位置データ一括削除完了: \(positions.count)件")
        #endif
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
            try self.modelContext.save()
        }
    }

    // MARK: - ペアリング関連

    public func saveAntennaPairing(_ pairing: AntennaPairing) async throws {
        let persistentPairing = pairing.toPersistent()
        self.modelContext.insert(persistentPairing)
        try self.modelContext.save()
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
            self.modelContext.delete(pairing)
        }
        try self.modelContext.save()
    }

    public func updateAntennaPairing(_ pairing: AntennaPairing) async throws {
        let predicate = #Predicate<PersistentAntennaPairing> { $0.id == pairing.id }
        let descriptor = FetchDescriptor<PersistentAntennaPairing>(predicate: predicate)

        let existingPairings = try modelContext.fetch(descriptor)
        if let existingPairing = existingPairings.first {
            existingPairing.deviceName = pairing.device.name
            existingPairing.isConnected = pairing.device.isConnected
            try self.modelContext.save()
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

        self.modelContext.insert(persistentData)
        try self.modelContext.save()
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
            self.modelContext.delete(item)
        }
        try self.modelContext.save()
    }

    // MARK: - システム活動履歴関連

    public func saveSystemActivity(_ activity: SystemActivity) async throws {
        let persistentActivity = activity.toPersistent()
        self.modelContext.insert(persistentActivity)
        try self.modelContext.save()
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
            self.modelContext.delete(activity)
        }
        try self.modelContext.save()
    }

    // MARK: - 受信ファイル関連

    public func saveReceivedFile(_ file: ReceivedFile) async throws {
        let persistentFile = file.toPersistent()
        self.modelContext.insert(persistentFile)
        try self.modelContext.save()
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
            self.modelContext.delete(file)
        }
        try self.modelContext.save()
    }

    public func deleteAllReceivedFiles() async throws {
        let descriptor = FetchDescriptor<PersistentReceivedFile>()

        let files = try modelContext.fetch(descriptor)
        for file in files {
            self.modelContext.delete(file)
        }
        try self.modelContext.save()
    }

    // MARK: - フロアマップ関連

    public func saveFloorMap(_ floorMap: FloorMapInfo) async throws {
        guard !floorMap.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("フロアマップIDが空です")
        }

        guard !floorMap.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("フロアマップ名が空です")
        }

        guard floorMap.width > 0 && floorMap.depth > 0 else {
            throw RepositoryError.invalidData("フロアマップのサイズが無効です (width: \(floorMap.width), depth: \(floorMap.depth))")
        }

        do {
            // 重複チェック
            let existingFloorMap = try await loadFloorMap(by: floorMap.id)
            if existingFloorMap != nil {
                throw RepositoryError.duplicateEntry("IDが重複するフロアマップが既に存在します: \(floorMap.id)")
            }

            let persistentFloorMap = floorMap.toPersistent()
            self.modelContext.insert(persistentFloorMap)

            try self.modelContext.save()
            #if DEBUG
                print("✅ フロアマップ保存完了 - ID: \(floorMap.id), Name: \(floorMap.name)")
            #endif
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.saveFailed("フロアマップの保存に失敗しました: \(error.localizedDescription)")
        }
    }

    public func loadAllFloorMaps() async throws -> [FloorMapInfo] {
        let descriptor = FetchDescriptor<PersistentFloorMap>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let persistentFloorMaps = try modelContext.fetch(descriptor)
        let floorMaps = persistentFloorMaps.map { $0.toEntity() }

        #if DEBUG
            print("📊 SwiftDataRepository: フロアマップ読み込み完了 - \(floorMaps.count)件")
            for floorMap in floorMaps {
                print("  - ID: \(floorMap.id), Name: \(floorMap.name)")
            }
        #endif

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
            self.modelContext.delete(floorMap)
        }
        try self.modelContext.save()
    }

    public func setActiveFloorMap(id: String) async throws {
        // すべてのフロアマップを非アクティブに
        let allDescriptor = FetchDescriptor<PersistentFloorMap>()
        let allFloorMaps = try modelContext.fetch(allDescriptor)

        for floorMap in allFloorMaps {
            floorMap.isActive = (floorMap.id == id)
        }

        try self.modelContext.save()
    }

    // MARK: - キャリブレーション関連

    public func saveCalibrationData(_ data: CalibrationData) async throws {
        guard !data.antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidData("アンテナIDが空です")
        }

        guard !data.calibrationPoints.isEmpty else {
            throw RepositoryError.invalidData("キャリブレーションポイントが空です")
        }

        do {
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

                try self.modelContext.save()
                #if DEBUG
                    print("🔄 キャリブレーションデータを更新しました: \(data.antennaId)")
                #endif
            } else {
                // 新規作成
                let persistentData = data.toPersistent()
                self.modelContext.insert(persistentData)
                try self.modelContext.save()
                #if DEBUG
                    print("✅ キャリブレーションデータ保存完了: \(data.antennaId)")
                #endif
            }
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.saveFailed("キャリブレーションデータの保存に失敗しました: \(error.localizedDescription)")
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
            self.modelContext.delete(data)
        }
        try self.modelContext.save()
    }

    public func deleteAllCalibrationData() async throws {
        let descriptor = FetchDescriptor<PersistentCalibrationData>()
        let allData = try modelContext.fetch(descriptor)

        for data in allData {
            self.modelContext.delete(data)
        }
        try self.modelContext.save()
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
            self.modelContext.insert(persistentData)
        }

        try self.modelContext.save()

        #if DEBUG
            print("🗄️ SwiftDataRepository: マップキャリブレーションデータ保存完了 - アンテナ: \(data.antennaId), フロアマップ: \(data.floorMapId)")
        #endif
    }

    public func loadMapCalibrationData() async throws -> [MapCalibrationData] {
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let persistentData = try modelContext.fetch(descriptor)
        let mapCalibrationData = persistentData.map { $0.toEntity() }

        #if DEBUG
            print("🗄️ SwiftDataRepository: マップキャリブレーションデータ読み込み完了 - \(mapCalibrationData.count)件")
        #endif
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
            self.modelContext.delete(data)
        }
        try self.modelContext.save()
    }

    public func deleteAllMapCalibrationData() async throws {
        let descriptor = FetchDescriptor<PersistentMapCalibrationData>()
        let allData = try modelContext.fetch(descriptor)

        for data in allData {
            self.modelContext.delete(data)
        }
        try self.modelContext.save()
    }

    // MARK: - データ整合性機能

    /// 重複するアンテナ位置データをクリーンアップ
    public func cleanupDuplicateAntennaPositions() async throws -> Int {
        let descriptor = FetchDescriptor<PersistentAntennaPosition>()
        let allPositions = try modelContext.fetch(descriptor)

        // アンテナID + フロアマップIDでグループ化
        let groupedPositions = Dictionary(grouping: allPositions) { position in
            "\(position.antennaId)_\(position.floorMapId)"
        }

        var deletedCount = 0

        for (key, positions) in groupedPositions {
            if positions.count > 1 {
                #if DEBUG
                    print("⚠️ 重複するアンテナ位置データを発見: \(key) - \(positions.count)件")
                #endif

                // 最新データを保持し、他は削除
                let sortedPositions = positions.sorted { pos1, pos2 in
                    pos1.id > pos2.id
                }

                let duplicatesToDelete = Array(sortedPositions.dropFirst())

                for duplicate in duplicatesToDelete {
                    #if DEBUG
                        print(
                            "🗑️ 重複データを削除: ID=\(duplicate.id), AntennaID=\(duplicate.antennaId), Name=\(duplicate.antennaName)"
                        )
                    #endif
                    self.modelContext.delete(duplicate)
                    deletedCount += 1
                }
            }
        }

        if deletedCount > 0 {
            try self.modelContext.save()
            #if DEBUG
                print("✅ 重複データクリーンアップ完了: \(deletedCount)件削除")
            #endif
        } else {
            #if DEBUG
                print("✅ 重複データは見つかりませんでした")
            #endif
        }

        return deletedCount
    }

    /// 全てのデータタイプの重複をチェック・クリーンアップ
    public func cleanupAllDuplicateData() async throws -> [String: Int] {
        var results: [String: Int] = [:]

        // アンテナ位置データの重複クリーンアップ
        results["antennaPositions"] = try await self.cleanupDuplicateAntennaPositions()

        // 他のデータタイプも必要に応じて追加可能

        return results
    }

    /// データベースの整合性チェック
    public func validateDataIntegrity() async throws -> [String] {
        var issues: [String] = []

        // アンテナ位置データの整合性チェック
        let antennaPositions = try await loadAntennaPositions()
        let duplicateGroups = Dictionary(grouping: antennaPositions) { position in
            "\(position.antennaId)_\(position.floorMapId)"
        }.filter { $1.count > 1 }

        if !duplicateGroups.isEmpty {
            issues.append("重複するアンテナ位置データ: \(duplicateGroups.count)グループ")
        }

        // 空の必須フィールドチェック
        let invalidAntennaPositions = antennaPositions.filter { position in
            position.antennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || position.antennaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || position.floorMapId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !invalidAntennaPositions.isEmpty {
            issues.append("無効なアンテナ位置データ: \(invalidAntennaPositions.count)件")
        }

        return issues
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

    // キャリブレーション関連
    public func saveCalibrationData(_ data: CalibrationData) async throws {}
    public func loadCalibrationData() async throws -> [CalibrationData] { [] }
    public func loadCalibrationData(for antennaId: String) async throws -> CalibrationData? { nil }
    public func deleteCalibrationData(for antennaId: String) async throws {}
    public func deleteAllCalibrationData() async throws {}

    // マップベースキャリブレーション関連
    public func saveMapCalibrationData(_ data: MapCalibrationData) async throws {}
    public func loadMapCalibrationData() async throws -> [MapCalibrationData] { [] }
    public func loadMapCalibrationData(for antennaId: String, floorMapId: String) async throws -> MapCalibrationData? {
        nil
    }
    public func deleteMapCalibrationData(for antennaId: String, floorMapId: String) async throws {}
    public func deleteAllMapCalibrationData() async throws {}

    // データ整合性機能
    public func cleanupDuplicateAntennaPositions() async throws -> Int { 0 }
    public func cleanupAllDuplicateData() async throws -> [String: Int] { [:] }
    public func validateDataIntegrity() async throws -> [String] { [] }
}
