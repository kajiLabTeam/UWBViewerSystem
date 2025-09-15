import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import UWBViewerSystem

@Suite("シンプルキャリブレーションViewModel フロアマップ画像表示テスト")
struct SimpleCalibrationViewModelTests {

    // MARK: - Test Setup

    @MainActor
    private func createTestViewModel() -> SimpleCalibrationViewModel {
        return SimpleCalibrationViewModel()
    }

    @MainActor
    private func createIsolatedTestViewModel() -> SimpleCalibrationViewModel {
        // まずUserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: "currentFloorMapInfo")

        let viewModel = SimpleCalibrationViewModel()

        // ViewModelが初期化された後に、再度確実にクリア
        Task {
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05秒待機
            UserDefaults.standard.removeObject(forKey: "currentFloorMapInfo")
        }

        return viewModel
    }

    private func createTestFloorMapInfo() -> FloorMapInfo {
        return FloorMapInfo(
            id: "test-floor-map",
            name: "テストフロアマップ",
            buildingName: "テストビル",
            width: 1000.0,
            depth: 800.0,
            createdAt: Date()
        )
    }

    private func setupTestEnvironment() {
        // テスト用のDocumentsディレクトリ構造を作成
        let fileManager = FileManager.default
        if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let floorMapsDir = documentsPath.appendingPathComponent("FloorMaps")
            try? fileManager.createDirectory(at: floorMapsDir, withIntermediateDirectories: true)

            // テスト用のフロアマップ情報をUserDefaultsに保存
            let testFloorMapInfo = createTestFloorMapInfo()

            // フロアマップ情報をエンコードして保存（SimpleCalibrationViewModelが使用するキー）
            if let encoded = try? JSONEncoder().encode(testFloorMapInfo) {
                UserDefaults.standard.set(encoded, forKey: "currentFloorMapInfo")
            }
        }
    }

    private func cleanupTestEnvironment() {
        // テスト後のクリーンアップ
        UserDefaults.standard.removeObject(forKey: "currentFloorMapInfo")
    }

    // MARK: - フロアマップデータ読み込みテスト

    @Test("フロアマップデータ読み込み - UserDefaultsからの読み込み")
    func testLoadCurrentFloorMapData() async throws {
        setupTestEnvironment()
        defer { cleanupTestEnvironment() }

        let viewModel = await createTestViewModel()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // 検証
        await #expect(viewModel.currentFloorMapInfo != nil)
        await #expect(viewModel.currentFloorMapInfo?.id == "test-floor-map")
        await #expect(viewModel.currentFloorMapInfo?.name == "テストフロアマップ")
    }

    @Test("フロアマップデータ読み込み - 選択されたフロアマップIDがない場合")
    func testLoadCurrentFloorMapDataWithoutSelectedId() async throws {
        let viewModel = await createIsolatedTestViewModel()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // UserDefaultsの変更通知が処理されるまで少し待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 検証: フロアマップ情報がnilであること
        await #expect(viewModel.currentFloorMapInfo == nil)
    }

    // MARK: - フロアマップ画像読み込みテスト

    @Test("フロアマップ画像読み込み - 存在しないファイルの場合")
    func testLoadFloorMapImageWithNonExistentFile() async throws {
        let viewModel = await createTestViewModel()

        // 初期データ読み込み（画像ファイルが存在しない場合）
        await viewModel.loadInitialData()

        // 検証: 画像がnilであること
        #if canImport(UIKit)
        await #expect(viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
        await #expect(viewModel.floorMapImage == nil)
        #endif
    }

    // MARK: - 基準点表示テスト

    @Test("基準点表示 - 複数の基準点が正しく設定される")
    func testReferencePointsDisplay() async throws {
        setupTestEnvironment()
        defer { cleanupTestEnvironment() }

        let viewModel = await createTestViewModel()

        // テスト用の基準点を設定
        let testPoints = [
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 2.0, y: 1.0, z: 0.0),
            Point3D(x: 1.5, y: 2.0, z: 0.0)
        ]

        await viewModel.setReferencePoints(testPoints)

        // 検証
        await #expect(viewModel.referencePoints.count == 3)
        await #expect(viewModel.referencePoints[0].x == 1.0)
        await #expect(viewModel.referencePoints[1].x == 2.0)
        await #expect(viewModel.referencePoints[2].y == 2.0)
    }

    // MARK: - ViewModel初期化テスト

    @Test("ViewModel初期化 - 初期状態の確認")
    func testViewModelInitialization() async throws {
        let viewModel = await createIsolatedTestViewModel()

        // UserDefaultsの変更通知が処理されるまで少し待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 初期状態の検証
        await #expect(viewModel.currentFloorMapInfo == nil)
        #if canImport(UIKit)
        await #expect(viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
        await #expect(viewModel.floorMapImage == nil)
        #endif
        await #expect(viewModel.referencePoints.isEmpty)
    }

    // MARK: - エラーハンドリングテスト

    @Test("エラーハンドリング - 不正なJSON形式でのフロアマップ情報")
    func testErrorHandlingWithInvalidJSON() async throws {
        // 不正なJSONデータを設定
        UserDefaults.standard.set("invalid-json-data", forKey: "currentFloorMapInfo")
        defer { cleanupTestEnvironment() }

        let viewModel = await createTestViewModel()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // UserDefaultsの変更通知が処理されるまで少し待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 検証: エラーが発生してもnilが設定されること
        await #expect(viewModel.currentFloorMapInfo == nil)
    }

    // MARK: - 統合テスト

    @Test("統合テスト - フロアマップ読み込みから表示まで")
    func testIntegrationFloorMapLoadingAndDisplay() async throws {
        setupTestEnvironment()
        defer { cleanupTestEnvironment() }

        let viewModel = await createTestViewModel()

        // Step 1: 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // Step 2: フロアマップ情報が正しく読み込まれることを確認
        await #expect(viewModel.currentFloorMapInfo != nil)

        // Step 3: 基準点を設定
        let testPoints = [
            Point3D(x: 100.0, y: 100.0, z: 0.0),
            Point3D(x: 200.0, y: 200.0, z: 0.0)
        ]

        await viewModel.setReferencePoints(testPoints)

        // Step 4: 全体の状態を検証
        await #expect(viewModel.currentFloorMapInfo?.id == "test-floor-map")
        await #expect(viewModel.referencePoints.count == 2)

        // Step 5: 画像の状態を確認（ファイルが存在しないため、nilが期待される）
        #if canImport(UIKit)
        await #expect(viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
        await #expect(viewModel.floorMapImage == nil)
        #endif
    }

    // MARK: - クロスプラットフォーム対応テスト

    @Test("クロスプラットフォーム対応 - 画像プロパティの型確認")
    func testCrossPlatformImageProperty() async throws {
        let viewModel = await createTestViewModel()

        // プラットフォーム固有の画像プロパティの型を確認
        #if canImport(UIKit)
        let _: UIImage? = await viewModel.floorMapImage
        #elseif canImport(AppKit)
        let _: NSImage? = await viewModel.floorMapImage
        #endif

        // テストが通ることで、適切な型が定義されていることを確認
        #expect(true)
    }

    // MARK: - リアルタイム更新テスト

    @Test("リアルタイム更新 - UserDefaults変更時の自動更新")
    func testRealTimeUpdateWhenUserDefaultsChanges() async throws {
        let viewModel = await createIsolatedTestViewModel()

        // 初期状態ではフロアマップ情報がnilであることを確認
        await #expect(viewModel.currentFloorMapInfo == nil)

        // フロアマップ情報を設定
        let testFloorMapInfo = createTestFloorMapInfo()
        if let encoded = try? JSONEncoder().encode(testFloorMapInfo) {
            UserDefaults.standard.set(encoded, forKey: "currentFloorMapInfo")
        }

        // UserDefaultsの変更通知が処理されるまで少し待つ
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // リアルタイム更新が機能していることを確認
        await #expect(viewModel.currentFloorMapInfo != nil)
        await #expect(viewModel.currentFloorMapInfo?.id == "test-floor-map")

        // クリーンアップ
        cleanupTestEnvironment()
    }
}