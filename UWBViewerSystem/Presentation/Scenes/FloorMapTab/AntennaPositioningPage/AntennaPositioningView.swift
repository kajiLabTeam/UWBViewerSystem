import SwiftData
import SwiftUI

struct AntennaPositioningView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = AntennaPositioningViewModel()
    @StateObject private var flowNavigator = SensingFlowNavigator()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // フロープログレス表示
            SensingFlowProgressView(navigator: flowNavigator)

            ScrollView {
                VStack(spacing: 20) {
                    HeaderSection()

                    HStack(spacing: 20) {
                        MapCanvasSection(viewModel: viewModel)

                        AntennaDeviceListSection(viewModel: viewModel)
                    }

                    InstructionsSection()

                    Spacer(minLength: 80)
                }
                .padding()
            }

            NavigationButtonsSection(viewModel: viewModel)
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
            viewModel.setModelContext(modelContext)
            viewModel.loadMapAndDevices()
            flowNavigator.currentStep = .antennaConfiguration
            flowNavigator.setRouter(router)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("FloorMapChanged"))) { notification in
            // フロアマップが変更された時にデータを再読み込み
            print("📢 AntennaPositioningView: FloorMapChanged通知を受信")
            if let floorMapInfo = notification.object as? FloorMapInfo {
                print("📢 新しいフロアマップ: \(floorMapInfo.name) (ID: \(floorMapInfo.id))")
            }
            viewModel.loadMapAndDevices()
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アンテナ位置をマップ上に配置してください")
                .font(.title2)
                .fontWeight(.medium)

            Text("選択したデバイスをマップ上の実際の位置にドラッグ&ドロップで配置してください。正確な位置設定により、より精密な位置測定が可能になります。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Navigation Buttons

    @ViewBuilder
    private func NavigationButtonsSection(viewModel: AntennaPositioningViewModel) -> some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 20) {
                Button("戻る") {
                    flowNavigator.goToPreviousStep()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.secondary)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Button("自動配置") {
                    viewModel.autoArrangeAntennas()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                Button("リセット") {
                    viewModel.resetPositions()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.orange)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)

                Button("全削除") {
                    viewModel.removeAllDevices()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.red)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)

                Button("次へ") {
                    print("🔘 Next button clicked")
                    let saveSuccess = viewModel.saveAntennaPositionsForFlow()
                    print("🔘 Save result: \(saveSuccess)")

                    if saveSuccess {
                        print("🔘 Calling flowNavigator.proceedToNextStep()")
                        flowNavigator.proceedToNextStep()
                    } else {
                        print("❌ Cannot proceed: antenna positions not saved")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(viewModel.canProceedValue ? Color.blue : Color.gray)
                .cornerRadius(8)
                .disabled(!viewModel.canProceedValue)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .alert("エラー", isPresented: Binding.constant(flowNavigator.lastError != nil)) {
            Button("OK") {
                flowNavigator.lastError = nil
            }
        } message: {
            Text(flowNavigator.lastError ?? "")
        }
    }
}

// MARK: - Map Canvas Section

struct MapCanvasSection: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("フロアマップ")
                .font(.headline)

            FloorMapCanvas(
                floorMapImage: viewModel.mapImage,
                floorMapInfo: viewModel.currentFloorMapInfo,
                onMapTap: nil
            ) { geometry in
                // アンテナ位置
                ForEach(viewModel.antennaPositions) { antenna in
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
                        isSelected: true, // 常にセンサー範囲を表示
                        isDraggable: true,
                        showRotationControls: false,
                        onPositionChanged: { newPosition in
                            let normalizedPosition = geometry.imageCoordinateToNormalized(newPosition)
                            viewModel.updateAntennaPosition(antenna.id, normalizedPosition: normalizedPosition)
                        },
                        onRotationChanged: { newRotation in
                            viewModel.updateAntennaRotation(antenna.id, rotation: newRotation)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
            .background(Color(UIColor.systemBackground))
        #endif
            .cornerRadius(8)
            .shadow(radius: 2)
    }
}

// MARK: - Antenna Device List Section

struct AntennaDeviceListSection: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel
    @State private var showingAddDeviceAlert = false
    @State private var newDeviceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("アンテナデバイス")
                    .font(.headline)

                Spacer()

                Button(action: {
                    print("🔘 Plus button clicked - showing add device alert")
                    newDeviceName = ""
                    showingAddDeviceAlert = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.selectedDevices) { device in
                        AntennaDeviceRowWithActions(
                            device: AntennaInfo(id: device.id, name: device.name, coordinates: Point3D.zero),
                            position: viewModel.getDevicePosition(device.id),
                            rotation: viewModel.getDeviceRotation(device.id),
                            isPositioned: viewModel.isDevicePositioned(device.id),
                            onRemove: {
                                viewModel.removeDevice(device.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300)
        .alert("新しいデバイスを追加", isPresented: $showingAddDeviceAlert) {
            TextField("デバイス名", text: $newDeviceName)

            Button("追加") {
                if !newDeviceName.isEmpty {
                    print("🔘 Alert: Adding device with name: \(newDeviceName)")
                    viewModel.addNewDevice(name: newDeviceName)
                    newDeviceName = ""  // リセット
                } else {
                    print("❌ Alert: Device name is empty")
                }
            }
            .disabled(newDeviceName.isEmpty)

            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("アンテナデバイスの名前を入力してください。")
        }
    }
}

// MARK: - Enhanced Instructions Section with Rotation Info

struct InstructionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置・設定のヒント")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("デバイスをマップ上の実際の位置にドラッグしてください")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("アンテナをダブルタップして向き（回転）を調整できます")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("最低3台以上のアンテナを配置してください")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "4.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("三角形以上の形状になるように配置すると精度が向上します")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    Text("アンテナの向きは電波の指向性に影響します。壁や障害物を考慮して設定してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Enhanced Antenna Device Row with Rotation Info

struct AntennaDeviceRow: View {
    let device: AntennaInfo
    let position: CGPoint?
    let rotation: Double?
    let isPositioned: Bool

    var body: some View {
        HStack {
            // デバイス情報
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(device.id)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let position {
                    Text("位置: (\(Int(position.x)), \(Int(position.y)))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if let rotation {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(rotation))

                        Text("向き: \(Int(rotation))°")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // ステータス表示
            VStack(spacing: 4) {
                if isPositioned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                        .font(.title3)
                }

                Text(isPositioned ? "配置済み" : "未配置")
                    .font(.caption2)
                    .foregroundColor(isPositioned ? .green : .orange)

                // 向き設定状況
                if rotation != nil {
                    Text("向き設定済み")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else if isPositioned {
                    Text("向き未設定")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColorForStatus)
        )
    }

    private var backgroundColorForStatus: Color {
        if isPositioned && rotation != nil {
            return Color(.systemGreen).opacity(0.15)
        } else if isPositioned {
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
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(device.id)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let position {
                    Text("位置: (\(Int(position.x)), \(Int(position.y)))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if let rotation {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(rotation))

                        Text("向き: \(Int(rotation))°")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // ステータス表示と削除ボタン
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    if isPositioned {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }

                    Text(isPositioned ? "配置済み" : "未配置")
                        .font(.caption2)
                        .foregroundColor(isPositioned ? .green : .orange)

                    // 向き設定状況
                    if rotation != nil {
                        Text("向き設定済み")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    } else if isPositioned {
                        Text("向き未設定")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Button(action: {
                    showingRemoveAlert = true
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
                .fill(backgroundColorForStatus)
        )
        .alert("デバイスを削除", isPresented: $showingRemoveAlert) {
            Button("削除", role: .destructive) {
                onRemove()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("デバイス「\(device.name)」を削除しますか？この操作は取り消せません。")
        }
    }

    private var backgroundColorForStatus: Color {
        if isPositioned && rotation != nil {
            return Color(.systemGreen).opacity(0.15)
        } else if isPositioned {
            return Color(.systemOrange).opacity(0.1)
        } else {
            return Color(.systemRed).opacity(0.1)
        }
    }
}

#Preview {
    NavigationStack {
        AntennaPositioningView()
            .environmentObject(NavigationRouterModel.shared)
    }
}
