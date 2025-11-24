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

    // MARK: - ディレクトリ管理

    /// センシングセッション用のディレクトリを作成
    ///
    /// ディレクトリ構造: /Applications/sensing/yyyymmdd/hhmmss/
    ///
    /// - Parameter startTime: センシング開始時刻
    /// - Returns: 作成されたディレクトリのURL
    /// - Throws: ディレクトリ作成に失敗した場合
    static func createSessionDirectory(startTime: Date) throws -> URL {
        // Documentsディレクトリを取得（ファイルアプリから見えるようにするため）
        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw ExportError.fileCreationFailed("Documentsディレクトリが見つかりません")
        }

        // 日付フォーマッターの設定
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        // 日付ディレクトリ名 (yyyymmdd)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: startTime)

        // 時刻ディレクトリ名 (hhmmss)
        dateFormatter.dateFormat = "HHmmss"
        let timeString = dateFormatter.string(from: startTime)

        // ディレクトリパスを構築
        let sessionDirectory = documentsDirectory
            .appendingPathComponent("sensing")
            .appendingPathComponent(dateString)
            .appendingPathComponent(timeString)

        // ディレクトリを作成
        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        print("✅ セッションディレクトリを作成: \(sessionDirectory.path)")
        print("📁 Documentsディレクトリ: \(documentsDirectory.path)")
        print("📁 相対パス: sensing/\(dateString)/\(timeString)")

        return sessionDirectory
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
    ///   - directoryURL: 保存先ディレクトリのURL
    ///   - fileName: ファイル名（デフォルト: "raw_data.csv"）
    /// - Returns: 生成されたCSVファイルのURL
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportRawDataToCSV(
        realtimeDataList: [RealtimeData],
        directoryURL: URL,
        fileName: String = "raw_data.csv"
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

        // ファイルに書き込み
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return try self.writeCSV(content: csvContent, to: fileURL)
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
    ///   - directoryURL: 保存先ディレクトリのURL
    ///   - fileName: ファイル名（デフォルト: "global_coordinates.csv"）
    /// - Returns: 生成されたCSVファイルのURL
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportGlobalCoordinateDataToCSV(
        realtimeDataList: [RealtimeData],
        globalCoordinates: [String: Point3D],
        directoryURL: URL,
        fileName: String = "global_coordinates.csv"
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

        // ファイルに書き込み
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return try self.writeCSV(content: csvContent, to: fileURL)
    }

    // MARK: - フィルタリング後データCSVエクスポート

    /// フィルタリング後（移動平均適用後）のデータをCSVとしてエクスポート
    ///
    /// CSVフォーマット:
    /// ```
    /// timestamp,deviceName,antennaId,filtered_x,filtered_y,filtered_z,original_x,original_y,original_z
    /// 1699876543210,Device1,antenna1,14.123,18.456,0.0,14.200,18.500,0.0
    /// ```
    ///
    /// - Parameters:
    ///   - realtimeDataList: エクスポートするリアルタイムデータのリスト
    ///   - globalCoordinates: デバイス名をキーとしたグローバル座標の辞書（元データ）
    ///   - processor: データ処理を行うSensorDataProcessor
    ///   - directoryURL: 保存先ディレクトリのURL
    ///   - fileName: ファイル名（デフォルト: "filtered_data.csv"）
    /// - Returns: 生成されたCSVファイルのURL
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportFilteredDataToCSV(
        realtimeDataList: [RealtimeData],
        globalCoordinates: [String: Point3D],
        processor: SensorDataProcessor,
        directoryURL: URL,
        fileName: String = "filtered_data.csv"
    ) throws -> URL {
        guard !realtimeDataList.isEmpty else {
            throw ExportError.noDataToExport
        }

        // デバイスごとにグループ化
        let groupedData = Dictionary(grouping: realtimeDataList) { $0.deviceName }

        // CSVヘッダー
        var csvContent =
            "timestamp,deviceName,antennaId,filtered_x,filtered_y,filtered_z,original_x,original_y,original_z\n"

        // 各デバイスのデータに移動平均フィルタを適用
        for (deviceName, deviceData) in groupedData.sorted(by: { $0.key < $1.key }) {
            // タイムスタンプでソート
            let sortedData = deviceData.sorted { $0.timestamp < $1.timestamp }

            // グローバル座標のリストを作成
            let coordinates = sortedData.compactMap { globalCoordinates[$0.deviceName] }

            guard !coordinates.isEmpty else { continue }

            // 移動平均フィルタを適用
            let filteredCoordinates = processor.applyMovingAverageToPoints(coordinates)

            // CSV行を作成
            for (index, data) in sortedData.enumerated() {
                guard index < filteredCoordinates.count else { break }

                let originalCoord = coordinates[index]
                let filteredCoord = filteredCoordinates[index]

                let row = [
                    String(data.timestamp),
                    deviceName,
                    data.antennaId,
                    String(format: "%.6f", filteredCoord.x),
                    String(format: "%.6f", filteredCoord.y),
                    String(format: "%.6f", filteredCoord.z),
                    String(format: "%.6f", originalCoord.x),
                    String(format: "%.6f", originalCoord.y),
                    String(format: "%.6f", originalCoord.z),
                ].joined(separator: ",")

                csvContent += row + "\n"
            }
        }

        // ファイルに書き込み
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return try self.writeCSV(content: csvContent, to: fileURL)
    }

    // MARK: - Helper Methods

    /// CSV内容をファイルに書き込む
    ///
    /// - Parameters:
    ///   - content: CSVファイルの内容
    ///   - fileURL: 保存先ファイルのURL
    /// - Returns: 保存されたファイルのURL
    /// - Throws: ファイル書き込みに失敗した場合
    private static func writeCSV(content: String, to fileURL: URL) throws -> URL {
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

    // MARK: - 全データエクスポート

    /// 生データ、グローバル座標データ、フィルタリング後データの全てをエクスポート
    ///
    /// - Parameters:
    ///   - realtimeDataList: エクスポートするリアルタイムデータのリスト
    ///   - globalCoordinates: デバイス名をキーとしたグローバル座標の辞書
    ///   - startTime: センシング開始時刻
    ///   - processor: データ処理を行うSensorDataProcessor（オプション）
    /// - Returns: (セッションディレクトリURL, 生データURL, グローバル座標URL, フィルタリング後データURL)
    /// - Throws: データが空、またはファイル作成/書き込みに失敗した場合
    static func exportAllData(
        realtimeDataList: [RealtimeData],
        globalCoordinates: [String: Point3D],
        startTime: Date,
        processor: SensorDataProcessor = SensorDataProcessor()
    ) throws -> (
        sessionDirectory: URL,
        rawDataURL: URL,
        globalCoordinateURL: URL,
        filteredDataURL: URL
    ) {
        // セッションディレクトリを作成
        let sessionDirectory = try createSessionDirectory(startTime: startTime)

        // 生データをエクスポート
        let rawDataURL = try exportRawDataToCSV(
            realtimeDataList: realtimeDataList,
            directoryURL: sessionDirectory
        )

        // グローバル座標データをエクスポート
        let globalCoordinateURL = try exportGlobalCoordinateDataToCSV(
            realtimeDataList: realtimeDataList,
            globalCoordinates: globalCoordinates,
            directoryURL: sessionDirectory
        )

        // フィルタリング後データをエクスポート
        let filteredDataURL = try exportFilteredDataToCSV(
            realtimeDataList: realtimeDataList,
            globalCoordinates: globalCoordinates,
            processor: processor,
            directoryURL: sessionDirectory
        )

        print("✅ 全センシングデータのエクスポート完了")
        print("   セッションディレクトリ: \(sessionDirectory.path)")

        return (
            sessionDirectory: sessionDirectory,
            rawDataURL: rawDataURL,
            globalCoordinateURL: globalCoordinateURL,
            filteredDataURL: filteredDataURL
        )
    }
}
