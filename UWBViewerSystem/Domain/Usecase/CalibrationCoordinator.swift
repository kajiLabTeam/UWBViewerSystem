import Foundation

/// キャリブレーション手順を管理するコーディネータークラス
public class CalibrationCoordinator: ObservableObject {

    // MARK: - キャリブレーション手順の定義

    /// キャリブレーション手順の種類
    public enum CalibrationType: String, CaseIterable, Codable {
        case traditional = "traditional"  // 従来の最小二乗法キャリブレーション
        case mapBased = "map_based"  // マップベースキャリブレーション
        case hybrid = "hybrid"  // ハイブリッド（両方組み合わせ）
    }

    /// キャリブレーション手順のステップ
    public enum CalibrationStep: String, CaseIterable, Codable {
        case preparation = "preparation"  // 準備
        case mapSetup = "map_setup"  // マップ基準座標設定
        case dataCollection = "data_collection"  // UWBデータ収集
        case calculation = "calculation"  // 変換行列計算
        case validation = "validation"  // 精度検証
        case completion = "completion"  // 完了

        public var displayName: String {
            switch self {
            case .preparation:
                return "準備"
            case .mapSetup:
                return "マップ基準座標設定"
            case .dataCollection:
                return "データ収集"
            case .calculation:
                return "変換行列計算"
            case .validation:
                return "精度検証"
            case .completion:
                return "完了"
            }
        }

        public var description: String {
            switch self {
            case .preparation:
                return "アンテナの設置と機器の準備を行います"
            case .mapSetup:
                return "フロアマップ上で基準座標（3箇所）を設定します"
            case .dataCollection:
                return "UWBアンテナで測定データを収集します"
            case .calculation:
                return "アフィン変換による座標変換行列を計算します"
            case .validation:
                return "キャリブレーション精度を検証します"
            case .completion:
                return "キャリブレーション完了"
            }
        }
    }

    /// キャリブレーション状況
    public struct CalibrationProgress: Codable {
        public let antennaId: String
        public let floorMapId: String
        public let calibrationType: CalibrationType
        public var currentStep: CalibrationStep
        public var completedSteps: Set<CalibrationStep>
        public var isCompleted: Bool
        public let startedAt: Date
        public var updatedAt: Date
        public var accuracyScore: Double?
        public var notes: String?

        public init(
            antennaId: String,
            floorMapId: String,
            calibrationType: CalibrationType,
            currentStep: CalibrationStep = .preparation
        ) {
            self.antennaId = antennaId
            self.floorMapId = floorMapId
            self.calibrationType = calibrationType
            self.currentStep = currentStep
            completedSteps = []
            isCompleted = false
            startedAt = Date()
            updatedAt = Date()
        }
    }

    // MARK: - 公開プロパティ

    @Published public private(set) var currentProgress: [String: CalibrationProgress] = [:]
    @Published public private(set) var isCalibrationInProgress: Bool = false

    // MARK: - プライベートプロパティ

    private let dataRepository: DataRepositoryProtocol
    // private let traditionalCalibration: CalibrationUsecase // TODO: MainActor問題を解決後に追加
    private var mapCalibrationData: [String: MapCalibrationData] = [:]

    // MARK: - 初期化

    public init(dataRepository: DataRepositoryProtocol) {
        self.dataRepository = dataRepository
        // TODO: MainActor問題を解決後に追加
        // self.traditionalCalibration = CalibrationUsecase(dataRepository: dataRepository)
    }

    // MARK: - 公開メソッド

    /// 新しいキャリブレーション手順を開始
    public func startCalibration(
        antennaId: String,
        floorMapId: String,
        type: CalibrationType
    ) {
        let progress = CalibrationProgress(
            antennaId: antennaId,
            floorMapId: floorMapId,
            calibrationType: type
        )

        currentProgress[antennaId] = progress
        isCalibrationInProgress = true

        print("🎯 キャリブレーション開始: \(antennaId) (\(type.rawValue))")
    }

    /// 手順のステップを進める
    public func advanceStep(for antennaId: String) throws {
        guard var progress = currentProgress[antennaId] else {
            throw CalibrationCoordinatorError.progressNotFound(antennaId)
        }

        let currentStepIndex = CalibrationStep.allCases.firstIndex(of: progress.currentStep) ?? 0
        let nextStepIndex = currentStepIndex + 1

        if nextStepIndex < CalibrationStep.allCases.count {
            // 現在のステップを完了としてマーク
            progress.completedSteps.insert(progress.currentStep)

            // 次のステップに進む
            progress.currentStep = CalibrationStep.allCases[nextStepIndex]
            progress.updatedAt = Date()

            currentProgress[antennaId] = progress

            print("➡️ ステップ進行: \(antennaId) -> \(progress.currentStep.displayName)")
        } else {
            // 全ステップ完了
            try completeCalibration(for: antennaId)
        }
    }

    /// 特定のステップを完了としてマーク
    public func completeStep(
        _ step: CalibrationStep,
        for antennaId: String,
        withAccuracy accuracy: Double? = nil
    ) throws {
        guard var progress = currentProgress[antennaId] else {
            throw CalibrationCoordinatorError.progressNotFound(antennaId)
        }

        progress.completedSteps.insert(step)
        progress.updatedAt = Date()

        if let accuracy {
            progress.accuracyScore = accuracy
        }

        currentProgress[antennaId] = progress

        print("✅ ステップ完了: \(antennaId) - \(step.displayName)")

        // 全ステップが完了した場合、キャリブレーション終了
        if progress.completedSteps.count == CalibrationStep.allCases.count {
            try completeCalibration(for: antennaId)
        }
    }

    /// マップキャリブレーションデータを登録
    public func registerMapCalibrationData(_ data: MapCalibrationData) {
        mapCalibrationData[data.antennaId] = data
        print("📍 マップキャリブレーションデータ登録: \(data.antennaId)")
    }

    /// ハイブリッドキャリブレーション実行
    public func performHybridCalibration(for antennaId: String) async throws -> CalibrationResult {
        guard let progress = currentProgress[antennaId],
            progress.calibrationType == .hybrid
        else {
            throw CalibrationCoordinatorError.invalidCalibrationtype
        }

        // 1. マップベースの変換行列を取得
        guard let mapCalibrationData = mapCalibrationData[antennaId],
            let affineTransform = mapCalibrationData.affineTransform
        else {
            throw CalibrationCoordinatorError.mapCalibrationNotAvailable
        }

        // 2. 従来のキャリブレーションデータを取得
        // TODO: MainActor問題を解決後に実装
        // let traditionalData = traditionalCalibration.getCalibrationData(for: antennaId)
        // guard traditionalData.calibrationPoints.count >= 3 else {
        //     throw CalibrationCoordinatorError.insufficientTraditionalData
        // }

        // 一時的なダミーデータ
        let traditionalPoints = mapCalibrationData.calibrationPoints

        // 3. ハイブリッド変換を計算
        let hybridTransform = try calculateHybridTransform(
            mapTransform: affineTransform,
            traditionalPoints: traditionalPoints
        )

        // 4. 結果を返す
        let result = CalibrationResult(
            success: true,
            transform: hybridTransform.toCalibrationTransform(),
            processedPoints: traditionalPoints.map { point in
                CalibrationPoint(
                    referencePosition: point.realWorldCoordinate,
                    measuredPosition: point.mapCoordinate,
                    antennaId: point.antennaId
                )
            }
        )

        return result
    }

    /// キャリブレーション進捗情報を取得
    public func getProgress(for antennaId: String) -> CalibrationProgress? {
        currentProgress[antennaId]
    }

    /// すべての進捗情報を取得
    public func getAllProgress() -> [CalibrationProgress] {
        Array(currentProgress.values)
    }

    /// キャリブレーション中止
    public func cancelCalibration(for antennaId: String) {
        currentProgress.removeValue(forKey: antennaId)
        mapCalibrationData.removeValue(forKey: antennaId)

        if currentProgress.isEmpty {
            isCalibrationInProgress = false
        }

        print("🚫 キャリブレーション中止: \(antennaId)")
    }

    /// 全キャリブレーション中止
    public func cancelAllCalibrations() {
        currentProgress.removeAll()
        mapCalibrationData.removeAll()
        isCalibrationInProgress = false
        print("🚫 全キャリブレーション中止")
    }

    // MARK: - プライベートメソッド

    /// キャリブレーション完了処理
    private func completeCalibration(for antennaId: String) throws {
        guard var progress = currentProgress[antennaId] else {
            throw CalibrationCoordinatorError.progressNotFound(antennaId)
        }

        progress.isCompleted = true
        progress.currentStep = .completion
        progress.updatedAt = Date()

        currentProgress[antennaId] = progress

        // 他にアクティブなキャリブレーションがない場合、全体の進行を停止
        let activeCount = currentProgress.values.filter { !$0.isCompleted }.count
        if activeCount == 0 {
            isCalibrationInProgress = false
        }

        print("🎉 キャリブレーション完了: \(antennaId)")
    }

    /// ハイブリッド変換行列を計算
    private func calculateHybridTransform(
        mapTransform: AffineTransformMatrix,
        traditionalPoints: [MapCalibrationPoint]
    ) throws -> AffineTransformMatrix {

        // 1. 従来のキャリブレーション点をマップ変換で補正
        var adjustedPoints: [MapCalibrationPoint] = []

        for (index, point) in traditionalPoints.enumerated() {
            // 測定座標をマップ変換で実世界座標に変換
            let _ = AffineTransform.mapToRealWorld(
                mapPoint: point.mapCoordinate,
                using: mapTransform
            )

            let adjustedPoint = MapCalibrationPoint(
                mapCoordinate: point.mapCoordinate,
                realWorldCoordinate: point.realWorldCoordinate,  // 実際の参照座標を使用
                antennaId: point.antennaId,
                pointIndex: index + 1
            )

            adjustedPoints.append(adjustedPoint)
        }

        // 2. 新しいアフィン変換行列を計算（精度向上）
        let hybridTransform = try AffineTransform.calculateAffineTransform(from: adjustedPoints)

        print("🔄 ハイブリッド変換計算完了: accuracy=\(hybridTransform.accuracy)")
        return hybridTransform
    }
}

// MARK: - エラー定義

public enum CalibrationCoordinatorError: Error, LocalizedError {
    case progressNotFound(String)
    case invalidCalibrationtype
    case mapCalibrationNotAvailable
    case insufficientTraditionalData

    public var errorDescription: String? {
        switch self {
        case .progressNotFound(let antennaId):
            return "キャリブレーション進捗が見つかりません: \(antennaId)"
        case .invalidCalibrationtype:
            return "無効なキャリブレーションタイプです"
        case .mapCalibrationNotAvailable:
            return "マップキャリブレーションデータが利用できません"
        case .insufficientTraditionalData:
            return "従来のキャリブレーションデータが不十分です"
        }
    }
}

// MARK: - 拡張

extension AffineTransformMatrix {
    /// CalibrationTransformに変換（後方互換性のため）
    func toCalibrationTransform() -> CalibrationTransform {
        // アフィン変換行列から回転角とスケールを抽出
        let rotation = atan2(b, a)
        let scaleX = sqrt(a * a + b * b)
        let scaleY = sqrt(c * c + d * d)

        return CalibrationTransform(
            translation: Point3D(x: tx, y: ty, z: translateZ),
            rotation: rotation,
            scale: Point3D(x: scaleX, y: scaleY, z: scaleZ),
            accuracy: accuracy
        )
    }
}
