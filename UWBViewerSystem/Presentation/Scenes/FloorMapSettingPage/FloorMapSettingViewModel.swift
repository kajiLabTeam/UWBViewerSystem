import Foundation
import SwiftUI
import UIKit

/// フロアマップ設定画面のViewModel
@MainActor
class FloorMapSettingViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedFloorMapImage: UIImage?
    @Published var floorName: String = ""
    @Published var buildingName: String = ""
    @Published var floorWidth: Double = 10.0
    @Published var floorDepth: Double = 15.0
    @Published var selectedPreset: FloorMapPreset?
    @Published var floorPresets: [FloorMapPreset] = []

    @Published var isImagePickerPresented: Bool = false
    @Published var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // MARK: - Computed Properties

    var canProceedToNext: Bool {
        !floorName.isEmpty && !buildingName.isEmpty && floorWidth > 0 && floorDepth > 0
    }

    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // MARK: - Initialization

    init() {
        setupFloorPresets()
    }

    // MARK: - Public Methods

    func setupInitialData() {
        loadSavedSettings()
    }

    func selectImageFromLibrary() {
        imagePickerSourceType = .photoLibrary
        isImagePickerPresented = true
    }

    func captureImageFromCamera() {
        guard isCameraAvailable else {
            showError("カメラが利用できません")
            return
        }

        imagePickerSourceType = .camera
        isImagePickerPresented = true
    }

    func selectPreset(_ preset: FloorMapPreset) {
        selectedPreset = preset
        floorWidth = preset.width
        floorDepth = preset.depth

        if floorName.isEmpty {
            floorName = preset.name
        }
    }

    func saveFloorMapSettings() -> Bool {
        guard canProceedToNext else {
            showError("必要な情報がすべて入力されていません")
            return false
        }

        isLoading = true

        // フロアマップ情報を保存
        var floorMapInfo = FloorMapInfo(
            id: UUID().uuidString,
            name: floorName,
            buildingName: buildingName,
            width: floorWidth,
            depth: floorDepth,
            createdAt: Date()
        )
        floorMapInfo.image = selectedFloorMapImage

        do {
            try saveFloorMapInfo(floorMapInfo)
            isLoading = false
            return true
        } catch {
            showError("フロアマップ情報の保存に失敗しました: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }

    func cancelSetup() {
        // 設定をリセット
        selectedFloorMapImage = nil
        floorName = ""
        buildingName = ""
        floorWidth = 10.0
        floorDepth = 15.0
        selectedPreset = nil

        // ナビゲーションを戻る
        NavigationRouterModel.shared.pop()
    }

    func onImageSelected(_ image: UIImage) {
        selectedFloorMapImage = image
        isImagePickerPresented = false
    }

    // MARK: - Private Methods

    private func setupFloorPresets() {
        floorPresets = [
            FloorMapPreset(
                name: "小規模オフィス",
                description: "10-20人程度のオフィス",
                width: 8.0,
                depth: 12.0,
                iconName: "building.2"
            ),
            FloorMapPreset(
                name: "中規模オフィス",
                description: "20-50人程度のオフィス",
                width: 15.0,
                depth: 20.0,
                iconName: "building.2.fill"
            ),
            FloorMapPreset(
                name: "大規模オフィス",
                description: "50人以上のオフィス",
                width: 25.0,
                depth: 30.0,
                iconName: "building.columns"
            ),
            FloorMapPreset(
                name: "会議室",
                description: "中規模の会議室",
                width: 6.0,
                depth: 8.0,
                iconName: "person.3"
            ),
            FloorMapPreset(
                name: "展示ホール",
                description: "展示会・イベント会場",
                width: 30.0,
                depth: 40.0,
                iconName: "building.columns.fill"
            ),
            FloorMapPreset(
                name: "カスタム",
                description: "手動で寸法を設定",
                width: 10.0,
                depth: 15.0,
                iconName: "slider.horizontal.3"
            ),
        ]
    }

    private func loadSavedSettings() {
        // UserDefaultsまたはSwiftDataから保存された設定を読み込む
        // 実装例：以前の設定がある場合は復元
        if let savedFloorName = UserDefaults.standard.object(forKey: "lastFloorName") as? String,
            !savedFloorName.isEmpty
        {
            floorName = savedFloorName
        }

        if let savedBuildingName = UserDefaults.standard.object(forKey: "lastBuildingName") as? String,
            !savedBuildingName.isEmpty
        {
            buildingName = savedBuildingName
        }
    }

    private func saveFloorMapInfo(_ info: FloorMapInfo) throws {
        // UserDefaultsに基本情報を保存
        UserDefaults.standard.set(info.name, forKey: "lastFloorName")
        UserDefaults.standard.set(info.buildingName, forKey: "lastBuildingName")
        UserDefaults.standard.set(info.width, forKey: "lastFloorWidth")
        UserDefaults.standard.set(info.depth, forKey: "lastFloorDepth")

        // 画像をDocumentsディレクトリに保存
        if let image = info.image {
            try saveImageToDocuments(image, with: info.id)
        }

        // フロアマップ情報をエンコードして保存
        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        UserDefaults.standard.set(data, forKey: "currentFloorMapInfo")
    }

    private func saveImageToDocuments(_ image: UIImage, with id: String) throws {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw FloorMapSettingError.imageProcessingFailed
        }

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsDirectory.appendingPathComponent("\(id).jpg")

        try imageData.write(to: imageURL)
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

// MARK: - Supporting Types

struct FloorMapPreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let width: Double
    let depth: Double
    let iconName: String
}

struct FloorMapInfo: Codable {
    let id: String
    let name: String
    let buildingName: String
    let width: Double
    let depth: Double
    let createdAt: Date

    // UIImageは直接Codableではないため、保存時は別途処理
    var image: UIImage?

    enum CodingKeys: String, CodingKey {
        case id, name, buildingName, width, depth, createdAt
    }
}

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
