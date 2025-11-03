import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// フロアマップ設定画面のViewModel
@MainActor
class FloorMapSettingViewModel: ObservableObject {
    // MARK: - Published Properties

    private var modelContext: ModelContext?
    private var swiftDataRepository: SwiftDataRepository?
    private let preferenceRepository: PreferenceRepositoryProtocol

    #if canImport(UIKit)
        #if os(iOS)
            @Published var selectedFloorMapImage: UIImage?
        #elseif os(macOS)
            @Published var selectedFloorMapImage: NSImage?
        #endif
    #elseif canImport(AppKit)
        @Published var selectedFloorMapImage: NSImage?
    #endif
    @Published var floorName: String = "テストフロア"
    @Published var buildingName: String = "テストビル"
    @Published var floorWidth: Double = 10.0
    @Published var floorDepth: Double = 10.0

    @Published var isImagePickerPresented: Bool = false
    #if canImport(UIKit)
        #if os(iOS)
            @Published var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
        #endif
    #endif
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // MARK: - Computed Properties

    var canProceedToNext: Bool {
        let hasRequiredFields =
            !self.floorName.isEmpty && !self.buildingName.isEmpty && self.floorWidth > 0 && self.floorDepth > 0
        return hasRequiredFields
    }

    var isCameraAvailable: Bool {
        #if canImport(UIKit)
            #if os(iOS)
                return UIImagePickerController.isSourceTypeAvailable(.camera)
            #else
                return false
            #endif
        #else
            return false
        #endif
    }

    // MARK: - Initialization

    init(preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()) {
        self.preferenceRepository = preferenceRepository
        #if DEBUG
            print("🚀 FloorMapSettingViewModel: init called")
        #endif
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        if #available(macOS 14, iOS 17, *) {
            swiftDataRepository = SwiftDataRepository(modelContext: context)
        }
    }

    // MARK: - Public Methods

    func setupInitialData() {
        self.loadSavedSettings()
    }

    func selectImageFromLibrary() {
        #if canImport(UIKit)
            self.imagePickerSourceType = .photoLibrary
        #endif
        self.isImagePickerPresented = true
    }

    func saveFloorMapSettings() async -> Bool {
        guard self.canProceedToNext else {
            self.showError("必要な情報がすべて入力されていません")
            return false
        }

        self.isLoading = true

        // フロアマップ情報を保存
        let floorMapInfo = FloorMapInfo(
            id: UUID().uuidString,
            name: self.floorName,
            buildingName: self.buildingName,
            width: self.floorWidth,
            depth: self.floorDepth,
            createdAt: Date()
        )

        do {
            try self.saveFloorMapInfo(floorMapInfo)

            // SwiftDataにも保存（非同期処理を同期的に待機）
            if let repository = swiftDataRepository {
                do {
                    try await repository.saveFloorMap(floorMapInfo)
                    #if DEBUG
                        print("✅ フロアマップをSwiftDataに保存成功: \(floorMapInfo.name)")
                    #endif

                    // プロジェクト進行状況を初期化して保存
                    let projectProgress = ProjectProgress(
                        floorMapId: floorMapInfo.id,
                        currentStep: .floorMapSetting,
                        completedSteps: [.floorMapSetting]  // フロアマップ設定完了
                    )

                    try await repository.saveProjectProgress(projectProgress)
                    #if DEBUG
                        print("✅ プロジェクト進行状況を保存成功: \(projectProgress.currentStep.displayName)")
                    #endif

                    // 保存直後に確認
                    await self.verifyDataSaved(
                        repository: repository, floorMapInfo: floorMapInfo, projectProgress: projectProgress)
                } catch {
                    #if DEBUG
                        print("❌ SwiftDataへの保存エラー: \(error)")
                    #endif
                    self.showError("データベースへの保存に失敗しました: \(error.localizedDescription)")
                    self.isLoading = false
                    return false
                }
            }

            self.isLoading = false
            return true
        } catch {
            self.showError("フロアマップ情報の保存に失敗しました: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }

    func cancelSetup() {
        // 設定をリセット
        self.selectedFloorMapImage = nil
        self.floorName = ""
        self.buildingName = ""
        self.floorWidth = 10.0
        self.floorDepth = 15.0

        // ナビゲーションを戻る
        NavigationRouterModel.shared.pop()
    }

    #if os(iOS)
        func onImageSelected(_ image: UIImage) {
            self.selectedFloorMapImage = image
            self.isImagePickerPresented = false
        }
    #elseif os(macOS)
        func onImageSelected(_ image: NSImage) {
            self.selectedFloorMapImage = image
            self.isImagePickerPresented = false
        }
    #endif

    private func loadSavedSettings() {
        // PreferenceRepositoryから保存された設定を読み込む
        let settings = self.preferenceRepository.loadLastFloorSettings()

        if let savedFloorName = settings.name, !savedFloorName.isEmpty {
            self.floorName = savedFloorName
        }

        if let savedBuildingName = settings.buildingName, !savedBuildingName.isEmpty {
            self.buildingName = savedBuildingName
        }

        if let savedWidth = settings.width {
            self.floorWidth = savedWidth
        }

        if let savedDepth = settings.depth {
            self.floorDepth = savedDepth
        }
    }

    private func saveFloorMapInfo(_ info: FloorMapInfo) throws {
        // PreferenceRepositoryに基本情報を保存
        self.preferenceRepository.saveLastFloorSettings(
            name: info.name,
            buildingName: info.buildingName,
            width: info.width,
            depth: info.depth
        )

        // 画像をDocumentsディレクトリに保存
        if let image = selectedFloorMapImage {
            try self.saveImageToDocuments(image, with: info.id)
        }

        // フロアマップ情報を保存
        self.preferenceRepository.saveCurrentFloorMapInfo(info)
    }

    #if os(iOS)
        private func saveImageToDocuments(_ image: UIImage, with id: String) throws {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw FloorMapSettingError.imageProcessingFailed
            }

            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("\(id).jpg")

            try imageData.write(to: imageURL)
        }
    #elseif os(macOS)
        private func saveImageToDocuments(_ image: NSImage, with id: String) throws {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw FloorMapSettingError.imageProcessingFailed
            }
            let nsImage = NSImage(cgImage: cgImage, size: image.size)
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let imageData = bitmapRep.representation(using: .jpeg, properties: [:])
            else {
                throw FloorMapSettingError.imageProcessingFailed
            }

            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let imageURL = documentsDirectory.appendingPathComponent("\(id).jpg")

            try imageData.write(to: imageURL)
        }
    #endif

    private func showError(_ message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
    }

    /// 保存直後にデータが正常に保存されているかを確認
    private func verifyDataSaved(
        repository: SwiftDataRepository, floorMapInfo: FloorMapInfo, projectProgress: ProjectProgress
    ) async {
        #if DEBUG
            print("🔍 === 保存検証開始 ===")

            do {
                // フロアマップの確認
                if let savedFloorMap = try await repository.loadFloorMap(by: floorMapInfo.id) {
                    print("✅ フロアマップ保存確認成功:")
                    print("   ID: \(savedFloorMap.id)")
                    print("   Name: \(savedFloorMap.name)")
                    print("   Building: \(savedFloorMap.buildingName)")
                    print("   Size: \(savedFloorMap.width) × \(savedFloorMap.depth)")
                } else {
                    print("❌ フロアマップが見つかりません: ID=\(floorMapInfo.id)")
                }

                // プロジェクト進行状況の確認
                if let savedProgress = try await repository.loadProjectProgress(by: projectProgress.id) {
                    print("✅ プロジェクト進行状況保存確認成功:")
                    print("   ID: \(savedProgress.id)")
                    print("   FloorMapID: \(savedProgress.floorMapId)")
                    print("   CurrentStep: \(savedProgress.currentStep.displayName)")
                    print(
                        "   CompletedSteps: \(savedProgress.completedSteps.map { $0.displayName }.joined(separator: ", "))"
                    )
                } else {
                    print("❌ プロジェクト進行状況が見つかりません: ID=\(projectProgress.id)")
                }

                // 全フロアマップの確認
                let allFloorMaps = try await repository.loadAllFloorMaps()
                print("📊 データベース内の全フロアマップ: \(allFloorMaps.count)件")
                for (index, floorMap) in allFloorMaps.enumerated() {
                    print("   [\(index + 1)] \(floorMap.name) (ID: \(floorMap.id))")
                }

            } catch {
                print("❌ 保存検証中にエラーが発生: \(error)")
            }

            print("🔍 === 保存検証終了 ===")
        #endif
    }
}

// FloorMapInfoはCommonTypes.swiftで定義済み

enum FloorMapSettingError: Error, LocalizedError {
    case imageProcessingFailed
    case savingFailed

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return "画像の処理に失敗しました"
        case .savingFailed:
            return "設定の保存に失敗しました"
        }
    }
}
