import SwiftData
import SwiftUI

/// アンテナ位置設定画面
///
/// フロアマップ上でアンテナデバイスの位置と向きを設定するための画面です。
/// - フローティングパネルでデバイスの追加・削除・管理
/// - ドラッグ&ドロップでアンテナの配置
/// - ダブルタップでアンテナの回転
/// - キャリブレーション結果の可視化
struct AntennaPositioningView: View {
    /// 選択されたフロアマップID
    let floorMapId: String

    /// ナビゲーションルーター
    @EnvironmentObject var router: NavigationRouterModel

    /// アンテナ位置設定のViewModel
    @StateObject private var viewModel = AntennaPositioningViewModel()

    /// センシングフローのナビゲーター
    @StateObject private var flowNavigator = SensingFlowNavigator()

    /// SwiftDataのモデルコンテキスト
    @Environment(\.modelContext) private var modelContext

    /// デバイスリストパネルの展開状態
    @State private var isDeviceListExpanded = true

    /// コントロールパネルの展開状態
    @State private var isControlPanelExpanded = true

    /// デバイス追加アラートの表示状態
    @State private var showingAddDeviceAlert = false

    /// 新しいデバイスの名前
    @State private var newDeviceName = ""

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: self.flowNavigator)

            // フルスクリーンマップ with フローティングコントロール
            ZStack {
                // 背景: フルスクリーンマップ
                MapCanvasSection(viewModel: self.viewModel)

                // 左側: デバイスリストパネル
                VStack {
                    HStack {
                        FloatingDeviceListPanel(
                            viewModel: self.viewModel,
                            isExpanded: self.$isDeviceListExpanded,
                            showingAddDeviceAlert: self.$showingAddDeviceAlert
                        )
                        .frame(maxWidth: 380)

                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)

                // 右下: コントロールパネル
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingControlPanel(
                            viewModel: self.viewModel,
                            flowNavigator: self.flowNavigator,
                            isExpanded: self.$isControlPanelExpanded,
                            floorMapId: self.floorMapId
                        )
                        .frame(maxWidth: 450)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("アンテナ位置設定")
        .navigationBarTitleDisplayModeIfAvailable(.large)
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
            .background(Color(UIColor.systemBackground))
        #endif
            .onAppear {
                self.viewModel.setModelContext(self.modelContext)
                self.viewModel.setFloorMapId(self.floorMapId)
                self.viewModel.loadMapAndDevices(floorMapId: self.floorMapId)
                self.flowNavigator.currentStep = .antennaConfiguration
                self.flowNavigator.currentFloorMapId = self.floorMapId
                self.flowNavigator.setRouter(self.router)
            }
            .alert("エラー", isPresented: Binding.constant(self.flowNavigator.lastError != nil)) {
                Button("OK") {
                    self.flowNavigator.lastError = nil
                }
            } message: {
                Text(self.flowNavigator.lastError ?? "")
            }
            .alert("新しいデバイスを追加", isPresented: self.$showingAddDeviceAlert) {
                TextField("デバイス名", text: self.$newDeviceName)

                Button("追加") {
                    if !self.newDeviceName.isEmpty {
                        print("🔘 Alert: Adding device with name: \(self.newDeviceName)")
                        self.viewModel.addNewDevice(name: self.newDeviceName)
                        self.newDeviceName = ""  // リセット
                    } else {
                        print("❌ Alert: Device name is empty")
                    }
                }
                .disabled(self.newDeviceName.isEmpty)

                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("アンテナデバイスの名前を入力してください。")
            }
            .sheet(isPresented: self.$viewModel.showCalibrationResult) {
                if let resultData = self.viewModel.calibrationResultData,
                   let floorMapInfo = self.viewModel.currentFloorMapInfo
                {
                    NavigationStack {
                        CalibrationResultVisualizationView(
                            tagPositions: resultData.tagPositions,
                            initialAntennaPositions: resultData.initialAntennaPositions,
                            calibratedAntennaPositions: resultData.calibratedAntennaPositions,
                            floorMapInfo: floorMapInfo,
                            showInitialPositions: true
                        )
                        .navigationTitle("キャリブレーション結果")
                        .navigationBarTitleDisplayModeIfAvailable(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") {
                                    self.viewModel.showCalibrationResult = false
                                }
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - Map Canvas Section

/// マップキャンバスセクション
///
/// フロアマップ上にアンテナマーカーを配置し、ドラッグ&ドロップと回転機能を提供します。
/// - アンテナの位置をドラッグで変更可能
/// - アンテナの向きをダブルタップで回転可能
/// - センサー範囲を常に表示
struct MapCanvasSection: View {
    /// アンテナ位置設定のViewModel
    @ObservedObject var viewModel: AntennaPositioningViewModel

    var body: some View {
        if let floorMapImage = self.viewModel.mapImage,
           let floorMapInfo = self.viewModel.currentFloorMapInfo
        {
            FloorMapCanvas(
                floorMapImage: floorMapImage,
                floorMapInfo: floorMapInfo,
                calibrationPoints: self.viewModel.calibrationData.first?.calibrationPoints,
                onMapTap: nil,
                enableZoom: true,
                fixedHeight: nil,
                showGrid: true
            ) { geometry in
                // アンテナ位置
                ForEach(self.viewModel.antennaPositions) { antenna in
                    let antennaDisplayData = AntennaDisplayData(
                        id: antenna.id,
                        name: antenna.deviceName,
                        rotation: antenna.rotation,
                        color: antenna.color
                    )

                    let displayPosition = geometry.normalizedToImageCoordinate(antenna.normalizedPosition)

                    AntennaMarker(
                        antenna: antennaDisplayData,
                        position: displayPosition,
                        size: geometry.antennaSizeInPixels(),
                        sensorRange: geometry.sensorRangeInPixels(),
                        isSelected: true,  // 常にセンサー範囲を表示
                        isDraggable: true,
                        showRotationControls: false,
                        onPositionChanged: { newPosition in
                            let normalizedPosition = geometry.imageCoordinateToNormalized(newPosition)
                            self.viewModel.updateAntennaPosition(antenna.id, normalizedPosition: normalizedPosition)
                        },
                        onRotationChanged: { newRotation in
                            self.viewModel.updateAntennaRotation(antenna.id, rotation: newRotation)
                        }
                    )
                }
            }
        } else {
            ZStack {
                Color.secondary.opacity(0.1)

                VStack(spacing: 12) {
                    ProgressView()
                    Text("フロアマップを読み込んでいます...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Antenna Device List Section

/// アンテナデバイスリストセクション
///
/// アンテナデバイスの一覧を表示し、追加・削除機能を提供します。
/// - デバイスの追加ボタン
/// - デバイス情報（名前、ID、位置、向き）の表示
/// - デバイスの削除機能
struct AntennaDeviceListSection: View {
    /// アンテナ位置設定のViewModel
    @ObservedObject var viewModel: AntennaPositioningViewModel

    /// デバイス追加アラートの表示状態
    @State private var showingAddDeviceAlert = false

    /// 新しいデバイスの名前
    @State private var newDeviceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("アンテナデバイス")
                    .font(.headline)

                Spacer()

                Button(action: {
                    print("🔘 Plus button clicked - showing add device alert")
                    self.newDeviceName = ""
                    self.showingAddDeviceAlert = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(self.viewModel.selectedDevices) { device in
                        AntennaDeviceRowWithActions(
                            device: AntennaInfo(id: device.id, name: device.name, coordinates: Point3D.zero),
                            position: self.viewModel.getDevicePosition(device.id),
                            rotation: self.viewModel.getDeviceRotation(device.id),
                            isPositioned: self.viewModel.isDevicePositioned(device.id),
                            onRemove: {
                                self.viewModel.removeDevice(device.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - Enhanced Antenna Device Row with Rotation Info

/// アンテナデバイス行（向き情報付き）
///
/// アンテナデバイスの情報を1行で表示するコンポーネント。
/// - デバイス名とID
/// - 位置情報（メートル単位）
/// - 向き情報（度単位、矢印アイコン付き）
/// - 配置ステータス（未配置/配置済/完了）
/// - 削除ボタン
struct AntennaDeviceRow: View {
    /// デバイス情報
    let device: DeviceInfo

    /// デバイスの位置（メートル単位）
    let position: CGPoint?

    /// デバイスが配置されているかどうか
    let isPositioned: Bool

    /// デバイスの向き（度単位）
    let rotation: Double?

    /// 削除時のコールバック
    let onRemove: () -> Void

    var body: some View {
        HStack {
            // デバイス情報
            VStack(alignment: .leading, spacing: 4) {
                Text(self.device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(self.device.id)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let position {
                    Text("位置: (X: \(String(format: "%.2f", position.x))m, Y: \(String(format: "%.2f", position.y))m)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if let rotation {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(rotation))

                        Text("向き: \(String(format: "%.1f", rotation))°")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // ステータス表示
            VStack(spacing: 4) {
                if self.isPositioned && self.rotation != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("完了")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                } else if self.isPositioned {
                    HStack(spacing: 4) {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.orange)
                        Text("配置済")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.red)
                        Text("未配置")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }

            // 削除ボタン
            Button(action: self.onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(self.backgroundColorForStatus)
        )
    }

    /// ステータスに応じた背景色を取得
    ///
    /// - Returns: 配置状態に応じた背景色
    ///   - 完了（配置済み + 向き設定済み）: 緑色
    ///   - 配置済み（向き未設定）: オレンジ色
    ///   - 未配置: 赤色
    private var backgroundColorForStatus: Color {
        if self.isPositioned && self.rotation != nil {
            return Color(.systemGreen).opacity(0.15)
        } else if self.isPositioned {
            return Color(.systemOrange).opacity(0.1)
        } else {
            return Color(.systemRed).opacity(0.1)
        }
    }
}

// MARK: - Antenna Device Row with Actions (Add/Remove)

/// アンテナデバイス行（アクション付き）
///
/// アンテナデバイスの情報を1行で表示し、削除機能を提供するコンポーネント。
/// - デバイス名とID
/// - 位置情報（メートル単位）
/// - 向き情報（度単位、矢印アイコン付き）
/// - 配置ステータス（未配置/配置済み）
/// - 削除確認アラート付きの削除ボタン
struct AntennaDeviceRowWithActions: View {
    /// アンテナ情報
    let device: AntennaInfo

    /// デバイスの位置（メートル単位）
    let position: CGPoint?

    /// デバイスの向き（度単位）
    let rotation: Double?

    /// デバイスが配置されているかどうか
    let isPositioned: Bool

    /// 削除時のコールバック
    let onRemove: () -> Void

    /// 削除確認アラートの表示状態
    @State private var showingRemoveAlert = false

    var body: some View {
        HStack {
            // デバイス情報
            VStack(alignment: .leading, spacing: 4) {
                Text(self.device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(self.device.id)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // デバッグ: positionの状態を表示
                if let position {
                    Text("位置: (X: \(String(format: "%.2f", position.x))m, Y: \(String(format: "%.2f", position.y))m)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else if self.isPositioned {
                    Text("位置: 取得中...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if let rotation {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(rotation))

                        Text("向き: \(String(format: "%.1f", rotation))°")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // ステータス表示と削除ボタン
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    if self.isPositioned {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }

                    Text(self.isPositioned ? "配置済み" : "未配置")
                        .font(.caption2)
                        .foregroundColor(self.isPositioned ? .green : .orange)

                    // 向き設定状況
                    if self.rotation != nil {
                        Text("向き設定済み")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else if self.isPositioned {
                        Text("向き未設定")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Button(action: {
                    self.showingRemoveAlert = true
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(self.backgroundColorForStatus)
        )
        .alert("デバイスを削除", isPresented: self.$showingRemoveAlert) {
            Button("削除", role: .destructive) {
                self.onRemove()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("デバイス「\(self.device.name)」を削除しますか？この操作は取り消せません。")
        }
    }

    /// ステータスに応じた背景色を取得
    ///
    /// - Returns: 配置状態に応じた背景色
    ///   - 完了（配置済み + 向き設定済み）: 緑色
    ///   - 配置済み（向き未設定）: オレンジ色
    ///   - 未配置: 赤色
    private var backgroundColorForStatus: Color {
        if self.isPositioned && self.rotation != nil {
            return Color(.systemGreen).opacity(0.15)
        } else if self.isPositioned {
            return Color(.systemOrange).opacity(0.1)
        } else {
            return Color(.systemRed).opacity(0.1)
        }
    }
}

// MARK: - Floating Device List Panel

/// フローティングデバイスリストパネル
///
/// 画面左側に配置されるフローティングパネルで、アンテナデバイスの一覧と管理機能を提供します。
/// - 展開/折りたたみ可能
/// - デバイスの一覧表示（位置、向き、ステータス）
/// - デバイスの追加ボタン
/// - デバイスの削除機能
struct FloatingDeviceListPanel: View {
    /// アンテナ位置設定のViewModel
    @ObservedObject var viewModel: AntennaPositioningViewModel

    /// パネルの展開状態
    @Binding var isExpanded: Bool

    /// デバイス追加アラートの表示状態
    @Binding var showingAddDeviceAlert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.headerView

            if self.isExpanded {
                Divider()
                self.deviceListView
            }
        }
        .padding(16)
        .background(self.backgroundView)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    /// パネルのヘッダー部分
    ///
    /// デバイスアイコン、タイトル、展開/折りたたみボタンを含みます。
    private var headerView: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.blue)
            Text("デバイス")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    self.isExpanded.toggle()
                }
            }) {
                Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
        }
    }

    /// デバイス一覧表示部分
    ///
    /// アンテナデバイスのリストをスクロール可能な形式で表示します。
    private var deviceListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(self.viewModel.antennaPositions) { antenna in
                    AntennaDeviceRow(
                        device: DeviceInfo(
                            id: antenna.id,
                            name: antenna.deviceName
                        ),
                        position: self.viewModel.getDevicePosition(antenna.id),
                        isPositioned: antenna.normalizedPosition != .zero,
                        rotation: antenna.rotation,
                        onRemove: {
                            self.viewModel.removeDevice(antenna.id)
                        }
                    )
                }

                self.addDeviceButton
            }
        }
        .frame(maxHeight: 400)
    }

    /// デバイス追加ボタン
    ///
    /// 新しいアンテナデバイスを追加するためのボタンです。
    private var addDeviceButton: some View {
        Button(action: {
            self.showingAddDeviceAlert = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("デバイスを追加")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    /// パネルの背景ビュー
    ///
    /// プラットフォームに応じた背景色を提供します。
    private var backgroundView: some View {
        Group {
            #if os(macOS)
                Color(NSColor.controlBackgroundColor).opacity(0.95)
            #elseif os(iOS)
                Color(UIColor.systemBackground).opacity(0.95)
            #endif
        }
    }
}

// MARK: - Floating Control Panel

/// フローティングコントロールパネル
///
/// 画面右下に配置されるフローティングパネルで、操作ガイドと各種制御機能を提供します。
/// - 操作説明（ピンチ、ドラッグ、タップなど）
/// - 自動配置ボタン
/// - リセットボタン
/// - キャリブレーション結果表示ボタン
/// - 前のステップ/次のステップへの遷移ボタン
/// - Walk-throughキャリブレーションへの遷移ボタン
struct FloatingControlPanel: View {
    /// アンテナ位置設定のViewModel
    @ObservedObject var viewModel: AntennaPositioningViewModel

    /// センシングフローのナビゲーター
    @ObservedObject var flowNavigator: SensingFlowNavigator

    /// パネルの展開状態
    @Binding var isExpanded: Bool

    /// フロアマップID
    let floorMapId: String

    /// ナビゲーションルーター
    @EnvironmentObject var router: NavigationRouterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.headerView

            if self.isExpanded {
                Divider()
                self.instructionsView
                Divider()
                self.controlButtonsView
            }
        }
        .padding(16)
        .background(self.backgroundView)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    /// パネルのヘッダー部分
    ///
    /// コントロールアイコン、タイトル、展開/折りたたみボタンを含みます。
    private var headerView: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.blue)
            Text("コントロール")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    self.isExpanded.toggle()
                }
            }) {
                Image(systemName: self.isExpanded ? "chevron.down" : "chevron.up")
                    .foregroundColor(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
        }
    }

    /// 操作説明部分
    ///
    /// マップとアンテナの操作方法を表示します。
    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(.blue)
                Text("マップをピンチで拡大/縮小")
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .foregroundColor(.blue)
                Text("マップをドラッグで移動")
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Image(systemName: "move.3d")
                    .foregroundColor(.blue)
                Text("アンテナをドラッグして配置")
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Image(systemName: "rotate.right.fill")
                    .foregroundColor(.blue)
                Text("アンテナをダブルタップで回転")
                    .font(.caption)
            }
        }
        .foregroundColor(.secondary)
    }

    /// コントロールボタン部分
    ///
    /// 各種制御ボタン（自動配置、リセット、キャリブレーション結果、戻る、次へ）を表示します。
    private var controlButtonsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("戻る") {
                    self.flowNavigator.goToPreviousStep()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1))
                .foregroundColor(.secondary)
                .cornerRadius(8)
                .buttonStyle(.plain)

                Button("次へ") {
                    let saveSuccess = self.viewModel.saveAntennaPositionsForFlow()
                    if saveSuccess {
                        self.flowNavigator.proceedToNextStep(floorMapId: self.floorMapId)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(self.viewModel.canProceedValue ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
                .buttonStyle(.plain)
                .disabled(!self.viewModel.canProceedValue)
            }
        }
    }

    /// パネルの背景ビュー
    ///
    /// プラットフォームに応じた背景色を提供します。
    private var backgroundView: some View {
        Group {
            #if os(macOS)
                Color(NSColor.controlBackgroundColor).opacity(0.95)
            #elseif os(iOS)
                Color(UIColor.systemBackground).opacity(0.95)
            #endif
        }
    }
}

#Preview {
    NavigationStack {
        AntennaPositioningView(floorMapId: "test-floor-map-id")
            .environmentObject(NavigationRouterModel.shared)
    }
}
