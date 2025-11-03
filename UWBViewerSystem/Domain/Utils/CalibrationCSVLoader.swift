import Foundation

/// キャリブレーション用のCSVファイルローダー
///
/// PythonスクリプトのCSV読み込み機能を実装
/// - TAG_CONFIG.csv: タグの既知位置情報
/// - INITIAL_ANTENNA_CONFIG.csv: アンテナの初期位置情報
struct CalibrationCSVLoader {

    // MARK: - Errors

    enum LoaderError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case parsingError(String, line: Int)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let filename):
                return "ファイルが見つかりません: \(filename)"
            case .invalidFormat(let message):
                return "無効なフォーマット: \(message)"
            case .parsingError(let message, let line):
                return "パースエラー (行\(line)): \(message)"
            }
        }
    }

    // MARK: - TAG_CONFIG.csv

    /// TAG_CONFIG.csvからタグ位置を読み込む
    ///
    /// CSVフォーマット:
    /// ```
    /// NAME,POSITION_X,POSITION_Y
    /// Tag 1,14.090,18.134
    /// Tag 2,15.260,18.090
    /// Tag 3,14.592,16.592
    /// ```
    ///
    /// - Parameter url: TAG_CONFIG.csvのURL
    /// - Returns: タグ名をキーとした位置情報の辞書
    /// - Throws: ファイルが見つからない、またはフォーマットが無効な場合
    static func loadTagConfig(from url: URL) throws -> [String: Point3D] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoaderError.fileNotFound(url.lastPathComponent)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw LoaderError.invalidFormat("CSVファイルが空です")
        }

        // ヘッダー行を検証
        let header = lines[0].components(separatedBy: ",")
        guard
            header.count >= 3,
            header[0].trimmingCharacters(in: .whitespaces).uppercased() == "NAME",
            header[1].trimmingCharacters(in: .whitespaces).uppercased().contains("POSITION_X"),
            header[2].trimmingCharacters(in: .whitespaces).uppercased().contains("POSITION_Y")
        else {
            throw LoaderError.invalidFormat(
                "ヘッダー行が無効です。必要な列: NAME, POSITION_X, POSITION_Y"
            )
        }

        var tagConfig: [String: Point3D] = [:]

        // データ行をパース
        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2  // ヘッダー行を含めた行番号
            let columns = line.components(separatedBy: ",")

            guard columns.count >= 3 else {
                throw LoaderError.parsingError(
                    "列数が不足しています（必要: 3列以上、実際: \(columns.count)列）",
                    line: lineNumber
                )
            }

            let name = columns[0].trimmingCharacters(in: .whitespaces)

            guard let x = Double(columns[1].trimmingCharacters(in: .whitespaces)) else {
                throw LoaderError.parsingError(
                    "POSITION_Xの値が無効です: \(columns[1])",
                    line: lineNumber
                )
            }

            guard let y = Double(columns[2].trimmingCharacters(in: .whitespaces)) else {
                throw LoaderError.parsingError(
                    "POSITION_Yの値が無効です: \(columns[2])",
                    line: lineNumber
                )
            }

            tagConfig[name] = Point3D(x: x, y: y, z: 0)
        }

        print("✅ TAG_CONFIG.csvを読み込みました: \(tagConfig.count)個のタグ")
        return tagConfig
    }

    // MARK: - INITIAL_ANTENNA_CONFIG.csv

    /// INITIAL_ANTENNA_CONFIG.csvからアンテナ初期位置を読み込む
    ///
    /// CSVフォーマット:
    /// ```
    /// NAME,POSITION_X,POSITION_Y,ANGLE
    /// Antenna 1,14.500,8.000,90.0
    /// ```
    /// または
    /// ```
    /// NAME,POSITION_X,POSITION_Y,ROTATION
    /// Antenna 1,14.500,8.000,90.0
    /// ```
    ///
    /// - Parameter url: INITIAL_ANTENNA_CONFIG.csvのURL
    /// - Returns: アンテナ名をキーとした位置・角度情報の辞書
    /// - Throws: ファイルが見つからない、またはフォーマットが無効な場合
    static func loadInitialAntennaConfig(from url: URL) throws -> [String: (
        position: Point3D, rotation: Double
    )] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoaderError.fileNotFound(url.lastPathComponent)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw LoaderError.invalidFormat("CSVファイルが空です")
        }

        // ヘッダー行を検証
        let header = lines[0].components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces).uppercased()
        }

        guard header.count >= 4 else {
            throw LoaderError.invalidFormat("列数が不足しています（必要: 4列以上）")
        }

        guard header[0] == "NAME" else {
            throw LoaderError.invalidFormat("最初の列はNAMEである必要があります")
        }

        guard header[1].contains("POSITION_X") else {
            throw LoaderError.invalidFormat("2列目はPOSITION_Xである必要があります")
        }

        guard header[2].contains("POSITION_Y") else {
            throw LoaderError.invalidFormat("3列目はPOSITION_Yである必要があります")
        }

        // ANGLE または ROTATION 列を検索
        let angleColumnIndex: Int
        if let index = header.firstIndex(where: { $0 == "ANGLE" || $0 == "ROTATION" }) {
            angleColumnIndex = index
        } else {
            throw LoaderError.invalidFormat("ANGLE または ROTATION 列が見つかりません")
        }

        var antennaConfig: [String: (position: Point3D, rotation: Double)] = [:]

        // データ行をパース
        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2
            let columns = line.components(separatedBy: ",")

            guard columns.count >= 4 else {
                throw LoaderError.parsingError(
                    "列数が不足しています（必要: 4列以上、実際: \(columns.count)列）",
                    line: lineNumber
                )
            }

            let name = columns[0].trimmingCharacters(in: .whitespaces)

            guard let x = Double(columns[1].trimmingCharacters(in: .whitespaces)) else {
                throw LoaderError.parsingError(
                    "POSITION_Xの値が無効です: \(columns[1])",
                    line: lineNumber
                )
            }

            guard let y = Double(columns[2].trimmingCharacters(in: .whitespaces)) else {
                throw LoaderError.parsingError(
                    "POSITION_Yの値が無効です: \(columns[2])",
                    line: lineNumber
                )
            }

            guard columns.count > angleColumnIndex else {
                throw LoaderError.parsingError(
                    "ANGLE/ROTATION 列が不足しています（必要: \(angleColumnIndex + 1)列目）",
                    line: lineNumber
                )
            }

            let angleColumnValue = columns[angleColumnIndex].trimmingCharacters(in: .whitespaces)

            guard let angle = Double(angleColumnValue) else {
                throw LoaderError.parsingError(
                    "ANGLE/ROTATIONの値が無効です: \(angleColumnValue)",
                    line: lineNumber
                )
            }

            antennaConfig[name] = (
                position: Point3D(x: x, y: y, z: 0),
                rotation: angle
            )
        }

        print("✅ INITIAL_ANTENNA_CONFIG.csvを読み込みました: \(antennaConfig.count)個のアンテナ")
        return antennaConfig
    }

    // MARK: - デフォルト値

    /// デフォルトのタグ設定を取得
    ///
    /// TAG_CONFIG.csvが見つからない場合のフォールバック
    static func defaultTagConfig() -> [String: Point3D] {
        [
            "Tag 1": Point3D(x: 14.090, y: 18.134, z: 0),
            "Tag 2": Point3D(x: 15.260, y: 18.090, z: 0),
            "Tag 3": Point3D(x: 14.592, y: 16.592, z: 0),
        ]
    }

    /// デフォルトのアンテナ設定を取得
    ///
    /// INITIAL_ANTENNA_CONFIG.csvが見つからない場合のフォールバック
    static func defaultInitialAntennaConfig() -> [String: (position: Point3D, rotation: Double)] {
        [
            "Antenna 1": (
                position: Point3D(x: 14.500, y: 8.000, z: 0),
                rotation: 90.0
            )
        ]
    }

    // MARK: - ディレクトリからの読み込み

    /// ディレクトリパスからTAG_CONFIGとINITIAL_ANTENNA_CONFIGを読み込む
    ///
    /// - Parameter directoryURL: CSVファイルが存在するディレクトリのURL
    /// - Returns: タグ設定とアンテナ設定のタプル
    /// - Throws: ファイルの読み込みに失敗した場合
    static func loadCalibrationConfigs(from directoryURL: URL) throws -> (
        tagConfig: [String: Point3D],
        antennaConfig: [String: (position: Point3D, rotation: Double)]
    ) {
        let tagConfigURL = directoryURL.appendingPathComponent("TAG_CONFIG.csv")
        let antennaConfigURL = directoryURL.appendingPathComponent("INITIAL_ANTENNA_CONFIG.csv")

        let tagConfig: [String: Point3D]
        if FileManager.default.fileExists(atPath: tagConfigURL.path) {
            tagConfig = try self.loadTagConfig(from: tagConfigURL)
        } else {
            print("⚠️ TAG_CONFIG.csvが見つかりません。デフォルト値を使用します。")
            tagConfig = self.defaultTagConfig()
        }

        let antennaConfig: [String: (position: Point3D, rotation: Double)]
        if FileManager.default.fileExists(atPath: antennaConfigURL.path) {
            antennaConfig = try self.loadInitialAntennaConfig(from: antennaConfigURL)
        } else {
            print("⚠️ INITIAL_ANTENNA_CONFIG.csvが見つかりません。デフォルト値を使用します。")
            antennaConfig = self.defaultInitialAntennaConfig()
        }

        return (tagConfig: tagConfig, antennaConfig: antennaConfig)
    }
}
