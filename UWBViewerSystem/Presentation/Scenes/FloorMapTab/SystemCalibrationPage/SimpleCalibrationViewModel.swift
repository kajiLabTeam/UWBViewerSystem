import Combine
import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// シンプルな3ステップキャリブレーション画面のViewModel
@MainActor
class SimpleCalibrationViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 現在のステップ (0: アンテナ選択, 1: 基準座標設定, 2: キャリブレーション実行)
    @Published var currentStep: Int = 0

    /// 選択されたアンテナID
    @Published var selectedAntennaId: String = ""

    /// 利用可能なアンテナ一覧
    @Published var availableAntennas: [AntennaInfo] = []

    /// 基準座標（マップから設定された3つの座標）
    @Published var referencePoints: [Point3D] = []

    /// キャリブレーション実行中フラグ
    @Published var isCalibrating: Bool = false

    /// キャリブレーション進行状況 (0.0 - 1.0)
    @Published var calibrationProgress: Double = 0.0

    /// キャリブレーション結果
    @Published var calibrationResult: CalibrationResult?

    /// エラーメッセージ
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false

    /// 成功アラート表示フラグ
    @Published var showSuccessAlert: Bool = false

    /// 現在のフロアマップID
    @Published var currentFloorMapId: String = ""

    /// 現在のフロアマップ情報
    @Published var currentFloorMapInfo: FloorMapInfo?

    /// フロアマップ画像
    #if canImport(UIKit)
        @Published var floorMapImage: UIImage?
    #elseif canImport(AppKit)
        @Published var floorMapImage: NSImage?
    #endif

    /// 配置済みアンテナ位置データ
    @Published var antennaPositions: [AntennaPositionData] = []

    // MARK: - Private Properties

    private let dataRepository: DataRepositoryProtocol
    private let preferenceRepository: PreferenceRepositoryProtocol
    private let calibrationUsecase: CalibrationUsecase
    private var cancellables = Set<AnyCancellable>()
    private var calibrationTimer: Timer?
    private var swiftDataRepository: SwiftDataRepository?

    // MARK: - Computed Properties

    /// 現在のステップタイトル
    var currentStepTitle: String {
        switch currentStep {
        case 0: return "アンテナ選択"
        case 1: return "基準座標設定"
        case 2: return "キャリブレーション実行"
        default: return ""
        }
    }

    /// 現在のステップ説明
    var currentStepDescription: String {
        switch currentStep {
        case 0: return "キャリブレーションを行うアンテナを選択してください"
        case 1: return "フロアマップ上で3つの基準座標をタップしてください"
        case 2: return "キャリブレーションを開始してください"
        default: return ""
        }
    }

    /// 次へボタンが有効かどうか
    var canProceedToNext: Bool {
        switch currentStep {
        case 0: return !selectedAntennaId.isEmpty
        case 1: return referencePoints.count >= 3
        case 2: return false // キャリブレーション実行画面では次へボタンは無効
        default: return false
        }
    }

    /// 戻るボタンが有効かどうか
    var canGoBack: Bool {
        currentStep > 0 && !isCalibrating
    }

    /// キャリブレーション実行可能かどうか
    var canStartCalibration: Bool {
        currentStep == 2 && !selectedAntennaId.isEmpty && referencePoints.count >= 3 && !isCalibrating
    }

    /// 進行状況のパーセンテージ表示
    var progressPercentage: String {
        "\(Int(calibrationProgress * 100))%"
    }

    /// キャリブレーション結果の精度テキスト
    var calibrationAccuracyText: String {
        if let result = calibrationResult,
           let accuracy = result.transform?.accuracy {
            return String(format: "%.2f%%", accuracy * 100)
        }
        return "不明"
    }

    /// キャリブレーション結果のテキスト
    var calibrationResultText: String {
        guard let result = calibrationResult else { return "未実行" }
        return result.success ? "成功" : "失敗"
    }

    /// キャリブレーション結果の色
    var calibrationResultColor: Color {
        guard let result = calibrationResult else { return .secondary }
        return result.success ? .green : .red
    }

    // MARK: - Initialization

    init(
        dataRepository: DataRepositoryProtocol = DataRepository(),
        preferenceRepository: PreferenceRepositoryProtocol = PreferenceRepository()
    ) {
        self.dataRepository = dataRepository
        self.preferenceRepository = preferenceRepository
        calibrationUsecase = CalibrationUsecase(dataRepository: dataRepository)

        loadInitialData()
        setupDataObserver()
    }

    deinit {
        calibrationTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// SwiftDataのModelContextを設定
    func setModelContext(_ context: ModelContext) {
        swiftDataRepository = SwiftDataRepository(modelContext: context)

        // SwiftDataRepository設定後にアンテナ位置データを再読み込み
        Task { @MainActor in
            await loadAntennaPositionsFromSwiftData()
        }
    }

    /// 初期データの読み込み
    func loadInitialData() {
        loadAvailableAntennas()
        loadCurrentFloorMapData()
        loadAntennaPositions()
    }

    /// データの再読み込み（外部から呼び出し可能）
    func reloadData() {
        print("🔄 reloadData() 呼び出し")
        loadCurrentFloorMapData()
        loadAntennaPositions()
        print("🔍 reloadData完了時の画像状態: \(floorMapImage != nil ? "画像あり" : "画像なし")")
    }

    /// 次のステップに進む
    func proceedToNext() {
        guard canProceedToNext else { return }

        withAnimation {
            currentStep += 1
        }
    }

    /// 前のステップに戻る
    func goBack() {
        guard canGoBack else { return }

        withAnimation {
            currentStep -= 1
        }
    }

    /// アンテナを選択
    func selectAntenna(_ antennaId: String) {
        selectedAntennaId = antennaId
    }

    /// 基準座標を設定（マップからの座標）
    func setReferencePoints(_ points: [Point3D]) {
        referencePoints = points
    }

    /// 基準座標を追加
    func addReferencePoint(_ point: Point3D) {
        if referencePoints.count < 3 {
            referencePoints.append(point)
        }
    }

    /// 基準座標をクリア
    func clearReferencePoints() {
        referencePoints.removeAll()
    }

    /// キャリブレーションを開始
    /// キャリブレーションを開始
    func startCalibration() {
        // 事前条件チェック
        guard validateCalibrationPreConditions() else {
            return
        }

        isCalibrating = true
        calibrationProgress = 0.0
        calibrationResult = nil
        errorMessage = ""

        // 基準座標をキャリブレーション用の測定点として設定
        setupCalibrationPoints()

        // キャリブレーション実行
        performCalibration()
    }

    /// キャリブレーション開始前の条件をチェック
    private func validateCalibrationPreConditions() -> Bool {
        guard canStartCalibration else {
            showError("キャリブレーションを開始できません。必要な条件が満たされていません。")
            return false
        }

        guard !selectedAntennaId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("アンテナが選択されていません。")
            return false
        }

        guard referencePoints.count >= 3 else {
            showError("基準座標が不足しています。少なくとも3点の設定が必要です。")
            return false
        }

        // 基準座標の妥当性チェック
        for (index, point) in referencePoints.enumerated() {
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else {
                showError("基準座標\(index + 1)に無効な値が含まれています。")
                return false
            }
        }

        // 同一座標の重複チェック
        let uniquePoints = Set(referencePoints.map { "\($0.x),\($0.y),\($0.z)" })
        guard uniquePoints.count == referencePoints.count else {
            showError("基準座標に重複があります。異なる座標を設定してください。")
            return false
        }

        return true
    }

    /// キャリブレーション完了後にリセット
    func resetCalibration() {
        currentStep = 0
        selectedAntennaId = ""
        referencePoints.removeAll()
        isCalibrating = false
        calibrationProgress = 0.0
        calibrationResult = nil

        // 最初のアンテナを再選択
        if !availableAntennas.isEmpty {
            selectedAntennaId = availableAntennas.first?.id ?? ""
        }
    }

    // MARK: - Private Methods

    /// 利用可能なアンテナを読み込み
    private func loadAvailableAntennas() {
        availableAntennas = dataRepository.loadFieldAntennaConfiguration() ?? []

        // デフォルトで最初のアンテナを選択
        if !availableAntennas.isEmpty && selectedAntennaId.isEmpty {
            selectedAntennaId = availableAntennas.first?.id ?? ""
        }
    }

    /// 現在のフロアマップデータを読み込み
    private func loadCurrentFloorMapData() {
        print("📋 フロアマップデータ読み込み開始")

        guard let floorMapInfo = preferenceRepository.loadCurrentFloorMapInfo() else {
            print("❌ PreferenceRepository から currentFloorMapInfo が見つかりません")
            handleError("フロアマップ情報が設定されていません。先にフロアマップを設定してください。")
            // 現在の状態をクリア
            clearFloorMapData()
            return
        }

        print("✅ PreferenceRepository からデータを取得")

        // データの妥当性チェック
        guard !floorMapInfo.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !floorMapInfo.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              floorMapInfo.width > 0,
              floorMapInfo.depth > 0 else {
            print("❌ フロアマップデータが無効です")
            handleError("フロアマップデータが無効です")
            clearFloorMapData()
            return
        }

        print("✅ フロアマップ情報の設定成功:")
        print("   ID: \(floorMapInfo.id)")
        print("   名前: \(floorMapInfo.name)")
        print("   ビル名: \(floorMapInfo.buildingName)")
        print("   サイズ: \(floorMapInfo.width)x\(floorMapInfo.depth)")

        currentFloorMapId = floorMapInfo.id
        currentFloorMapInfo = floorMapInfo
        print("🔄 フロアマップ情報を設定し、画像読み込みを開始")
        loadFloorMapImage(for: floorMapInfo.id)
    }

    /// フロアマップデータをクリア
    private func clearFloorMapData() {
        currentFloorMapId = ""
        currentFloorMapInfo = nil
        floorMapImage = nil
    }

    /// フロアマップ画像を読み込み
    private func loadFloorMapImage(for floorMapId: String) {
        print("🖼️ フロアマップ画像読み込み開始: \(floorMapId)")
        print("🔍 currentFloorMapInfo: \(currentFloorMapInfo?.name ?? "nil")")

        // FloorMapInfoのimageプロパティを使用して統一された方法で読み込む
        if let floorMapInfo = currentFloorMapInfo,
           let image = floorMapInfo.image {
            print("✅ FloorMapInfo.imageプロパティから画像を取得成功: \(image.size)")
            floorMapImage = image
            print("✅ floorMapImageプロパティに設定完了")
            return
        }

        print("❌ FloorMapInfo.imageプロパティからの画像取得に失敗")

        // フォールバック: 独自の検索ロジック
        let fileManager = FileManager.default

        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Documents ディレクトリが見つかりません")
            return
        }

        print("📁 Documents パス: \(documentsPath.path)")

        // 複数の場所を検索
        let searchPaths = [
            documentsPath.appendingPathComponent("\(floorMapId).jpg"),  // Documents直下（FloorMapInfo.imageと同じ）
            documentsPath.appendingPathComponent("\(floorMapId).png"),  // Documents直下（PNG版）
            documentsPath.appendingPathComponent("FloorMaps").appendingPathComponent("\(floorMapId).jpg"),  // FloorMapsサブディレクトリ
            documentsPath.appendingPathComponent("FloorMaps").appendingPathComponent("\(floorMapId).png")   // FloorMapsサブディレクトリ（PNG版）
        ]

        for imageURL in searchPaths {
            print("🔍 検索中: \(imageURL.path)")

            if fileManager.fileExists(atPath: imageURL.path) {
                print("✅ ファイルが存在します: \(imageURL.lastPathComponent)")

                do {
                    let imageData = try Data(contentsOf: imageURL)
                    print("📊 画像データサイズ: \(imageData.count) bytes")

                    #if canImport(UIKit)
                        if let image = UIImage(data: imageData) {
                            print("✅ UIImage作成成功: \(image.size)")
                            floorMapImage = image
                            return
                        } else {
                            print("❌ UIImageの作成に失敗")
                        }
                    #elseif canImport(AppKit)
                        if let image = NSImage(data: imageData) {
                            print("✅ NSImage作成成功: \(image.size)")
                            floorMapImage = image
                            return
                        } else {
                            print("❌ NSImageの作成に失敗")
                        }
                    #endif
                } catch {
                    print("❌ ファイル読み込みエラー: \(error)")
                }
            }
        }

        // デバッグ: Documentsディレクトリ内のファイル一覧を表示
        do {
            let files = try fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            print("📂 Documents内のファイル: \(files.map { $0.lastPathComponent })")
        } catch {
            print("❌ Documentsディレクトリ内容の取得に失敗: \(error)")
        }

        print("❌ すべての場所でフロアマップ画像が見つかりませんでした")
    }

    /// SwiftDataからアンテナ位置データを読み込み
    private func loadAntennaPositionsFromSwiftData() async {
        print("📍 SwiftDataからアンテナ位置データ読み込み開始")

        guard let repository = swiftDataRepository else {
            print("❌ SwiftDataRepository が利用できません")
            antennaPositions = []
            return
        }

        guard let floorMapId = currentFloorMapInfo?.id else {
            print("❌ フロアマップIDが設定されていません")
            antennaPositions = []
            return
        }

        do {
            let positions = try await repository.loadAntennaPositions(for: floorMapId)
            antennaPositions = positions
            print("✅ SwiftDataからアンテナ位置データ読み込み完了: \(positions.count)個")

            for position in positions {
                print("   - \(position.antennaName) (ID: \(position.antennaId))")
                print("     位置: (\(position.position.x), \(position.position.y), \(position.position.z))")
                print("     向き: \(position.rotation)°")
            }
        } catch {
            print("❌ SwiftDataからのアンテナ位置データ読み込みに失敗: \(error)")
            antennaPositions = []
        }
    }

    /// アンテナ位置データを読み込み
    private func loadAntennaPositions() {
        print("📍 アンテナ位置データ読み込み開始")

        // SwiftDataRepositoryが利用可能な場合はそちらを優先
        if let _ = swiftDataRepository {
            Task { @MainActor in
                await loadAntennaPositionsFromSwiftData()
            }
            return
        }

        // フォールバック: DataRepositoryを使用
        guard let floorMapId = currentFloorMapInfo?.id else {
            print("❌ フロアマップIDが設定されていません")
            antennaPositions = []
            return
        }

        if let positions = dataRepository.loadAntennaPositions() {
            // 現在のフロアマップに関連するアンテナ位置のみをフィルタ
            let filteredPositions = positions.filter { $0.floorMapId == floorMapId }
            antennaPositions = filteredPositions
            print("✅ アンテナ位置データ読み込み完了 (UserDefaults): \(filteredPositions.count)個")

            for position in filteredPositions {
                print("   - \(position.antennaName) (ID: \(position.antennaId))")
                print("     位置: (\(position.position.x), \(position.position.y), \(position.position.z))")
                print("     向き: \(position.rotation)°")
            }
        } else {
            print("❌ アンテナ位置データの読み込みに失敗")
            antennaPositions = []
        }
    }

    /// キャリブレーション用の測定点をセットアップ
    private func setupCalibrationPoints() {
        // 既存のキャリブレーションデータをクリア
        calibrationUsecase.clearCalibrationData(for: selectedAntennaId)

        // 基準座標を測定点として追加
        // 注意: 実際の実装では、各基準座標に対応する測定座標を取得する必要があります
        // ここでは簡略化のため、基準座標をそのまま測定座標としています
        for referencePoint in referencePoints {
            calibrationUsecase.addCalibrationPoint(
                for: selectedAntennaId,
                referencePosition: referencePoint,
                measuredPosition: referencePoint // 実際の実装では実測値を使用
            )
        }
    }

    /// キャリブレーション実行
    private func performCalibration() {
        Task {
            // プログレス更新のタイマーを開始
            startProgressTimer()

            // キャリブレーション実行
            await calibrationUsecase.performCalibration(for: selectedAntennaId)

            await MainActor.run {
                // タイマーを停止
                calibrationTimer?.invalidate()

                // 結果を取得
                if let result = calibrationUsecase.lastCalibrationResult {
                    calibrationResult = result
                    calibrationProgress = 1.0
                    isCalibrating = false

                    if result.success {
                        showSuccessAlert = true
                    } else {
                        showError(result.errorMessage ?? "キャリブレーションに失敗しました")
                    }
                } else {
                    isCalibrating = false
                    showError("キャリブレーション結果を取得できませんでした")
                }
            }
        }
    }

    /// プログレス更新タイマーを開始
    private func startProgressTimer() {
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCalibrating else { return }

                // プログレスをゆっくり更新（実際の処理進行度に合わせて調整）
                if self.calibrationProgress < 0.95 {
                    self.calibrationProgress += 0.02
                }
            }
        }
    }

    /// UserDefaultsの変更を監視してフロアマップデータを更新
    private func setupDataObserver() {
        // UserDefaultsの "currentFloorMapInfo" キーの変更を監視
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadCurrentFloorMapData()
                }
            }
            .store(in: &cancellables)
    }

    /// エラー表示
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
        isCalibrating = false
    }

    /// 包括的なエラーハンドリング
    private func handleError(_ message: String) {
        print("❌ SimpleCalibrationViewModel Error: \(message)")
        showError(message)
    }

    /// 安全な非同期タスク実行
    private func safeAsyncTask<T>(
        operation: @escaping () async throws -> T,
        onSuccess: @escaping (T) -> Void = { _ in },
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        Task {
            do {
                let result = try await operation()
                await MainActor.run {
                    onSuccess(result)
                }
            } catch {
                await MainActor.run {
                    handleError(error.localizedDescription)
                    onFailure(error)
                }
            }
        }
    }
}
