//
//  UWBViewerSystemApp.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/07/08.
//

import SwiftData
import SwiftUI

@main
struct UWBViewerSystemApp: App {
    /// アプリ全体で使用するルーター
    /// - Note: NavigationRouterModelはObservableObjectを継承しているため、@StateObjectで使用することができる
    @StateObject var router = NavigationRouterModel.shared

    @available(macOS 14, iOS 17, *)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistentSensingSession.self,
            PersistentAntennaPosition.self,
            PersistentAntennaPairing.self,
            PersistentRealtimeData.self,
            PersistentSystemActivity.self,
            PersistentReceivedFile.self,
            PersistentFloorMap.self,
            PersistentProjectProgress.self,
        ])

        // インメモリ設定で最初に試行（テスト用）
        let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            // まずインメモリで動作確認
            let testContainer = try ModelContainer(for: schema, configurations: [inMemoryConfiguration])
            print("✅ SwiftDataスキーマ検証成功")
            
            // 実際のファイルベース設定
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            // 既存のデータベースを強制削除して再作成
            deleteExistingDatabase()
            
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("⚠️ SwiftDataのモデルコンテナ作成エラー: \(error)")
            
            // 強制的にインメモリで動作（データは永続化されないが動作は可能）
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
}
