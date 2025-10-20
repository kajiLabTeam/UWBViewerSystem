import SwiftData
import SwiftUI

struct AntennaPositioningView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = AntennaPositioningViewModel()
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @Environment(\.modelContext) private var modelContext

    @State private var isDeviceListExpanded = true
    @State private var isControlPanelExpanded = true

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
                            isExpanded: self.$isDeviceListExpanded
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
                            isExpanded: self.$isControlPanelExpanded
                        )
                        .frame(maxWidth: 450)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("アンテナ位置設定")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            self.viewModel.setModelContext(self.modelContext)
            self.flowNavigator.currentStep = .antennaConfiguration
            self.flowNavigator.setRouter(self.router)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("FloorMapChanged"))) { notification in
            // フロアマップが変更された時にデータを再読み込み
            print("📢 AntennaPositioningView: FloorMapChanged通知を受信")
            if let floorMapInfo = notification.object as? FloorMapInfo {
                print("📢 新しいフロアマップ: \(floorMapInfo.name) (ID: \(floorMapInfo.id))")
            }
            self.viewModel.loadMapAndDevices()
        }
        .alert("エラー", isPresented: Binding.constant(self.flowNavigator.lastError != nil)) {
            Button("OK") {
                self.flowNavigator.lastError = nil
            }
        } message: {
            Text(self.flowNavigator.lastError ?? "")
        }
    }
}

// MARK: - Map Canvas Section

struct MapCanvasSection: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel

    var body: some View {
        FloorMapCanvas(
            floorMapImage: self.viewModel.mapImage,
            floorMapInfo: self.viewModel.currentFloorMapInfo,
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
    }
}

// MARK: - Antenna Device List Section

// MARK: - Enhanced Antenna Device Row with Rotation Info

struct AntennaDeviceRow: View {
    let device: DeviceInfo
    let position: CGPoint?
    let isPositioned: Bool
    let rotation: Double?
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

struct AntennaDeviceRowWithActions: View {
    let device: AntennaInfo
    let position: CGPoint?
    let rotation: Double?
    let isPositioned: Bool
    let onRemove: () -> Void

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

struct FloatingDeviceListPanel: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel
    @Binding var isExpanded: Bool

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

    private var addDeviceButton: some View {
        Button(action: {
            self.viewModel.addNewDevice(name: "New Device")
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

struct FloatingControlPanel: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel
    @ObservedObject var flowNavigator: SensingFlowNavigator
    @Binding var isExpanded: Bool

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

    private var controlButtonsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("自動配置") {
                    self.viewModel.autoArrangeAntennas()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
                .buttonStyle(.plain)

                Button("リセット") {
                    self.viewModel.resetPositions()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .foregroundColor(.orange)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }

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
                        self.flowNavigator.proceedToNextStep()
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
        AntennaPositioningView()
            .environmentObject(NavigationRouterModel.shared)
    }
}
