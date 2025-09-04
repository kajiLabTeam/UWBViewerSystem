import Foundation
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

    #if canImport(UIKit)
        #if os(iOS)
            @Published var selectedFloorMapImage: UIImage?
        #elseif os(macOS)
            @Published var selectedFloorMapImage: NSImage?
        #endif
    #elseif canImport(AppKit)
        @Published var selectedFloorMapImage: NSImage?
    #endif
    @Published var floorName: String = ""
    @Published var buildingName: String = ""
    @Published var floorWidth: Double = 10.0
    @Published var floorDepth: Double = 15.0
    @Published var selectedPreset: FloorMapPreset?
    @Published var floorPresets: [FloorMapPreset] = []

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
        !floorName.isEmpty && !buildingName.isEmpty && floorWidth > 0 && floorDepth > 0
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

    init() {
        setupFloorPresets()
    }

    // MARK: - Public Methods

    func setupInitialData() {
        loadSavedSettings()
    }

    func selectImageFromLibrary() {
        #if canImport(UIKit)
            imagePickerSourceType = .photoLibrary
        #endif
        isImagePickerPresented = true
    }

    func captureImageFromCamera() {
        guard isCameraAvailable else {
            showError("カメラが利用できません")
            return
        }

        #if canImport(UIKit)
            imagePickerSourceType = .camera
        #endif
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

    #if os(iOS)
        func onImageSelected(_ image: UIImage) {
            selectedFloorMapImage = image
            isImagePickerPresented = false
        }
    #elseif os(macOS)
        func onImageSelected(_ image: NSImage) {
            selectedFloorMapImage = image
            isImagePickerPresented = false
        }
    #endif

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
