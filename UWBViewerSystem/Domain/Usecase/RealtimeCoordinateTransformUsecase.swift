import Foundation

/// リアルタイムセンサーデータの座標変換を行うUsecase
///
/// 極座標（距離、仰角、方位）からグローバル座標（フロアマップ座標系）への変換を実行します。
@MainActor
public class RealtimeCoordinateTransformUsecase {

    private let swiftDataRepository: SwiftDataRepository

    public init(swiftDataRepository: SwiftDataRepository) {
        self.swiftDataRepository = swiftDataRepository
    }

    /// 極座標からグローバル座標への変換
    ///
    /// - Parameters:
    ///   - distance: 距離（メートル）
    ///   - elevation: 仰角（度）
    ///   - azimuth: 方位角（度）
    ///   - antennaId: アンテナID
    ///   - floorMapId: フロアマップID
    /// - Returns: グローバル座標（Point3D）。変換失敗時はnil
    public func transformToGlobalCoordinate(
        distance: Double,
        elevation: Double,
        azimuth: Double,
        antennaId: String,
        floorMapId: String
    ) async -> Point3D? {
        // アンテナ位置情報を取得
        guard let antennaPositions = try? await swiftDataRepository.loadAntennaPositions(for: floorMapId),
              let antennaPosition = antennaPositions.first(where: { $0.antennaId == antennaId })
        else {
            print("⚠️ アンテナ位置情報が見つかりません: antennaId=\(antennaId), floorMapId=\(floorMapId)")
            return nil
        }

        // ステップ1: 極座標からローカル直交座標への変換
        let localCoord = self.polarToCartesian(distance: distance, elevation: elevation, azimuth: azimuth)

        // ステップ2: ローカル座標からグローバル座標への変換
        let globalCoord = self.localToGlobal(
            localCoord: localCoord,
            antennaPosition: antennaPosition.position,
            antennaRotation: antennaPosition.rotation
        )

        return globalCoord
    }

    /// 複数のリアルタイムデータをバッチ変換
    ///
    /// - Parameters:
    ///   - realtimeDataList: リアルタイムデータのリスト
    ///   - floorMapId: フロアマップID
    /// - Returns: デバイス名をキーとしたグローバル座標の辞書
    public func transformMultipleData(
        _ realtimeDataList: [RealtimeData],
        floorMapId: String
    ) async -> [String: Point3D] {
        var results: [String: Point3D] = [:]

        for data in realtimeDataList {
            if let globalCoord = await self.transformToGlobalCoordinate(
                distance: data.distance,
                elevation: data.elevation,
                azimuth: data.azimuth,
                antennaId: data.antennaId,
                floorMapId: floorMapId
            ) {
                results[data.deviceName] = globalCoord
            }
        }

        return results
    }

    // MARK: - Private Methods

    /// 極座標（球面座標）から直交座標への変換
    ///
    /// - Parameters:
    ///   - distance: 距離（メートル）
    ///   - elevation: 仰角（度）
    ///   - azimuth: 方位角（度） - UWB座標系では東が0度
    /// - Returns: ローカル直交座標（アンテナ中心）
    private func polarToCartesian(distance: Double, elevation: Double, azimuth: Double) -> Point3D {
        // 角度をラジアンに変換
        let elevationRad = elevation * .pi / 180.0
        // UWB座標系（東が0度）から数学的座標系（北が0度）に変換するため90度加算
        let azimuthRad = (azimuth + 90.0) * .pi / 180.0

        // 球面座標から直交座標への変換
        // x: 東西方向（東が正）
        // y: 南北方向（北が正）
        // z: 上下方向（上が正）
        let x = distance * cos(elevationRad) * sin(azimuthRad)
        let y = distance * cos(elevationRad) * cos(azimuthRad)
        let z = distance * sin(elevationRad)

        return Point3D(x: x, y: y, z: z)
    }

    /// ローカル座標からグローバル座標への変換
    ///
    /// アンテナの位置と回転角度を考慮して、アンテナローカル座標をフロアマップのグローバル座標に変換します。
    ///
    /// - Parameters:
    ///   - localCoord: ローカル直交座標（アンテナ中心）
    ///   - antennaPosition: アンテナのグローバル位置（フロアマップ座標系）
    ///   - antennaRotation: アンテナの回転角度（度）
    /// - Returns: グローバル直交座標（フロアマップ座標系）
    private func localToGlobal(
        localCoord: Point3D,
        antennaPosition: Point3D,
        antennaRotation: Double
    ) -> Point3D {
        // 回転角度をラジアンに変換
        let rotationRad = antennaRotation * .pi / 180.0

        // 回転行列を適用（Z軸周りの回転）
        let rotatedX = localCoord.x * cos(rotationRad) - localCoord.y * sin(rotationRad)
        let rotatedY = localCoord.x * sin(rotationRad) + localCoord.y * cos(rotationRad)

        // アンテナ位置を加算してグローバル座標に変換
        let globalX = antennaPosition.x + rotatedX
        let globalY = antennaPosition.y + rotatedY
        let globalZ = antennaPosition.z + localCoord.z

        return Point3D(x: globalX, y: globalY, z: globalZ)
    }

    /// アンテナIDに対応するアンテナ位置情報を取得
    ///
    /// - Parameters:
    ///   - antennaId: アンテナID
    ///   - floorMapId: フロアマップID
    /// - Returns: アンテナ位置情報。見つからない場合はnil
    public func getAntennaPosition(antennaId: String, floorMapId: String) async -> AntennaPositionData? {
        guard let antennaPositions = try? await swiftDataRepository.loadAntennaPositions(for: floorMapId) else {
            return nil
        }
        return antennaPositions.first(where: { $0.antennaId == antennaId })
    }

    /// すべてのアンテナ位置情報を取得
    ///
    /// - Parameter floorMapId: フロアマップID
    /// - Returns: アンテナ位置情報の配列
    public func getAllAntennaPositions(floorMapId: String) async -> [AntennaPositionData] {
        guard let antennaPositions = try? await swiftDataRepository.loadAntennaPositions(for: floorMapId) else {
            return []
        }
        return antennaPositions
    }
}
