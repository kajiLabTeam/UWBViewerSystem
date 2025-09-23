//
//  UWBViewerSystemApp.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import SwiftData
import SwiftUI

// MARK: - SwiftData Error Handling

enum SwiftDataContainerError: Error {
    case schemaError(Error)
    case modelConfigurationError(Error)
    case fileSystemError(Error)
    case unknownError(Error)

    var localizedDescription: String {
        switch self {
        case .schemaError(let error):
            return "スキーマエラー: \(error.localizedDescription)"
        case .modelConfigurationError(let error):
            return "モデル設定エラー: \(error.localizedDescription)"
        case .fileSystemError(let error):
            return "ファイルシステムエラー: \(error.localizedDescription)"
        case .unknownError(let error):
            return "不明なエラー: \(error.localizedDescription)"
        }
    }
}

extension SwiftDataContainerError {
    /// SwiftDataのエラーを分類して適切なエラー型に変換
    static func categorize(_ error: Error) -> SwiftDataContainerError {
        let errorDescription = error.localizedDescription.lowercased()

        // SwiftDataのスキーマ関連エラーを検出
        if errorDescription.contains("schema") ||
            errorDescription.contains("model") ||
            errorDescription.contains("migration") ||
            errorDescription.contains("version") {
            return .schemaError(error)
        }

        // ファイルシステム関連エラーを検出
        if errorDescription.contains("file") ||
            errorDescription.contains("directory") ||
            errorDescription.contains("permission") ||
            errorDescription.contains("disk") ||
            errorDescription.contains("space") {
            return .fileSystemError(error)
        }

        // モデル設定関連エラーを検出
        if errorDescription.contains("configuration") ||
            errorDescription.contains("container") ||
            errorDescription.contains("context") {
            return .modelConfigurationError(error)
        }

        return .unknownError(error)
    }
}

@main
struct UWBViewerSystemApp: App {
    /// アプリ全体で使用するルーター
    /// - Note: NavigationRouterModelはObservableObjectを継承しているため、@StateObjectで使用することができる
    @StateObject var router = NavigationRouterModel.shared

    @available(macOS 14, iOS 17, *)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistentFloorMap.self,
            PersistentProjectProgress.self,
            PersistentAntennaPosition.self,
            PersistentSensingSession.self,
            PersistentSystemActivity.self,
            PersistentReceivedFile.self,
            PersistentCalibrationData.self,
            PersistentMapCalibrationData.self,
        ])

        // インメモリ設定で最初に試行（テスト用）
        let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            // まず既存のデータベースを強制削除
            print("🗑️ 既存のデータベースを削除してスキーマをリセット")
            deleteExistingDatabase()

            // データベースファイルの場所を表示
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                print("📁 Documents Directory: \(documentsDirectory.path)")
            }
            if let applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                print("📁 Application Support Directory: \(applicationSupportDirectory.path)")
            }

            // ApplicationSupportディレクトリの作成を確実に行う
            let fileManager = FileManager.default
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let bundleID = Bundle.main.bundleIdentifier ?? "net.harutiro.UWBViewerSystem"
                let appDirectory = appSupportURL.appendingPathComponent(bundleID)

                if !fileManager.fileExists(atPath: appDirectory.path) {
                    try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
                    print("📁 ApplicationSupport ディレクトリを作成: \(appDirectory.path)")
                }

                // カスタムModelConfigurationでファイル場所を指定
                let customURL = appDirectory.appendingPathComponent("SwiftData.sqlite")
                let modelConfiguration = ModelConfiguration(url: customURL)
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ SwiftDataファイルベース永続化で初期化成功 (カスタムパス)")

                return container
            } else {
                // フォールバック: デフォルトファイルベース設定で直接作成を試行
                let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ SwiftDataファイルベース永続化で初期化成功 (デフォルトパス)")

                return container
            }
        } catch {
            let categorizedError = SwiftDataContainerError.categorize(error)
            print("⚠️ SwiftDataのモデルコンテナ作成エラー: \(categorizedError.localizedDescription)")

            // エラーの種類に応じて適切な処理を実行
            switch categorizedError {
            case .schemaError(let originalError):
                print("🔄 スキーマエラーのため既存データベースを削除して再作成します")
                deleteExistingDatabase()

                do {
                    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                    return try ModelContainer(for: schema, configurations: [modelConfiguration])
                } catch {
                    print("⚠️ データベース再作成も失敗しました: \(error)")
                }

            case .fileSystemError(let originalError):
                print("📁 ファイルシステムエラーを検出。ApplicationSupportディレクトリの再作成を試行します")
                // ディレクトリ再作成を試行
                deleteExistingDatabase()

                do {
                    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                    return try ModelContainer(for: schema, configurations: [modelConfiguration])
                } catch {
                    print("⚠️ ディレクトリ再作成後も失敗しました: \(error)")
                }

            case .modelConfigurationError(let originalError):
                print("⚙️ モデル設定エラーを検出。設定を変更して再試行します")
                // より単純な設定で再試行
                do {
                    let simpleConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                    return try ModelContainer(for: schema, configurations: [simpleConfiguration])
                } catch {
                    print("⚠️ 簡素な設定でも失敗しました: \(error)")
                }

            case .unknownError(let originalError):
                print("❓ 不明なエラー: 通常のリカバリ処理を実行します")
            }

            // 最終的にインメモリで動作（データは永続化されないが動作は可能）
            do {
                print("🔄 インメモリモードで動作します（データは永続化されません）")
                return try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            } catch {
                fatalError("SwiftDataの初期化に完全に失敗しました: \(error)")
            }
        }
    }()

    @available(macOS 14, iOS 17, *)
    private static func deleteExistingDatabase() {
        let fileManager = FileManager.default

        // 複数のディレクトリをチェックして削除
        let directories: [(FileManager.SearchPathDirectory, String)] = [
            (.applicationSupportDirectory, "UWBViewerSystem"),
            (.documentDirectory, "UWBViewerSystem"),
            (.cachesDirectory, "UWBViewerSystem"),
        ]

        for (directory, appName) in directories {
            guard let baseDirectory = fileManager.urls(for: directory, in: .userDomainMask).first else {
                continue
            }

            let appDirectory = baseDirectory.appendingPathComponent(appName)

            do {
                if fileManager.fileExists(atPath: appDirectory.path) {
                    try fileManager.removeItem(at: appDirectory)
                    print("✅ \(directory)の既存データを削除しました: \(appDirectory.path)")
                }
            } catch {
                print("❌ \(directory)データ削除エラー: \(error)")
            }
        }

        // 追加: SwiftDataの一般的なファイル名パターンも削除
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let contents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
                for url in contents {
                    if url.pathExtension == "sqlite" || url.pathExtension == "sqlite-wal" || url.pathExtension == "sqlite-shm" {
                        try fileManager.removeItem(at: url)
                        print("✅ SwiftDataファイルを削除: \(url.lastPathComponent)")
                    }
                }
            } catch {
                print("❌ SwiftDataファイル削除エラー: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationRouter()
                .environmentObject(router)
                .task {
                    await performDataMigrationIfNeeded()
                    await debugDatabaseContents()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Data Migration

    /// アプリ起動時にデータ移行を実行
    @MainActor
    private func performDataMigrationIfNeeded() async {
        let swiftDataRepository = SwiftDataRepository(modelContext: sharedModelContainer.mainContext)
        let migrationUsecase = DataMigrationUsecase(swiftDataRepository: swiftDataRepository)

        do {
            try await migrationUsecase.migrateDataIfNeeded()
        } catch {
            print("データ移行に失敗しました: \(error)")
        }
    }

    /// アプリ起動時にデータベースの内容をデバッグ出力
    @MainActor
    private func debugDatabaseContents() async {
        print("🔍 === DATABASE DEBUG START ===")

        // データベースファイルの場所を確認
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("📁 Documents Directory: \(documentsDirectory.path)")

            // SwiftDataファイルを探す
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
                print("📄 Documents Directory contents:")
                for url in contents {
                    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    let size = resourceValues?.fileSize ?? 0
                    let date = resourceValues?.creationDate ?? Date()
                    print("   - \(url.lastPathComponent) (Size: \(size) bytes, Created: \(date))")
                }
            } catch {
                print("❌ Documents Directory読み取りエラー: \(error)")
            }
        }

        let swiftDataRepository = SwiftDataRepository(modelContext: sharedModelContainer.mainContext)

        do {
            // フロアマップの確認
            let floorMaps = try await swiftDataRepository.loadAllFloorMaps()
            print("📊 データベース内のフロアマップ: \(floorMaps.count)件")
            for (index, floorMap) in floorMaps.enumerated() {
                print("  [\(index + 1)] ID: \(floorMap.id)")
                print("      Name: \(floorMap.name)")
                print("      Building: \(floorMap.buildingName)")
                print("      Size: \(floorMap.width) × \(floorMap.depth)")
                print("      Created: \(floorMap.createdAt)")
            }

            // プロジェクト進行状況の確認
            let projectProgresses = try await swiftDataRepository.loadAllProjectProgress()
            print("📊 データベース内のプロジェクト進行状況: \(projectProgresses.count)件")
            for (index, progress) in projectProgresses.enumerated() {
                print("  [\(index + 1)] ID: \(progress.id)")
                print("      FloorMapID: \(progress.floorMapId)")
                print("      CurrentStep: \(progress.currentStep.displayName)")
                print("      CompletedSteps: \(progress.completedSteps.map { $0.displayName }.joined(separator: ", "))")
            }

            // アンテナ位置の確認
            let antennaPositions = try await swiftDataRepository.loadAntennaPositions()
            print("📊 データベース内のアンテナ位置: \(antennaPositions.count)件")
            for (index, position) in antennaPositions.enumerated() {
                print("  [\(index + 1)] ID: \(position.id)")
                print("      FloorMapID: \(position.floorMapId)")
                print("      Name: \(position.antennaName)")
                print("      Position: (\(position.position.x), \(position.position.y), \(position.position.z))")
            }

        } catch {
            print("❌ データベースデバッグ中にエラーが発生: \(error)")
        }

        print("🔍 === DATABASE DEBUG END ===")
    }
}
