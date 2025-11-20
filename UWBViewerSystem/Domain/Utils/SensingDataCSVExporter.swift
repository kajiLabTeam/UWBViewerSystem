import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// センシングデータのCSVエクスポート機能
///
/// Android側からの生データとグローバル座標変換後のデータをCSVファイルとして端末に保存する
struct SensingDataCSVExporter {

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case noDataToExport
        case fileCreationFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDataToExport:
                return "エクスポートするデータがありません"
            case .fileCreationFailed(let message):
                return "ファイル作成エラー: \(message)"
            case .writeFailed(let message):
                return "ファイル書き込みエラー: \(message)"
            }
        }
    }

    // MARK: - 生データCSVエクスポート

    /// 生データ(Android側からの受信データ)をCSVとしてエクスポート
    ///
    /// CSVフォーマット:
    /// ```
    /// timestamp,deviceName,antennaId,elevation,azimuth,distance,nlos,rssi,seqCount
    /// 1699876543210,Device1,antenna1,45.5,120.0,5.23,0,-65.5,123
    /// ```
    ///
    /// - Parameters:
    ///   - realtimeDataList: エクスポートするリアルタイムデータのリスト
    ///   - sessionName: センシングセッション名（ファイル名に使用）
    /// - Returns: 生成されたCSVファイルのURL
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportRawDataToCSV(
        realtimeDataList: [RealtimeData],
        sessionName: String
    ) throws -> URL {
        guard !realtimeDataList.isEmpty else {
            throw ExportError.noDataToExport
        }

        // CSVヘッダー
        var csvContent =
            "timestamp,deviceName,antennaId,elevation,azimuth,distance,nlos,rssi,seqCount\n"

        // データ行
        for data in realtimeDataList {
            let row = [
                String(data.timestamp),
                data.deviceName,
                data.antennaId,
                String(format: "%.6f", data.elevation),
                String(format: "%.6f", data.azimuth),
                String(format: "%.6f", data.distance),
                String(data.nlos),
                String(format: "%.2f", data.rssi),
                String(data.seqCount),
            ].joined(separator: ",")

            csvContent += row + "\n"
        }

        // ファイル名生成
        let fileName = "\(sessionName)_raw_data.csv"

        // ファイルに書き込み
        return try self.writeCSVToDocumentsDirectory(content: csvContent, fileName: fileName)
    }

    // MARK: - グローバル座標データCSVエクスポート

    /// グローバル座標変換後のデータをCSVとしてエクスポート
    ///
    /// CSVフォーマット:
    /// ```
    /// timestamp,deviceName,antennaId,global_x,global_y,global_z,elevation,azimuth,distance,nlos,rssi
    /// 1699876543210,Device1,antenna1,14.123,18.456,0.0,45.5,120.0,5.23,0,-65.5
    /// ```
    ///
    /// - Parameters:
    ///   - realtimeDataList: エクスポートするリアルタイムデータのリスト
    ///   - globalCoordinates: デバイス名をキーとしたグローバル座標の辞書
    ///   - sessionName: センシングセッション名（ファイル名に使用）
    /// - Returns: 生成されたCSVファイルのURL
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportGlobalCoordinateDataToCSV(
        realtimeDataList: [RealtimeData],
        globalCoordinates: [String: Point3D],
        sessionName: String
    ) throws -> URL {
        guard !realtimeDataList.isEmpty else {
            throw ExportError.noDataToExport
        }

        // CSVヘッダー
        var csvContent =
            "timestamp,deviceName,antennaId,global_x,global_y,global_z,elevation,azimuth,distance,nlos,rssi\n"

        // データ行
        for data in realtimeDataList {
            // グローバル座標を取得（存在しない場合は0.0を使用）
            let globalCoord = globalCoordinates[data.deviceName] ?? Point3D(x: 0, y: 0, z: 0)

            let row = [
                String(data.timestamp),
                data.deviceName,
                data.antennaId,
                String(format: "%.6f", globalCoord.x),
                String(format: "%.6f", globalCoord.y),
                String(format: "%.6f", globalCoord.z),
                String(format: "%.6f", data.elevation),
                String(format: "%.6f", data.azimuth),
                String(format: "%.6f", data.distance),
                String(data.nlos),
                String(format: "%.2f", data.rssi),
            ].joined(separator: ",")

            csvContent += row + "\n"
        }

        // ファイル名生成
        let fileName = "\(sessionName)_global_coordinates.csv"

        // ファイルに書き込み
        return try self.writeCSVToDocumentsDirectory(content: csvContent, fileName: fileName)
    }

    // MARK: - Helper Methods

    /// CSV内容をDocumentsディレクトリに書き込む
    ///
    /// - Parameters:
    ///   - content: CSVファイルの内容
    ///   - fileName: 保存するファイル名
    /// - Returns: 保存されたファイルのURL
    /// - Throws: ファイル作成または書き込みに失敗した場合
    private static func writeCSVToDocumentsDirectory(content: String, fileName: String) throws
        -> URL
    {
        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw ExportError.fileCreationFailed("Documentsディレクトリが見つかりません")
        }

        let fileURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ CSVファイルを保存しました: \(fileURL.path)")
            return fileURL
        } catch {
            throw ExportError.writeFailed("ファイル書き込みに失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - ファイル共有機能

    /// エクスポートしたCSVファイルを共有するためのActivityViewControllerを作成
    ///
    /// - Parameter fileURL: 共有するCSVファイルのURL
    /// - Returns: UIActivityViewController（UIKit環境のみ）
    #if canImport(UIKit)
        #if os(iOS)
            static func createShareViewController(for fileURL: URL) -> UIActivityViewController
            {
                let activityViewController = UIActivityViewController(
                    activityItems: [fileURL],
                    applicationActivities: nil
                )
                return activityViewController
            }
        #endif
    #endif

    // MARK: - 両方のCSVを一度にエクスポート

    /// 生データとグローバル座標データの両方をエクスポート
    ///
    /// - Parameters:
    ///   - realtimeDataList: エクスポートするリアルタイムデータのリスト
    ///   - globalCoordinates: デバイス名をキーとしたグローバル座標の辞書
    ///   - sessionName: センシングセッション名
    /// - Returns: 生成された2つのCSVファイルのURL (rawDataURL, globalCoordinateURL)
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportBothCSVs(
        realtimeDataList: [RealtimeData],
        globalCoordinates: [String: Point3D],
        sessionName: String
    ) throws -> (rawDataURL: URL, globalCoordinateURL: URL) {
        let rawDataURL = try exportRawDataToCSV(
            realtimeDataList: realtimeDataList,
            sessionName: sessionName
        )

        let globalCoordinateURL = try exportGlobalCoordinateDataToCSV(
            realtimeDataList: realtimeDataList,
            globalCoordinates: globalCoordinates,
            sessionName: sessionName
        )

        return (rawDataURL: rawDataURL, globalCoordinateURL: globalCoordinateURL)
    }
}
