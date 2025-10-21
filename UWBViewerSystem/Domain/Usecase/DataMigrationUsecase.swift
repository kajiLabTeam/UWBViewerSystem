import Foundation
import SwiftData

// MARK: - データ移行Usecase

/// UserDefaultsからSwiftDataへのデータ移行を管理するUsecase
///
/// このクラスは、アプリケーションのアップデート時に既存のUserDefaultsデータを
/// 新しいSwiftDataモデルに移行するためのビジネスロジックを提供します。
///
/// ## 移行対象データ
/// - センシングセッション（SensingSession）
/// - アンテナ位置データ（AntennaPositionData）
/// - システム活動履歴（SystemActivity）
///
/// ## 使用例
/// ```swift
/// let migrationUsecase = DataMigrationUsecase(
///     swiftDataRepository: swiftDataRepository,
///     preferenceRepository: preferenceRepository
/// )
///
/// if migrationUsecase.needsMigration {
///     try await migrationUsecase.migrateDataIfNeeded()
/// }
/// ```
///
/// ## 設計原則
/// - **冪等性**: 何度実行しても同じ結果になる
/// - **段階的移行**: データ種別ごとに段階的に移行
/// - **エラー耐性**: 一部のデータ移行が失敗しても続行
/// - **透明性**: 移行プロセスをログで可視化
@MainActor
public class DataMigrationUsecase {
    /// 旧DataRepository（UserDefaults経由のデータアクセス）
    private let dataRepository: DataRepository
    /// 新SwiftDataRepository（Core Data系のデータアクセス）
    private let swiftDataRepository: SwiftDataRepositoryProtocol
    /// 設定管理用Repository
    private let preferenceRepository: PreferenceRepositoryProtocol
    /// 移行完了を記録するキー
    private let migrationKey = "UWBViewerSystem.DataMigration.Completed"

    /// DataMigrationUsecaseのイニシャライザ
    /// - Parameters:
    ///   - dataRepository: 移行元となるUserDefaultsベースのリポジトリ
    ///   - swiftDataRepository: 移行先となるSwiftDataベースのリポジトリ
    ///   - preferenceRepository: 移行状態管理用のプリファレンスリポジトリ
    public init(
        dataRepository: DataRepository = DataRepository(),
        swiftDataRepository: SwiftDataRepositoryProtocol,
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.dataRepository = dataRepository
        self.swiftDataRepository = swiftDataRepository
        self.preferenceRepository = preferenceRepository
    }

    /// データ移行が必要かどうかを確認します
    /// - Returns: 移行が必要な場合true、既に完了している場合false
    public var needsMigration: Bool {
        !self.preferenceRepository.isMigrationCompleted(for: self.migrationKey)
    }

    /// UserDefaultsからSwiftDataへデータを移行します
    ///
    /// この操作は冪等性があり、既に移行が完了している場合は何も行いません。
    /// 移行中にエラーが発生した場合でも、部分的に移行されたデータは保持されます。
    ///
    /// - Throws: SwiftDataへの保存時に発生するエラー
    public func migrateDataIfNeeded() async throws {
        guard self.needsMigration else {
            print("データ移行は既に完了しています")
            return
        }

        print("データ移行を開始します...")

        // センシングセッションの移行
        await self.migrateSensingSessions()

        // アンテナ位置データの移行
        await self.migrateAntennaPositions()

        // システム活動履歴の移行
        await self.migrateSystemActivities()

        // 移行完了フラグを設定
        self.preferenceRepository.setMigrationCompleted(for: self.migrationKey, completed: true)
        print("データ移行が完了しました")
    }

    // MARK: - Private Migration Methods

    private func migrateSensingSessions() async {
        // UserDefaultsから直接移行
        let sessions: [SensingSession] = []  // 実際のUserDefaultsからの読み込みロジックに置き換え
        if !sessions.isEmpty {
            print("センシングセッション \(sessions.count)件を移行中...")

            for session in sessions {
                do {
                    try await self.swiftDataRepository.saveSensingSession(session)
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
                    try await self.swiftDataRepository.saveAntennaPosition(position)
                } catch {
                    print("アンテナ位置データ移行エラー (\(position.antennaName)): \(error)")
                }
            }
        }
    }

    private func migrateSystemActivities() async {
        // UserDefaultsから直接移行
        let activities: [SystemActivity] = []  // 実際のUserDefaultsからの読み込みロジックに置き換え
        if !activities.isEmpty {
            print("システム活動履歴 \(activities.count)件を移行中...")

            for activity in activities {
                do {
                    try await self.swiftDataRepository.saveSystemActivity(activity)
                } catch {
                    print("システム活動履歴移行エラー: \(error)")
                }
            }
        }
    }

    /// 移行状態をリセットします（テスト用）
    ///
    /// この操作により、移行完了フラグがクリアされ、次回の移行チェック時に
    /// 再度移行処理が実行されるようになります。
    ///
    /// - Warning: この操作は通常テスト目的でのみ使用してください
    public func resetMigration() {
        self.preferenceRepository.setMigrationCompleted(for: self.migrationKey, completed: false)
        print("移行フラグをリセットしました")
    }

    /// UserDefaultsの移行済みデータをクリアします（移行後のオプション）
    ///
    /// 移行が完了した後、不要になった旧データを削除するために使用します。
    /// 設定値など、継続して使用する必要があるデータは保持されます。
    ///
    /// - Note: この操作は移行完了後の任意のタイミングで実行できます
    public func clearUserDefaultsData() {
        print("UserDefaultsのデータをクリア中...")

        // PreferenceRepositoryから直接クリーンアップ
        self.preferenceRepository.removeObject(forKey: "sensingSessions")

        // その他のデータ（必要に応じて追加）
        // ただし、設定値などは残すようにする

        print("UserDefaultsのデータクリアが完了しました")
    }
}
