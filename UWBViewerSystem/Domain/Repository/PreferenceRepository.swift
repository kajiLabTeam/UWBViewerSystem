import Foundation

// MARK: - 設定・プリファレンス管理用Repository

/// アプリケーション設定とプリファレンス管理のためのリポジトリプロトコル
///
/// このプロトコルは、UWBアプリケーションのすべての設定項目を統一的に管理するためのインターフェースを定義します。
/// フロアマップ設定、アンテナ位置、キャリブレーション結果、センシングフロー状態、デバイス管理など、
/// アプリケーションのすべての永続化設定を扱います。
///
/// ## 使用例
/// ```swift
/// let repository: PreferenceRepositoryProtocol = PreferenceRepository()
///
/// // フロアマップ情報の保存・読み込み
/// let floorMapInfo = FloorMapInfo(name: "1F", buildingName: "Office", width: 100.0, depth: 50.0)
/// repository.saveCurrentFloorMapInfo(floorMapInfo)
/// let loaded = repository.loadCurrentFloorMapInfo()
///
/// // キャリブレーション結果の管理
/// let calibrationResult = SystemCalibrationResult(...)
/// repository.saveLastCalibrationResult(calibrationResult)
/// ```
///
/// ## アーキテクチャにおける位置づけ
/// Clean Architecture + MVVMパターンにおけるDomain層のRepository層として機能し、
/// Presentation層のViewModelから利用されます。実装はUserDefaultsを使用した永続化を行います。
public protocol PreferenceRepositoryProtocol {
    // MARK: - フロアマップ設定関連

    /// 現在のフロアマップ情報を保存します
    /// - Parameter info: 保存するフロアマップ情報
    /// - Note: エラーが発生した場合はログに出力されます
    func saveCurrentFloorMapInfo(_ info: FloorMapInfo)

    /// 現在のフロアマップ情報を読み込みます
    /// - Returns: 保存されているフロアマップ情報、存在しない場合はnil
    func loadCurrentFloorMapInfo() -> FloorMapInfo?

    /// 現在のフロアマップ情報を削除します
    func removeCurrentFloorMapInfo()

    /// 最後に設定されたフロア設定を保存します
    /// - Parameters:
    ///   - name: フロア名
    ///   - buildingName: 建物名
    ///   - width: フロアの幅（メートル）
    ///   - depth: フロアの奥行き（メートル）
    func saveLastFloorSettings(name: String, buildingName: String, width: Double, depth: Double)

    /// 最後に設定されたフロア設定を読み込みます
    /// - Returns: フロア設定のタプル（name, buildingName, width, depth）、存在しない項目はnil
    func loadLastFloorSettings() -> (name: String?, buildingName: String?, width: Double?, depth: Double?)

    /// フロアマップが設定済みかどうかのフラグを設定します
    /// - Parameter configured: 設定済みの場合true、未設定の場合false
    func setHasFloorMapConfigured(_ configured: Bool)

    /// フロアマップが設定済みかどうかを取得します
    /// - Returns: 設定済みの場合true、未設定の場合false
    func getHasFloorMapConfigured() -> Bool

    // MARK: - アンテナ設定関連

    /// 設定済みのアンテナ位置情報を保存します
    /// - Parameter positions: 保存するアンテナ位置データの配列
    /// - Note: エラーが発生した場合はログに出力されます
    func saveConfiguredAntennaPositions(_ positions: [AntennaPositionData])

    /// 設定済みのアンテナ位置情報を読み込みます
    /// - Returns: 保存されているアンテナ位置データの配列、存在しない場合はnil
    func loadConfiguredAntennaPositions() -> [AntennaPositionData]?

    /// 設定済みのアンテナ位置情報を削除します
    func removeConfiguredAntennaPositions()

    // MARK: - キャリブレーション関連

    /// 最後のシステムキャリブレーション結果を保存します
    /// - Parameter result: 保存するキャリブレーション結果
    /// - Note: エラーが発生した場合はログに出力されます
    func saveLastCalibrationResult(_ result: SystemCalibrationResult)

    /// 最後のシステムキャリブレーション結果を読み込みます
    /// - Returns: 保存されているキャリブレーション結果、存在しない場合はnil
    func loadLastCalibrationResult() -> SystemCalibrationResult?

    /// 最後のシステムキャリブレーション結果を削除します
    func removeLastCalibrationResult()

    // MARK: - センシングフロー関連

    /// センシングフローの現在の状態を保存します
    /// - Parameters:
    ///   - currentStep: 現在のステップ名
    ///   - completedSteps: 完了したステップの配列
    ///   - isCompleted: フロー全体が完了しているかどうか
    /// - Note: エラーが発生した場合はログに出力されます
    func saveSensingFlowState(currentStep: String, completedSteps: [String], isCompleted: Bool)

    /// センシングフローの状態を読み込みます
    /// - Returns: フロー状態のタプル（currentStep, completedSteps, isCompleted）
    func loadSensingFlowState() -> (currentStep: String?, completedSteps: [String], isCompleted: Bool)

    /// センシングフローの状態をリセットします（すべての関連データを削除）
    func resetSensingFlowState()

    /// センシングセッションが実行済みかどうかのフラグを設定します
    /// - Parameter executed: 実行済みの場合true、未実行の場合false
    func setHasExecutedSensingSession(_ executed: Bool)

    /// センシングセッションが実行済みかどうかを取得します
    /// - Returns: 実行済みの場合true、未実行の場合false
    func getHasExecutedSensingSession() -> Bool

    // MARK: - デバイス管理関連

    /// ペアリング済みデバイスのリストを保存します
    /// - Parameter devices: デバイスIDの文字列配列
    /// - Note: エラーが発生した場合はログに出力されます
    func savePairedDevices(_ devices: [String])

    /// ペアリング済みデバイスのリストを読み込みます
    /// - Returns: 保存されているデバイスIDの配列、存在しない場合はnil
    func loadPairedDevices() -> [String]?

    /// ペアリング済みデバイスのリストを削除します
    func removePairedDevices()

    /// デバイス接続の統計情報を保存します
    /// - Parameter statistics: 統計データの辞書
    func saveConnectionStatistics(_ statistics: [String: Any])

    /// デバイス接続の統計情報を読み込みます
    /// - Returns: 保存されている統計データの辞書、存在しない場合はnil
    func loadConnectionStatistics() -> [String: Any]?

    // MARK: - データ移行関連

    /// 指定されたデータ移行タスクの完了状態を設定します
    /// - Parameters:
    ///   - key: 移行タスクを識別するキー
    ///   - completed: 移行が完了している場合true、未完了の場合false
    func setMigrationCompleted(for key: String, completed: Bool)

    /// 指定されたデータ移行タスクが完了しているかどうかを確認します
    /// - Parameter key: 移行タスクを識別するキー
    /// - Returns: 移行が完了している場合true、未完了の場合false
    func isMigrationCompleted(for key: String) -> Bool

    // MARK: - 汎用設定メソッド

    /// Bool値を指定されたキーで保存します
    /// - Parameters:
    ///   - value: 保存するBool値
    ///   - key: 保存キー
    func setBool(_ value: Bool, forKey key: String)

    /// 指定されたキーのBool値を取得します
    /// - Parameter key: 取得キー
    /// - Returns: 保存されているBool値（存在しない場合はfalse）
    func getBool(forKey key: String) -> Bool

    /// String値を指定されたキーで保存します
    /// - Parameters:
    ///   - value: 保存するString値（nilの場合は削除）
    ///   - key: 保存キー
    func setString(_ value: String?, forKey key: String)

    /// 指定されたキーのString値を取得します
    /// - Parameter key: 取得キー
    /// - Returns: 保存されているString値、存在しない場合はnil
    func getString(forKey key: String) -> String?

    /// Double値を指定されたキーで保存します
    /// - Parameters:
    ///   - value: 保存するDouble値
    ///   - key: 保存キー
    func setDouble(_ value: Double, forKey key: String)

    /// 指定されたキーのDouble値を取得します
    /// - Parameter key: 取得キー
    /// - Returns: 保存されているDouble値（存在しない場合は0.0）
    func getDouble(forKey key: String) -> Double

    /// Codableなデータオブジェクトを指定されたキーで保存します
    /// - Parameters:
    ///   - value: 保存するCodableオブジェクト
    ///   - key: 保存キー
    /// - Throws: エンコードに失敗した場合のエラー
    func setData(_ value: some Codable, forKey key: String) throws

    /// 指定されたキーのCodableなデータオブジェクトを取得します
    /// - Parameters:
    ///   - type: 取得するデータの型
    ///   - key: 取得キー
    /// - Returns: デコードされたオブジェクト、存在しないかデコードに失敗した場合はnil
    func getData<T: Codable>(_ type: T.Type, forKey key: String) -> T?

    /// 指定されたキーのオブジェクトを削除します
    /// - Parameter key: 削除するキー
    func removeObject(forKey key: String)
}

/// PreferenceRepositoryProtocolのUserDefaults実装
///
/// このクラスは、UserDefaultsを使用してアプリケーションの設定とプリファレンスを永続化します。
/// すべての設定項目を一元管理し、型安全なアクセスを提供します。
///
/// ## 設計方針
/// - **単一責任**: 設定データの永続化のみを担当
/// - **型安全**: Codableプロトコルを活用した型安全なデータ保存・取得
/// - **エラーハンドリング**: 保存失敗時のログ出力による透明性確保
/// - **テスト容易性**: UserDefaultsの注入による単体テストサポート
///
/// ## 使用例
/// ```swift
/// // 標準的な使用
/// let repository = PreferenceRepository()
///
/// // テスト用（独自のUserDefaultsを注入）
/// let testDefaults = UserDefaults(suiteName: "test")
/// let testRepository = PreferenceRepository(userDefaults: testDefaults)
///
/// // フロアマップ情報の管理
/// let floorInfo = FloorMapInfo(name: "1F", buildingName: "Office", width: 100.0, depth: 50.0)
/// repository.saveCurrentFloorMapInfo(floorInfo)
/// ```
///
/// ## パフォーマンス考慮事項
/// - UserDefaultsはメインスレッドでの同期アクセスを前提としています
/// - 大きなデータの保存時は適切なタイミングで呼び出してください
public class PreferenceRepository: PreferenceRepositoryProtocol {
    /// UserDefaultsインスタンス（依存性注入によりテスト可能）
    private let userDefaults: UserDefaults

    /// PreferenceRepositoryのイニシャライザ
    /// - Parameter userDefaults: 使用するUserDefaultsインスタンス（デフォルトは.standard）
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - フロアマップ設定関連

    public func saveCurrentFloorMapInfo(_ info: FloorMapInfo) {
        do {
            try setData(info, forKey: "currentFloorMapInfo")
        } catch {
            print("❌ フロアマップ情報の保存に失敗: \(error)")
        }
    }

    public func loadCurrentFloorMapInfo() -> FloorMapInfo? {
        getData(FloorMapInfo.self, forKey: "currentFloorMapInfo")
    }

    public func removeCurrentFloorMapInfo() {
        removeObject(forKey: "currentFloorMapInfo")
    }

    public func saveLastFloorSettings(name: String, buildingName: String, width: Double, depth: Double) {
        setString(name, forKey: "lastFloorName")
        setString(buildingName, forKey: "lastBuildingName")
        setDouble(width, forKey: "lastFloorWidth")
        setDouble(depth, forKey: "lastFloorDepth")
    }

    public func loadLastFloorSettings() -> (name: String?, buildingName: String?, width: Double?, depth: Double?) {
        let name = getString(forKey: "lastFloorName")
        let buildingName = getString(forKey: "lastBuildingName")
        let width = userDefaults.object(forKey: "lastFloorWidth") as? Double
        let depth = userDefaults.object(forKey: "lastFloorDepth") as? Double
        return (name, buildingName, width, depth)
    }

    public func setHasFloorMapConfigured(_ configured: Bool) {
        setBool(configured, forKey: "hasFloorMapConfigured")
    }

    public func getHasFloorMapConfigured() -> Bool {
        getBool(forKey: "hasFloorMapConfigured")
    }

    // MARK: - アンテナ設定関連

    public func saveConfiguredAntennaPositions(_ positions: [AntennaPositionData]) {
        do {
            try setData(positions, forKey: "configuredAntennaPositions")
        } catch {
            print("❌ アンテナ位置情報の保存に失敗: \(error)")
        }
    }

    public func loadConfiguredAntennaPositions() -> [AntennaPositionData]? {
        getData([AntennaPositionData].self, forKey: "configuredAntennaPositions")
    }

    public func removeConfiguredAntennaPositions() {
        removeObject(forKey: "configuredAntennaPositions")
    }

    // MARK: - キャリブレーション関連

    public func saveLastCalibrationResult(_ result: SystemCalibrationResult) {
        do {
            try setData(result, forKey: "lastCalibrationResult")
        } catch {
            print("❌ キャリブレーション結果の保存に失敗: \(error)")
        }
    }

    public func loadLastCalibrationResult() -> SystemCalibrationResult? {
        getData(SystemCalibrationResult.self, forKey: "lastCalibrationResult")
    }

    public func removeLastCalibrationResult() {
        removeObject(forKey: "lastCalibrationResult")
    }

    // MARK: - センシングフロー関連

    public func saveSensingFlowState(currentStep: String, completedSteps: [String], isCompleted: Bool) {
        do {
            try setData(currentStep, forKey: "sensingFlowCurrentStep")
            try setData(completedSteps, forKey: "sensingFlowCompletedSteps")
            setBool(isCompleted, forKey: "sensingFlowCompleted")
        } catch {
            print("❌ センシングフロー状態の保存に失敗: \(error)")
        }
    }

    public func loadSensingFlowState() -> (currentStep: String?, completedSteps: [String], isCompleted: Bool) {
        let currentStep = getData(String.self, forKey: "sensingFlowCurrentStep")
        let completedSteps = getData([String].self, forKey: "sensingFlowCompletedSteps") ?? []
        let isCompleted = getBool(forKey: "sensingFlowCompleted")
        return (currentStep, completedSteps, isCompleted)
    }

    public func resetSensingFlowState() {
        removeObject(forKey: "sensingFlowCurrentStep")
        removeObject(forKey: "sensingFlowCompletedSteps")
        removeObject(forKey: "sensingFlowCompleted")
    }

    public func setHasExecutedSensingSession(_ executed: Bool) {
        setBool(executed, forKey: "hasExecutedSensingSession")
    }

    public func getHasExecutedSensingSession() -> Bool {
        getBool(forKey: "hasExecutedSensingSession")
    }

    // MARK: - デバイス管理関連

    public func savePairedDevices(_ devices: [String]) {
        do {
            try setData(devices, forKey: "pairedDevices")
        } catch {
            print("❌ ペアリングデバイス情報の保存に失敗: \(error)")
        }
    }

    public func loadPairedDevices() -> [String]? {
        getData([String].self, forKey: "pairedDevices")
    }

    public func removePairedDevices() {
        removeObject(forKey: "pairedDevices")
    }

    public func saveConnectionStatistics(_ statistics: [String: Any]) {
        userDefaults.set(statistics, forKey: "ConnectionStatistics")
    }

    public func loadConnectionStatistics() -> [String: Any]? {
        userDefaults.dictionary(forKey: "ConnectionStatistics")
    }

    // MARK: - データ移行関連

    public func setMigrationCompleted(for key: String, completed: Bool) {
        setBool(completed, forKey: key)
    }

    public func isMigrationCompleted(for key: String) -> Bool {
        getBool(forKey: key)
    }

    // MARK: - 汎用設定メソッド

    public func setBool(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getBool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    public func setString(_ value: String?, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getString(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func setDouble(_ value: Double, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    public func getDouble(forKey key: String) -> Double {
        userDefaults.double(forKey: key)
    }

    public func setData(_ value: some Codable, forKey key: String) throws {
        let encoded = try JSONEncoder().encode(value)
        userDefaults.set(encoded, forKey: key)
    }

    public func getData<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}
