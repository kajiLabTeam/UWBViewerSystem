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
}

@MainActor
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

    public func deleteAntennaPosition(by id: String) async throws {
        let predicate = #Predicate<PersistentAntennaPosition> { $0.id == id }
        let descriptor = FetchDescriptor<PersistentAntennaPosition>(predicate: predicate)

        let positions = try modelContext.fetch(descriptor)
        for position in positions {
            modelContext.delete(position)
        }
        try modelContext.save()
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

        // セッションとの関連付け
        let sessionPredicate = #Predicate<PersistentSensingSession> { $0.id == sessionId }
        let sessionDescriptor = FetchDescriptor<PersistentSensingSession>(predicate: sessionPredicate)
        let sessions = try modelContext.fetch(sessionDescriptor)

        if let session = sessions.first {
            persistentData.session = session
        }

        modelContext.insert(persistentData)
        try modelContext.save()
    }

    public func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] {
        let predicate = #Predicate<PersistentRealtimeData> { $0.session?.id == sessionId }
        let descriptor = FetchDescriptor<PersistentRealtimeData>(
            predicate: predicate,
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
}

// MARK: - Dummy Repository for Initialization

/// ViewModelの初期化時に使用するダミーリポジトリ
/// 実際のModelContextが利用可能になったら実装されたリポジトリに置き換える
public class DummySwiftDataRepository: SwiftDataRepositoryProtocol {
    public init() {}

    public func saveSensingSession(_ session: SensingSession) async throws {}
    public func loadSensingSession(by id: String) async throws -> SensingSession? { return nil }
    public func loadAllSensingSessions() async throws -> [SensingSession] { return [] }
    public func deleteSensingSession(by id: String) async throws {}
    public func updateSensingSession(_ session: SensingSession) async throws {}
    public func saveAntennaPosition(_ position: AntennaPositionData) async throws {}
    public func loadAntennaPositions() async throws -> [AntennaPositionData] { return [] }
    public func deleteAntennaPosition(by id: String) async throws {}
    public func updateAntennaPosition(_ position: AntennaPositionData) async throws {}
    public func saveAntennaPairing(_ pairing: AntennaPairing) async throws {}
    public func loadAntennaPairings() async throws -> [AntennaPairing] { return [] }
    public func deleteAntennaPairing(by id: String) async throws {}
    public func updateAntennaPairing(_ pairing: AntennaPairing) async throws {}
    public func saveRealtimeData(_ data: RealtimeData, sessionId: String) async throws {}
    public func loadRealtimeData(for sessionId: String) async throws -> [RealtimeData] { return [] }
    public func deleteRealtimeData(by id: UUID) async throws {}
    public func saveSystemActivity(_ activity: SystemActivity) async throws {}
    public func loadRecentSystemActivities(limit: Int) async throws -> [SystemActivity] { return [] }
    public func deleteOldSystemActivities(olderThan date: Date) async throws {}
    public func saveReceivedFile(_ file: ReceivedFile) async throws {}
    public func loadReceivedFiles() async throws -> [ReceivedFile] { return [] }
    public func deleteReceivedFile(by id: UUID) async throws {}
    public func deleteAllReceivedFiles() async throws {}
}
