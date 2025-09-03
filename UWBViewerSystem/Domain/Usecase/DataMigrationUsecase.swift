import Foundation
import SwiftData

// MARK: - データ移行Usecase

/// UserDefaultsからSwiftDataへのデータ移行を管理するUsecase
@MainActor
public class DataMigrationUsecase {
    private let dataRepository: DataRepository
    private let swiftDataRepository: SwiftDataRepositoryProtocol
    private let migrationKey = "UWBViewerSystem.DataMigration.Completed"
    
    public init(dataRepository: DataRepository = DataRepository(), swiftDataRepository: SwiftDataRepositoryProtocol) {
        self.dataRepository = dataRepository
        self.swiftDataRepository = swiftDataRepository
    }
    
    /// データ移行が必要かどうかを確認
    public var needsMigration: Bool {
        return !UserDefaults.standard.bool(forKey: migrationKey)
    }
    
    /// UserDefaultsからSwiftDataへデータを移行
    public func migrateDataIfNeeded() async throws {
        guard needsMigration else {
            print("データ移行は既に完了しています")
            return
        }
        
        print("データ移行を開始します...")
        
        do {
            // センシングセッションの移行
            await migrateSensingSessions()
            
            // アンテナ位置データの移行
            await migrateAntennaPositions()
            
            // システム活動履歴の移行
            await migrateSystemActivities()
            
            // 移行完了フラグを設定
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("データ移行が完了しました")
            
        } catch {
            print("データ移行エラー: \(error)")
            throw error
        }
    }
    
    // MARK: - Private Migration Methods
    
    private func migrateSensingSessions() async {
        if let sessions = dataRepository.loadSensingSessions() {
            print("センシングセッション \(sessions.count)件を移行中...")
            
            for session in sessions {
                do {
                    try await swiftDataRepository.saveSensingSession(session)
                } catch {
                    print("センシングセッション移行エラー (\(session.name)): \(error)")
                }
            }
        }
    }
    
    private func migrateAntennaPositions() async {
        if let positions = dataRepository.loadAntennaPositions() {
            print("アンテナ位置データ \(positions.count)件を移行中...")
            
            for position in positions {
                do {
                    try await swiftDataRepository.saveAntennaPosition(position)
                } catch {
                    print("アンテナ位置データ移行エラー (\(position.antennaName)): \(error)")
                }
            }
        }
    }
    
    private func migrateSystemActivities() async {
        if let activities = dataRepository.loadSystemActivities() {
            print("システム活動履歴 \(activities.count)件を移行中...")
            
            for activity in activities {
                do {
                    try await swiftDataRepository.saveSystemActivity(activity)
                } catch {
                    print("システム活動履歴移行エラー: \(error)")
                }
            }
        }
    }
    
    /// 移行をリセット（テスト用）
    public func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        print("移行フラグをリセットしました")
    }
    
    /// UserDefaultsのデータをクリア（移行後のオプション）
    public func clearUserDefaultsData() {
        print("UserDefaultsのデータをクリア中...")
        
        // センシングセッション関連
        dataRepository.clearSensingSessions()
        
        // その他のデータ（必要に応じて追加）
        // ただし、設定値などは残すようにする
        
        print("UserDefaultsのデータクリアが完了しました")
    }
}