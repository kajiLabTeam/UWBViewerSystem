import Foundation
import SwiftData
import SwiftUI

struct FloorMap: Identifiable {
    let id: String
    let name: String
    let antennaCount: Int
    let width: Double
    let height: Double
    var isActive: Bool

    var formattedSize: String {
        String(format: "%.1f × %.1f m", self.width, self.height)
    }

    init(
        from floorMapInfo: FloorMapInfo, antennaCount: Int = 0, isActive: Bool = false
    ) {
        self.id = floorMapInfo.id
        self.name = floorMapInfo.name
        self.antennaCount = antennaCount
        self.width = floorMapInfo.width
        self.height = floorMapInfo.depth
        self.isActive = isActive
    }

    init(
        id: String, name: String, antennaCount: Int, width: Double, height: Double, isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.antennaCount = antennaCount
        self.width = width
        self.height = height
        self.isActive = isActive
    }

    func toFloorMapInfo() -> FloorMapInfo {
        FloorMapInfo(
            id: self.id,
            name: self.name,
            buildingName: "",  // buildingNameが含まれていない場合は空文字列
            width: self.width,
            depth: self.height,
            createdAt: Date()  // 作成日時が含まれていない場合は現在日時
        )
    }
}

@MainActor
class FloorMapViewModel: ObservableObject {
    @Published var floorMaps: [FloorMap] = []
    @Published var selectedFloorMap: FloorMap?
    @Published var errorMessage: String?

    private var modelContext: ModelContext?
    private var swiftDataRepository: SwiftDataRepository?
    private let preferenceRepository: PreferenceRepositoryProtocol
    private var deletingFloorMapIds: Set<String> = []

    init(preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()) {
        self.preferenceRepository = preferenceRepository
        print("🚀 FloorMapViewModel: init called")
    }

    func setModelContext(_ context: ModelContext) {
        // 同じModelContextが設定されている場合は何もしない
        if self.modelContext === context {
            print("🔄 FloorMapViewModel: 同じModelContextのため処理をスキップ")
            return
        }

        self.modelContext = context
        if #available(macOS 14, iOS 17, *) {
            swiftDataRepository = SwiftDataRepository(modelContext: context)
        }
        print("🔄 FloorMapViewModel: 新しいModelContextが設定されました、データを再読み込み")
        self.loadFloorMaps()
    }

    func refreshData() {
        print("🔄 FloorMapViewModel: refreshData called (外部から呼び出し)")
        self.loadFloorMaps()
    }

    func loadFloorMaps() {
        print("🗂️ FloorMapViewModel: loadFloorMaps called")

        guard let repository = swiftDataRepository else {
            print("❌ FloorMapViewModel: SwiftDataRepository not available, using fallback data")
            self.loadFallbackData()
            return
        }

        Task {
            do {
                let floorMapInfos = try await repository.loadAllFloorMaps()
                print("📱 SwiftDataからフロアマップを読み込み: \(floorMapInfos.count)件")

                // SwiftDataからのデータを使用してFloorMapを構築
                var floorMaps: [FloorMap] = []

                for floorMapInfo in floorMapInfos {
                    // アンテナ数をカウント（TODO: 実際のアンテナ数を取得）
                    let antennaCount = self.getAntennaCount(for: floorMapInfo.id)

                    let floorMap = FloorMap(
                        from: floorMapInfo,
                        antennaCount: antennaCount,
                        isActive: false  // 後で設定
                    )
                    floorMaps.append(floorMap)
                }

                await MainActor.run {
                    self.floorMaps = floorMaps
                    print("✅ FloorMapViewModel: フロアマップ一覧をUIに反映: \(floorMaps.count)件")
                    for (index, map) in floorMaps.enumerated() {
                        print("   [\(index + 1)] ID: \(map.id), Name: \(map.name)")
                    }

                    // デフォルトで最初のフロアマップを選択（グローバルな選択状態は保存しない）
                    if !self.floorMaps.isEmpty {
                        self.floorMaps[0].isActive = true
                        self.selectedFloorMap = self.floorMaps[0]
                        print("🔄 デフォルトで最初のフロアマップを選択: \(self.selectedFloorMap?.name ?? "Unknown")")
                    }

                    self.updatePreferences()
                }
            } catch {
                print("❌ SwiftDataからのフロアマップ読み込みエラー: \(error)")
                await MainActor.run {
                    print("🔄 フォールバックデータを読み込み中...")
                    self.loadFallbackData()
                }
            }
        }
    }

    private func loadFallbackData() {
        print("🔄 FloorMapViewModel: Loading fallback data")

        // PreferenceRepositoryの状態を確認
        print("🔍 PreferenceRepository確認:")
        if let floorMapInfo = preferenceRepository.loadCurrentFloorMapInfo() {
            print("   currentFloorMapInfo exists")
            print("   FloorMapInfo loaded successfully:")
            print("     ID: \(floorMapInfo.id)")
            print("     Name: \(floorMapInfo.name)")
            print("     Building: \(floorMapInfo.buildingName)")

            let floorMap = FloorMap(from: floorMapInfo, antennaCount: 0, isActive: true)
            self.floorMaps = [floorMap]
            self.selectedFloorMap = floorMap
            self.updatePreferences()
            print("✅ フォールバックデータから1件のフロアマップを復元")
        } else {
            print("   currentFloorMapInfo not found")
            // 完全にデータがない場合は空の状態に
            self.floorMaps = []
            self.selectedFloorMap = nil
            self.preferenceRepository.setHasFloorMapConfigured(false)
            print("💭 フォールバックデータなし、空の状態に設定")
        }
    }

    private func getAntennaCount(for floorMapId: String) -> Int {
        // TODO: SwiftDataからアンテナ位置データを取得して数をカウント
        0
    }

    private func updatePreferences() {
        self.preferenceRepository.setHasFloorMapConfigured(!self.floorMaps.isEmpty)
    }

    func selectFloorMap(_ map: FloorMap) {
        for i in 0..<self.floorMaps.count {
            self.floorMaps[i].isActive = (self.floorMaps[i].id == map.id)
        }
        self.selectedFloorMap = map
    }

    func toggleActiveFloorMap(_ map: FloorMap) {
        for i in 0..<self.floorMaps.count {
            if self.floorMaps[i].id == map.id {
                self.floorMaps[i].isActive.toggle()
                if self.floorMaps[i].isActive {
                    self.selectedFloorMap = self.floorMaps[i]
                    for j in 0..<self.floorMaps.count {
                        if j != i && self.floorMaps[j].isActive {
                            self.floorMaps[j].isActive = false
                        }
                    }
                } else if self.selectedFloorMap?.id == map.id {
                    self.selectedFloorMap = self.floorMaps.first { $0.isActive }
                }
                break
            }
        }
    }

    func deleteFloorMap(_ map: FloorMap) {
        guard !self.deletingFloorMapIds.contains(map.id) else {
            #if DEBUG
                print("⚠️ すでに削除処理中: \(map.id)")
            #endif
            return
        }

        self.deletingFloorMapIds.insert(map.id)

        Task {
            defer {
                Task { @MainActor in
                    deletingFloorMapIds.remove(map.id)
                }
            }
            do {
                try await self.deleteFloorMapFromRepository(map.id)
                await MainActor.run {
                    self.updateUIAfterDeletion(map)
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
                        print("❌ フロアマップの削除エラー: \(error)")
                    #endif
                    self.errorMessage = "フロアマップの削除に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteFloorMapFromRepository(_ mapId: String) async throws {
        guard let repository = swiftDataRepository else { return }

        try await repository.deleteFloorMap(by: mapId)
        #if DEBUG
            print("✅ SwiftDataからフロアマップを削除: \(mapId)")
        #endif

        await self.deleteCascadingData(for: mapId, repository: repository)
    }

    private func deleteCascadingData(for mapId: String, repository: SwiftDataRepository) async {
        // 関連するアンテナ位置データの削除
        do {
            try await repository.deleteAllAntennaPositions(for: mapId)
            #if DEBUG
                print("✅ 関連するアンテナ位置データを一括削除")
            #endif
        } catch {
            #if DEBUG
                print("⚠️ アンテナ位置データの削除中にエラー（続行）: \(error)")
            #endif
        }
    }

    private func updateUIAfterDeletion(_ map: FloorMap) {
        self.floorMaps.removeAll { $0.id == map.id }

        // PreferenceRepositoryからの削除
        if let currentFloorMapInfo = preferenceRepository.loadCurrentFloorMapInfo(),
           currentFloorMapInfo.id == map.id
        {
            self.preferenceRepository.removeCurrentFloorMapInfo()
            #if DEBUG
                print("🗑️ PreferenceRepositoryの現在のフロアマップ情報をクリア")
            #endif
        }

        self.updateActiveStateAfterDeletion(deletedMap: map)
    }

    private func updateActiveStateAfterDeletion(deletedMap: FloorMap) {
        if self.floorMaps.isEmpty {
            self.preferenceRepository.setHasFloorMapConfigured(false)
            self.selectedFloorMap = nil
            #if DEBUG
                print("📝 全てのフロアマップが削除されたため、設定状態をクリア")
            #endif
        } else if deletedMap.isActive {
            self.floorMaps[0].isActive = true
            self.selectedFloorMap = self.floorMaps[0]
            #if DEBUG
                print("🔄 新しいアクティブフロアマップ: \(self.floorMaps[0].name)")
            #endif
        }
    }

    func addFloorMap(name: String, width: Double, height: Double, antennaCount: Int) {
        let newMap = FloorMap(
            id: UUID().uuidString,
            name: name,
            antennaCount: antennaCount,
            width: width,
            height: height,
            isActive: self.floorMaps.isEmpty
        )

        self.floorMaps.append(newMap)

        if self.floorMaps.count == 1 {
            self.selectedFloorMap = newMap
        }

        self.preferenceRepository.setHasFloorMapConfigured(true)
    }
}
