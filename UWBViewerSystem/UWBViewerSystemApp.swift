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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistentSensingSession.self,
            PersistentAntennaPosition.self,
            PersistentAntennaPairing.self,
            PersistentRealtimeData.self,
            PersistentSystemActivity.self,
            PersistentReceivedFile.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("SwiftDataのモデルコンテナの作成に失敗しました: \(error)")
        }
    }()

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
