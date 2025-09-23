import Foundation
import Testing
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
        // テスト用のMockRepositoryを作成
        let mockDataRepository = MockDataRepository()
        let mockPreferenceRepository = MockPreferenceRepository()
        return SimpleCalibrationViewModel(dataRepository: mockDataRepository, preferenceRepository: mockPreferenceRepository)
    }

    @MainActor
    private func createTestViewModelWithFloorMapInfo() -> (SimpleCalibrationViewModel, MockPreferenceRepository) {
        // テスト用のMockRepositoryを作成
        let mockDataRepository = MockDataRepository()
        let mockPreferenceRepository = MockPreferenceRepository()

        // テスト用のフロアマップ情報を設定
        let testFloorMapInfo = createTestFloorMapInfo()
        mockPreferenceRepository.saveCurrentFloorMapInfo(testFloorMapInfo)

        let viewModel = SimpleCalibrationViewModel(dataRepository: mockDataRepository, preferenceRepository: mockPreferenceRepository)
        return (viewModel, mockPreferenceRepository)
    }

    @MainActor
    private func createIsolatedTestViewModel() -> SimpleCalibrationViewModel {
        // テスト用のMockRepositoryを作成
        let mockDataRepository = MockDataRepository()
        let mockPreferenceRepository = MockPreferenceRepository()

        let viewModel = SimpleCalibrationViewModel(dataRepository: mockDataRepository, preferenceRepository: mockPreferenceRepository)

        return viewModel
    }

    @MainActor
    private func createTestViewModelWithMocks(
        mockPreferenceRepository: MockPreferenceRepository
    ) -> SimpleCalibrationViewModel {
        // テスト用のMockRepositoryを作成
        let mockDataRepository = MockDataRepository()

        let viewModel = SimpleCalibrationViewModel(dataRepository: mockDataRepository, preferenceRepository: mockPreferenceRepository)

        return viewModel
    }

    private func createTestFloorMapInfo() -> FloorMapInfo {
        FloorMapInfo(
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
        }
    }

    private func cleanupTestEnvironment() {
        // テスト後のクリーンアップ
        UserDefaults.standard.removeObject(forKey: "currentFloorMapInfo")
    }

    // MARK: - フロアマップデータ読み込みテスト

    @Test("フロアマップデータ読み込み - PreferenceRepositoryからの読み込み")
    func loadCurrentFloorMapData() async throws {
        let (viewModel, _) = await createTestViewModelWithFloorMapInfo()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // ポーリングベースでフロアマップ情報の読み込みを待機
        let maxWaitTime: TimeInterval = 2.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var floorMapLoaded = false
        repeat {
            let currentInfo = await viewModel.currentFloorMapInfo
            if currentInfo != nil && currentInfo?.id == "test-floor-map" {
                floorMapLoaded = true
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // 検証
        #expect(floorMapLoaded, "フロアマップ情報が正常に読み込まれていません")
        #expect(await viewModel.currentFloorMapInfo != nil)
        #expect(await viewModel.currentFloorMapInfo?.id == "test-floor-map")
        #expect(await viewModel.currentFloorMapInfo?.name == "テストフロアマップ")
    }

    @Test("フロアマップデータ読み込み - フロアマップIDがない場合")
    func loadCurrentFloorMapDataWithoutSelectedId() async throws {
        let viewModel = await createIsolatedTestViewModel()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // ポーリングベースでフロアマップ情報の更新を待機
        let maxWaitTime: TimeInterval = 1.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var currentFloorMapInfo: FloorMapInfo?
        repeat {
            currentFloorMapInfo = await viewModel.currentFloorMapInfo
            if currentFloorMapInfo == nil {
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // 検証: フロアマップ情報がnilであること
        #expect(currentFloorMapInfo == nil)
    }

    // MARK: - フロアマップ画像読み込みテスト

    @Test("フロアマップ画像読み込み - 存在しないファイルの場合")
    func loadFloorMapImageWithNonExistentFile() async throws {
        let viewModel = await createTestViewModel()

        // 初期データ読み込み（画像ファイルが存在しない場合）
        await viewModel.loadInitialData()

        // 検証: 画像がnilであること
        #if canImport(UIKit)
            #expect(await viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
            #expect(await viewModel.floorMapImage == nil)
        #endif
    }

    // MARK: - 基準点表示テスト

    @Test("基準点表示 - 複数の基準点が正しく設定される")
    func referencePointsDisplay() async throws {
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
        #expect(await viewModel.referencePoints.count == 3)
        #expect(await viewModel.referencePoints[0].x == 1.0)
        #expect(await viewModel.referencePoints[1].x == 2.0)
        #expect(await viewModel.referencePoints[2].y == 2.0)
    }

    // MARK: - ViewModel初期化テスト

    @Test("ViewModel初期化 - 初期状態の確認")
    func viewModelInitialization() async throws {
        defer { cleanupTestEnvironment() }

        let viewModel = await createIsolatedTestViewModel()

        // ポーリングベースで初期状態の確認
        let maxWaitTime: TimeInterval = 1.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var stableState = false
        repeat {
            let currentFloorMapInfo = await viewModel.currentFloorMapInfo
            let referencePoints = await viewModel.referencePoints

            if currentFloorMapInfo == nil && referencePoints.isEmpty {
                stableState = true
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // 初期状態の検証
        #expect(await viewModel.currentFloorMapInfo == nil)
        #if canImport(UIKit)
            #expect(await viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
            #expect(await viewModel.floorMapImage == nil)
        #endif
        #expect(await viewModel.referencePoints.isEmpty)
        #expect(stableState, "初期状態が安定していません")
    }

    // MARK: - エラーハンドリングテスト

    @Test("エラーハンドリング - 不正なJSON形式でのフロアマップ情報")
    func errorHandlingWithInvalidJSON() async throws {
        defer { cleanupTestEnvironment() }

        // 不正なJSONデータを設定
        UserDefaults.standard.set("invalid-json-data", forKey: "currentFloorMapInfo")

        let viewModel = await createTestViewModel()

        // 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // ポーリングベースでエラーハンドリングの確認
        let maxWaitTime: TimeInterval = 1.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var errorHandled = false
        repeat {
            let currentFloorMapInfo = await viewModel.currentFloorMapInfo
            if currentFloorMapInfo == nil {
                errorHandled = true
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // 検証: エラーが発生してもnilが設定されること
        #expect(errorHandled, "不正なJSONのエラーハンドリングが機能していません")
        #expect(await viewModel.currentFloorMapInfo == nil)
    }

    @Test("エラーハンドリング - 無効なフロアマップデータ")
    func errorHandlingWithInvalidFloorMapData() async throws {
        defer { cleanupTestEnvironment() }

        // 無効なデータを持つフロアマップ情報を設定
        let invalidFloorMapInfo = FloorMapInfo(
            id: "", // 空のID
            name: "テストフロアマップ",
            buildingName: "テストビル",
            width: -1.0, // 無効なサイズ
            depth: 800.0,
            createdAt: Date()
        )

        if let encoded = try? JSONEncoder().encode(invalidFloorMapInfo) {
            UserDefaults.standard.set(encoded, forKey: "currentFloorMapInfo")
        }

        let viewModel = await createTestViewModel()
        await viewModel.loadInitialData()

        // ポーリングベースで無効データのバリデーション確認
        let maxWaitTime: TimeInterval = 1.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var validationComplete = false
        repeat {
            let floorMapInfo = await viewModel.currentFloorMapInfo
            // バリデーションが完了した状態を確認
            if floorMapInfo == nil {
                validationComplete = true
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // 検証: 無効なデータの場合、SimpleCalibrationViewModelでバリデーションによりnilが設定される可能性がある
        // エラーハンドリングがされているかを確認
        let floorMapInfo = await viewModel.currentFloorMapInfo
        // バリデーションでfalseになる場合、nilが設定される
        #expect(floorMapInfo == nil)
        #expect(validationComplete, "無効データのバリデーション処理が完了していません")
    }

    @Test("エラーハンドリング - キャリブレーション開始条件チェック")
    func calibrationStartValidation() async throws {
        let viewModel = await createTestViewModel()

        // currentStepを2に設定（キャリブレーション実行ステップ）
        await MainActor.run {
            viewModel.currentStep = 2
        }

        // 条件1: アンテナが選択されていない場合
        #expect(await viewModel.canStartCalibration == false)

        // 条件2: アンテナは選択されているが基準点が不足している場合
        await viewModel.selectAntenna("test-antenna")
        await viewModel.addReferencePoint(Point3D(x: 1.0, y: 1.0, z: 0.0))
        #expect(await viewModel.canStartCalibration == false)

        // 条件3: 必要な基準点数が満たされた場合
        await viewModel.addReferencePoint(Point3D(x: 2.0, y: 1.0, z: 0.0))
        await viewModel.addReferencePoint(Point3D(x: 1.5, y: 2.0, z: 0.0))
        #expect(await viewModel.canStartCalibration == true)
    }

    @Test("エラーハンドリング - 重複する基準座標の検証")
    func duplicateReferencePointsValidation() async throws {
        let viewModel = await createTestViewModel()

        // 重複する座標を設定
        let duplicatePoints = [
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0), // 重複
            Point3D(x: 2.0, y: 2.0, z: 0.0)
        ]

        await viewModel.setReferencePoints(duplicatePoints)
        await viewModel.selectAntenna("test-antenna")

        // キャリブレーション開始を試行
        await viewModel.startCalibration()

        // エラーメッセージが設定されることを確認
        #expect(await !(viewModel.errorMessage.isEmpty))
        #expect(await viewModel.showErrorAlert == true)
    }

    @Test("エラーハンドリング - 無効な座標値の検証")
    func invalidCoordinateValidation() async throws {
        let viewModel = await createTestViewModel()

        // 無効な座標値（NaN、Infinity）を含む基準点を設定
        let invalidPoints = [
            Point3D(x: Double.nan, y: 1.0, z: 0.0), // NaN
            Point3D(x: 2.0, y: Double.infinity, z: 0.0), // Infinity
            Point3D(x: 3.0, y: 3.0, z: 0.0)
        ]

        await viewModel.setReferencePoints(invalidPoints)
        await viewModel.selectAntenna("test-antenna")

        // キャリブレーション開始を試行
        await viewModel.startCalibration()

        // エラーメッセージが設定されることを確認
        #expect(await !(viewModel.errorMessage.isEmpty))
        #expect(await viewModel.showErrorAlert == true)
    }

    // MARK: - 統合テスト

    @Test("統合テスト - フロアマップ読み込みから表示まで")
    func integrationFloorMapLoadingAndDisplay() async throws {
        defer { cleanupTestEnvironment() }

        // MockPreferenceRepositoryにテストデータを設定
        let testFloorMapInfo = createTestFloorMapInfo()
        let mockPreferenceRepository = MockPreferenceRepository()
        mockPreferenceRepository.saveCurrentFloorMapInfo(testFloorMapInfo)

        let viewModel = await createTestViewModelWithMocks(
            mockPreferenceRepository: mockPreferenceRepository
        )

        // Step 1: 初期データ読み込みでフロアマップデータが読み込まれる
        await viewModel.loadInitialData()

        // ポーリングベースでフロアマップ情報の読み込みを待機
        let maxWaitTime: TimeInterval = 2.0
        let pollInterval: TimeInterval = 0.05
        let startTime = Date()

        var floorMapLoaded = false
        repeat {
            let currentInfo = await viewModel.currentFloorMapInfo
            if currentInfo != nil && currentInfo?.id == "test-floor-map" {
                floorMapLoaded = true
                break
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        } while Date().timeIntervalSince(startTime) < maxWaitTime

        // Step 2: フロアマップ情報が正しく読み込まれることを確認
        #expect(floorMapLoaded, "フロアマップ情報の読み込みが完了していません")
        #expect(await viewModel.currentFloorMapInfo != nil)

        // Step 3: 基準点を設定
        let testPoints = [
            Point3D(x: 100.0, y: 100.0, z: 0.0),
            Point3D(x: 200.0, y: 200.0, z: 0.0)
        ]

        await viewModel.setReferencePoints(testPoints)

        // Step 4: 全体の状態を検証
        #expect(await viewModel.currentFloorMapInfo?.id == "test-floor-map")
        #expect(await viewModel.referencePoints.count == 2)

        // Step 5: 画像の状態を確認（ファイルが存在しないため、nilが期待される）
        #if canImport(UIKit)
            #expect(await viewModel.floorMapImage == nil)
        #elseif canImport(AppKit)
            #expect(await viewModel.floorMapImage == nil)
        #endif
    }

    // MARK: - クロスプラットフォーム対応テスト

    @Test("クロスプラットフォーム対応 - 画像プロパティの型確認")
    func crossPlatformImageProperty() async throws {
        let viewModel = await createTestViewModel()

        // プラットフォーム固有の画像プロパティの型を確認
        #if canImport(UIKit)
            let _: UIImage? = await viewModel.floorMapImage
        #elseif canImport(AppKit)
            let _: NSImage? = await viewModel.floorMapImage
        #endif

        // テストが通ることで、適切な型が定義されていることを確認
        #expect(true) // 型チェックのため必要
    }

    // MARK: - リアルタイム更新テスト

    @Test("リアルタイム更新 - Preference Repository変更時の自動更新")
    func realTimeUpdateWhenPreferenceChanges() async throws {
        defer { cleanupTestEnvironment() }

        // MockPreferenceRepositoryを使用したViewModelを作成
        let mockPreferenceRepository = MockPreferenceRepository()
        let viewModel = await createTestViewModelWithMocks(
            mockPreferenceRepository: mockPreferenceRepository
        )

        // 初期データ読み込みを実行（初期状態では何もない）
        await viewModel.loadInitialData()

        // 初期状態の確認
        #expect(await viewModel.currentFloorMapInfo == nil)

        // フロアマップ情報をMockPreferenceRepositoryに設定
        let testFloorMapInfo = createTestFloorMapInfo()
        mockPreferenceRepository.saveCurrentFloorMapInfo(testFloorMapInfo)

        // フロアマップ情報の再読み込みをトリガー
        await viewModel.loadInitialData()

        // データが正常に更新されることを確認
        let updatedFloorMapInfo = await viewModel.currentFloorMapInfo
        #expect(updatedFloorMapInfo != nil, "フロアマップ情報が更新されていません")
        if let info = updatedFloorMapInfo {
            #expect(info.id == "test-floor-map", "フロアマップIDが期待値と異なります")
            #expect(info.name == "テストフロアマップ", "フロアマップ名が期待値と異なります")
        }
    }
}
