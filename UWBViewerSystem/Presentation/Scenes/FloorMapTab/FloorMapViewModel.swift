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
    var projectProgress: ProjectProgress?

    var formattedSize: String {
        String(format: "%.1f × %.1f m", width, height)
    }

    var progressPercentage: Double {
        projectProgress?.completionPercentage ?? 0.0
    }

    var currentStepDisplayName: String {
        projectProgress?.currentStep.displayName ?? "未開始"
    }

    init(from floorMapInfo: FloorMapInfo, antennaCount: Int = 0, isActive: Bool = false, projectProgress: ProjectProgress? = nil) {
        id = floorMapInfo.id
        name = floorMapInfo.name
        self.antennaCount = antennaCount
        width = floorMapInfo.width
        height = floorMapInfo.depth
        self.isActive = isActive
        self.projectProgress = projectProgress
    }

    init(id: String, name: String, antennaCount: Int, width: Double, height: Double, isActive: Bool, projectProgress: ProjectProgress? = nil) {
        self.id = id
        self.name = name
        self.antennaCount = antennaCount
        self.width = width
        self.height = height
        self.isActive = isActive
        self.projectProgress = projectProgress
    }

    func toFloorMapInfo() -> FloorMapInfo {
        FloorMapInfo(
            id: id,
            name: name,
            buildingName: "", // buildingNameが含まれていない場合は空文字列
            width: width,
            depth: height,
            createdAt: Date() // 作成日時が含まれていない場合は現在日時
        )
    }
}

@MainActor
class FloorMapViewModel: ObservableObject {
    @Published var floorMaps: [FloorMap] = []
    @Published var selectedFloorMap: FloorMap?

    private var modelContext: ModelContext?
    private var swiftDataRepository: SwiftDataRepository?
    private let preferenceRepository: PreferenceRepositoryProtocol

    init(preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()) {
        self.preferenceRepository = preferenceRepository
        print("🚀 FloorMapViewModel: init called")
    }

    func setModelContext(_ context: ModelContext) {
        // 同じModelContextが設定されている場合は何もしない
        if modelContext === context {
            print("🔄 FloorMapViewModel: 同じModelContextのため処理をスキップ")
            return
        }

        modelContext = context
        if #available(macOS 14, iOS 17, *) {
            swiftDataRepository = SwiftDataRepository(modelContext: context)
        }
        print("🔄 FloorMapViewModel: 新しいModelContextが設定されました、データを再読み込み")
        loadFloorMaps()
    }

    func refreshData() {
        print("🔄 FloorMapViewModel: refreshData called (外部から呼び出し)")
        loadFloorMaps()
    }

    func loadFloorMaps() {
        print("🗂️ FloorMapViewModel: loadFloorMaps called")

        guard let repository = swiftDataRepository else {
            print("❌ FloorMapViewModel: SwiftDataRepository not available, using fallback data")
            loadFallbackData()
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
                    let antennaCount = getAntennaCount(for: floorMapInfo.id)

                    // プロジェクト進行状況を取得
                    var projectProgress: ProjectProgress?
                    do {
                        projectProgress = try await repository.loadProjectProgress(for: floorMapInfo.id)
                    } catch {
                        print("⚠️ プロジェクト進行状況の読み込みエラー: \(error)")
                    }

                    let floorMap = FloorMap(
                        from: floorMapInfo,
                        antennaCount: antennaCount,
                        isActive: false, // 後で設定
                        projectProgress: projectProgress
                    )
                    floorMaps.append(floorMap)
                }

                await MainActor.run {
                    self.floorMaps = floorMaps
                    print("✅ FloorMapViewModel: フロアマップ一覧をUIに反映: \(floorMaps.count)件")

                    // アクティブなフロアマップを設定
                    if let activeId = getCurrentActiveFloorMapId(),
                       let index = self.floorMaps.firstIndex(where: { $0.id == activeId }) {
                        self.floorMaps[index].isActive = true
                        selectedFloorMap = self.floorMaps[index]
                        print("🔄 アクティブなフロアマップを復元: \(selectedFloorMap?.name ?? "Unknown")")
                    } else if !self.floorMaps.isEmpty {
                        self.floorMaps[0].isActive = true
                        selectedFloorMap = self.floorMaps[0]
                        print("🔄 デフォルトで最初のフロアマップを選択: \(selectedFloorMap?.name ?? "Unknown")")
                    }

                    updatePreferences()
                }
            } catch {
                print("❌ SwiftDataからのフロアマップ読み込みエラー: \(error)")
                await MainActor.run {
                    print("🔄 フォールバックデータを読み込み中...")
                    loadFallbackData()
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
            floorMaps = [floorMap]
            selectedFloorMap = floorMap
            updatePreferences()
            print("✅ フォールバックデータから1件のフロアマップを復元")
        } else {
            print("   currentFloorMapInfo not found")
            // 完全にデータがない場合は空の状態に
            floorMaps = []
            selectedFloorMap = nil
            preferenceRepository.setHasFloorMapConfigured(false)
            print("💭 フォールバックデータなし、空の状態に設定")
        }
    }

    private func getAntennaCount(for floorMapId: String) -> Int {
        // TODO: SwiftDataからアンテナ位置データを取得して数をカウント
        0
    }

    private func getCurrentActiveFloorMapId() -> String? {
        preferenceRepository.loadCurrentFloorMapInfo()?.id
    }

    private func updatePreferences() {
        preferenceRepository.setHasFloorMapConfigured(!floorMaps.isEmpty)
    }

    func selectFloorMap(_ map: FloorMap) {
        for i in 0..<floorMaps.count {
            floorMaps[i].isActive = (floorMaps[i].id == map.id)
        }
        selectedFloorMap = map

        // UserDefaultsのcurrentFloorMapInfoを更新
        updateCurrentFloorMapInfo(map.toFloorMapInfo())
    }

    private func updateCurrentFloorMapInfo(_ floorMapInfo: FloorMapInfo) {
        preferenceRepository.saveCurrentFloorMapInfo(floorMapInfo)
        print("📍 FloorMapViewModel: currentFloorMapInfo updated to: \(floorMapInfo.name)")

        // フロアマップ変更を通知
        NotificationCenter.default.post(name: .init("FloorMapChanged"), object: floorMapInfo)
    }

    func toggleActiveFloorMap(_ map: FloorMap) {
        for i in 0..<floorMaps.count {
            if floorMaps[i].id == map.id {
                floorMaps[i].isActive.toggle()
                if floorMaps[i].isActive {
                    selectedFloorMap = floorMaps[i]
                    // UserDefaultsのcurrentFloorMapInfoを更新
                    updateCurrentFloorMapInfo(floorMaps[i].toFloorMapInfo())
                    for j in 0..<floorMaps.count {
                        if j != i && floorMaps[j].isActive {
                            floorMaps[j].isActive = false
                        }
                    }
                } else if selectedFloorMap?.id == map.id {
                    selectedFloorMap = floorMaps.first { $0.isActive }
                    // 新しく選択されたフロアマップのcurrentFloorMapInfoを更新
                    if let newSelectedMap = selectedFloorMap {
                        updateCurrentFloorMapInfo(newSelectedMap.toFloorMapInfo())
                    }
                }
                break
            }
        }
    }

    func deleteFloorMap(_ map: FloorMap) {
        floorMaps.removeAll { $0.id == map.id }

        if floorMaps.isEmpty {
            preferenceRepository.setHasFloorMapConfigured(false)
            selectedFloorMap = nil
        } else if map.isActive && !floorMaps.isEmpty {
            floorMaps[0].isActive = true
            selectedFloorMap = floorMaps[0]
        }
    }

    func addFloorMap(name: String, width: Double, height: Double, antennaCount: Int) {
        let newMap = FloorMap(
            id: UUID().uuidString,
            name: name,
            antennaCount: antennaCount,
            width: width,
            height: height,
            isActive: floorMaps.isEmpty
        )

        floorMaps.append(newMap)

        if floorMaps.count == 1 {
            selectedFloorMap = newMap
        }

        preferenceRepository.setHasFloorMapConfigured(true)
    }
}
