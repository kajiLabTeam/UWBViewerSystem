import Foundation
import SwiftData

/// 各アンテナの位置と角度を自動推定するキャリブレーションUsecase
///
/// # 概要
/// 複数のタグ位置（既知）でセンシングを行い、各アンテナが観測した座標から
/// アフィン変換を推定してアンテナの位置と角度を自動計算します。
///
/// # キャリブレーションフロー
/// 1. 複数の既知のタグ位置を設定
/// 2. 各位置でセンシングを実行し、各アンテナの観測データを収集
/// 3. 各アンテナごとに「観測座標 → 真の座標」のアフィン変換を推定
/// 4. 推定した変換からアンテナの位置と角度を抽出
/// 5. アンテナ設定をSwiftDataに保存
///
/// # 使い方
/// ```swift
/// let usecase = AutoAntennaCalibrationUsecase(
///     swiftDataRepository: repository,
///     observationUsecase: observationUsecase
/// )
///
/// // タグの真の座標を設定
/// let truePositions: [String: Point3D] = [
///     "tag1": Point3D(x: 1.0, y: 2.0, z: 0),
///     "tag2": Point3D(x: 3.0, y: 4.0, z: 0),
///     "tag3": Point3D(x: 5.0, y: 6.0, z: 0)
/// ]
/// usecase.setTrueTagPositions(truePositions)
///
/// // データ収集後、キャリブレーション実行
/// try await usecase.executeAutoCalibration(for: ["antenna1", "antenna2"])
/// ```
actor AutoAntennaCalibrationUsecase {

    // MARK: - Dependencies

    private let swiftDataRepository: SwiftDataRepository
    private let observationUsecase: ObservationDataUsecase
    private let affineCalibration = AntennaAffineCalibration()

    // MARK: - State

    /// タグIDごとの真の座標（既知の正確な位置）
    private var trueTagPositions: [String: Point3D] = [:]

    /// アンテナIDごとの測定データ（タグIDごとの観測座標リスト）
    private var measuredDataByAntenna: [String: [String: [Point3D]]] = [:]

    /// キャリブレーション結果
    private var calibrationResults: [String: AntennaAffineCalibration.AntennaConfig] = [:]

    // MARK: - Initialization

    init(
        swiftDataRepository: SwiftDataRepository,
        observationUsecase: ObservationDataUsecase
    ) {
        self.swiftDataRepository = swiftDataRepository
        self.observationUsecase = observationUsecase
    }

    // MARK: - Public Methods

    /// タグの真の座標を設定
    ///
    /// - Parameter positions: タグIDごとの真の座標
    func setTrueTagPositions(_ positions: [String: Point3D]) {
        self.trueTagPositions = positions
        print("📍 真のタグ位置を設定しました: \(positions.count)個")
    }

    /// 観測データを追加（リアルタイムデータから）
    ///
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - tagId: タグID
    ///   - measuredPosition: 観測された座標
    func addMeasuredData(antennaId: String, tagId: String, measuredPosition: Point3D) {
        if self.measuredDataByAntenna[antennaId] == nil {
            self.measuredDataByAntenna[antennaId] = [:]
        }
        if self.measuredDataByAntenna[antennaId]?[tagId] == nil {
            self.measuredDataByAntenna[antennaId]?[tagId] = []
        }
        self.measuredDataByAntenna[antennaId]?[tagId]?.append(measuredPosition)
    }

    /// ObservationSessionからデータを収集
    ///
    /// - Parameters:
    ///   - sessionId: センシングセッションID
    ///   - tagId: タグID（この位置でのセンシング対象）
    func collectDataFromSession(sessionId: String, tagId: String) async throws {
        // ObservationUsecaseからセッションデータを取得
        guard let session = await observationUsecase.currentSessions[sessionId] else {
            throw NSError(
                domain: "AutoAntennaCalibrationUsecase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "セッション \(sessionId) が見つかりません"]
            )
        }

        let observations = session.observations

        print("📊 セッション \(sessionId) からデータ収集: \(observations.count)件")

        for observation in observations {
            let antennaId = observation.antennaId

            // 観測座標を取得
            let measuredPosition = observation.position

            // データを追加
            self.addMeasuredData(
                antennaId: antennaId,
                tagId: tagId,
                measuredPosition: measuredPosition
            )
        }

        print("✅ タグ \(tagId) のデータ収集完了")
    }

    /// 自動キャリブレーションを実行
    ///
    /// - Parameters:
    ///   - antennaIds: キャリブレーション対象のアンテナID配列
    ///   - minObservationsPerTag: タグあたりの最小観測回数（デフォルト: 5）
    /// - Returns: アンテナIDごとのキャリブレーション結果
    /// - Throws: データ不足やキャリブレーション失敗時
    func executeAutoCalibration(
        for antennaIds: [String],
        minObservationsPerTag: Int = 5
    ) async throws -> [String: AntennaAffineCalibration.AntennaConfig] {
        guard !self.trueTagPositions.isEmpty else {
            throw CalibrationError.noTruePositions
        }

        print("""
        🚀 自動キャリブレーション開始
           対象アンテナ: \(antennaIds.count)個
           真のタグ位置: \(self.trueTagPositions.count)個
        """)

        var results: [String: AntennaAffineCalibration.AntennaConfig] = [:]

        for antennaId in antennaIds {
            do {
                let config = try await calibrateAntenna(
                    antennaId: antennaId,
                    minObservationsPerTag: minObservationsPerTag
                )
                results[antennaId] = config
                print("✅ \(antennaId) のキャリブレーション成功")
            } catch {
                print("❌ \(antennaId) のキャリブレーション失敗: \(error)")
                throw error
            }
        }

        self.calibrationResults = results
        print("🎉 全アンテナのキャリブレーション完了")

        return results
    }

    /// 特定のアンテナをキャリブレーション
    ///
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - minObservationsPerTag: タグあたりの最小観測回数
    /// - Returns: キャリブレーション結果
    /// - Throws: データ不足やキャリブレーション失敗時
    func calibrateAntenna(
        antennaId: String,
        minObservationsPerTag: Int = 5
    ) async throws -> AntennaAffineCalibration.AntennaConfig {
        guard let measuredData = measuredDataByAntenna[antennaId] else {
            throw CalibrationError.noMeasuredData(antennaId: antennaId)
        }

        // データフィルタリング: 最小観測回数を満たすタグのみ
        let filteredData = measuredData.filter { _, measurements in
            measurements.count >= minObservationsPerTag
        }

        guard filteredData.count >= 3 else {
            throw CalibrationError.insufficientTags(
                antennaId: antennaId,
                required: 3,
                found: filteredData.count
            )
        }

        print("""
        📡 \(antennaId) のキャリブレーション
           使用可能なタグ: \(filteredData.count)個
           各タグの観測数: \(filteredData.mapValues { $0.count })
        """)

        // アフィン変換を推定してアンテナ設定を取得
        let config = try affineCalibration.estimateAntennaConfig(
            measuredPointsByTag: filteredData,
            truePositions: self.trueTagPositions
        )

        return config
    }

    /// キャリブレーション結果をSwiftDataに保存
    ///
    /// - Parameters:
    ///   - floorMapId: フロアマップID
    ///   - results: キャリブレーション結果（アンテナIDごと）
    func saveCalibrationResults(
        floorMapId: String,
        results: [String: AntennaAffineCalibration.AntennaConfig]
    ) async throws {
        for (antennaId, config) in results {
            // 既存のアンテナ位置を検索
            let existingPositions = try await swiftDataRepository.loadAntennaPositions(
                for: floorMapId
            )

            if let existing = existingPositions.first(where: { $0.antennaId == antennaId }) {
                // 更新
                let updatedPosition = AntennaPositionData(
                    id: existing.id,
                    antennaId: antennaId,
                    antennaName: existing.antennaName,
                    position: config.position,
                    rotation: config.angleDegrees,
                    floorMapId: floorMapId
                )
                try await self.swiftDataRepository.updateAntennaPosition(updatedPosition)
                print("♻️  \(antennaId) の位置を更新しました")
            } else {
                // 新規作成
                let antennaPosition = AntennaPositionData(
                    id: UUID().uuidString,
                    antennaId: antennaId,
                    antennaName: antennaId,
                    position: config.position,
                    rotation: config.angleDegrees,
                    floorMapId: floorMapId
                )
                try await self.swiftDataRepository.saveAntennaPosition(antennaPosition)
                print("➕ \(antennaId) の位置を新規作成しました")
            }
        }

        print("💾 全てのキャリブレーション結果を保存しました")
    }

    /// キャリブレーション結果を取得
    func getCalibrationResults() -> [String: AntennaAffineCalibration.AntennaConfig] {
        self.calibrationResults
    }

    /// データをクリア
    func clearData() {
        self.measuredDataByAntenna.removeAll()
        self.calibrationResults.removeAll()
        print("🧹 キャリブレーションデータをクリアしました")
    }

    /// 特定のアンテナのデータをクリア
    func clearData(for antennaId: String) {
        self.measuredDataByAntenna.removeValue(forKey: antennaId)
        self.calibrationResults.removeValue(forKey: antennaId)
        print("🧹 \(antennaId) のデータをクリアしました")
    }

    /// 現在の測定データの統計情報を取得
    func getDataStatistics() -> [String: [String: Int]] {
        self.measuredDataByAntenna.mapValues { tagData in
            tagData.mapValues { $0.count }
        }
    }

    // MARK: - Errors

    enum CalibrationError: LocalizedError {
        case noTruePositions
        case noMeasuredData(antennaId: String)
        case insufficientTags(antennaId: String, required: Int, found: Int)

        var errorDescription: String? {
            switch self {
            case .noTruePositions:
                return "真のタグ位置が設定されていません。setTrueTagPositions()を呼び出してください。"
            case .noMeasuredData(let antennaId):
                return "アンテナ \(antennaId) の測定データがありません。"
            case .insufficientTags(let antennaId, let required, let found):
                return
                    "アンテナ \(antennaId) のタグ数が不足しています。最低\(required)個必要ですが、\(found)個しかありません。"
            }
        }
    }
}

// MARK: - Helper Extensions

extension AutoAntennaCalibrationUsecase {

    /// デバッグ用: 現在の状態をログ出力
    func printDebugInfo() {
        print("""

        === AutoAntennaCalibration Debug Info ===
        真のタグ位置: \(self.trueTagPositions.count)個
        \(self.trueTagPositions.map { "  - \($0.key): (\($0.value.x), \($0.value.y))" }.joined(separator: "\n"))

        測定データ:
        \(self.measuredDataByAntenna.map { antennaId, tagData in
            "  - \(antennaId): \(tagData.count)タグ"
                + "\n" + tagData.map { tagId, measurements in
                    "    - \(tagId): \(measurements.count)観測"
                }.joined(separator: "\n")
        }.joined(separator: "\n"))

        キャリブレーション結果: \(self.calibrationResults.count)個
        \(self.calibrationResults.map { antennaId, config in
            "  - \(antennaId): pos=(\(config.x), \(config.y)), angle=\(config.angleDegrees)°, rmse=\(config.rmse)"
        }.joined(separator: "\n"))
        =========================================

        """)
    }
}
