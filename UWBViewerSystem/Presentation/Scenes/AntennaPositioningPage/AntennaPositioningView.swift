import SwiftUI

struct AntennaPositioningView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = AntennaPositioningViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // デバッグ用表示
            Text("🔍 AntennaPositioningView が表示されています")
                .font(.caption)
                .foregroundColor(.red)
                .padding()
            
            HeaderSection()
            
            HStack(spacing: 20) {
                MapCanvasSection(viewModel: viewModel)
                
                AntennaDeviceListSection(viewModel: viewModel)
            }
            
            InstructionsSection()
            
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
        HStack(spacing: 20) {
                Button("戻る") {
                    print("🔙 戻るボタンが押されました")
                    router.pop()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.primary)
                
                Spacer()
                
                Button("自動配置") {
                    print("🎯 自動配置ボタンが押されました")
                    print("🎯 自動配置前 - canProceedValue: \(viewModel.canProceedValue)")
                    viewModel.autoArrangeAntennas()
                    print("🎯 自動配置後 - canProceedValue: \(viewModel.canProceedValue)")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.primary)
                
                Button("リセット") {
                    print("🔄 リセットボタンが押されました")
                    viewModel.resetPositions()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.primary)
                
                Button("次へ") {
                    print("➡️ 次へボタンが押されました - canProceed: \(viewModel.canProceedValue)")
                    print("➡️ router情報: \(type(of: router))")
                    print("➡️ アンテナ位置保存開始")
                    viewModel.saveAntennaPositions()
                    print("➡️ アンテナ位置保存完了")
                    print("➡️ キャリブレーション画面に移動開始")
                    router.push(.calibration)
                    print("➡️ push(.calibration)実行完了")
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.white)
                .disabled(!viewModel.canProceedValue)
        }
        .padding()
    }
}

// MARK: - Map Canvas Section
struct MapCanvasSection: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("フロアマップ")
                .font(.headline)
            
            ZStack {
                // マップ背景
                if let mapImage = viewModel.mapImage {
                    #if os(macOS)
                    Image(nsImage: mapImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color(NSColor.controlColor))
                        .cornerRadius(8)
                    #elseif os(iOS)
                    Image(uiImage: mapImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        #if os(macOS)
                        .fill(Color(NSColor.controlColor))
                        #elseif os(iOS)
                        .fill(Color(UIColor.systemGray5))
                        #endif
                        .overlay(
                            VStack {
                                Image(systemName: "map")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("マップが読み込まれていません")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                
                // アンテナ位置 (一時的にコメントアウト)
                // ForEach(viewModel.antennaPositions) { antenna in
                //     PositionAntennaMarker(
                //         antenna: antenna,
                //         onPositionChanged: { newPosition in
                //             viewModel.updateAntennaPosition(antenna.id, position: newPosition)
                //         }
                //     )
                // }
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Antenna Device List Section
struct AntennaDeviceListSection: View {
    @ObservedObject var viewModel: AntennaPositioningViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("アンテナデバイス")
                .font(.headline)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.selectedDevices) { device in
                        AntennaDeviceRow(
                            device: device,
                            position: nil,
                            isPositioned: false
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300)
    }
}

// MARK: - Instructions Section
struct InstructionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置のヒント")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.blue)
                    Text("デバイスをマップ上の実際の位置にドラッグしてください")
                        .font(.subheadline)
                }
                
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.blue)
                    Text("最低3台以上のアンテナを配置してください")
                        .font(.subheadline)
                }
                
                HStack {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.blue)
                    Text("三角形以上の形状になるように配置すると精度が向上します")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.systemBlue).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Position Antenna Marker
struct PositionAntennaMarker: View {
    let antenna: AntennaPosition
    let onPositionChanged: (CGPoint) -> Void
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(antenna.color)
                        .frame(width: 40, height: 40)
                )
                .shadow(radius: 2)
            
            Text(antenna.deviceName)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        #if os(macOS)
                        .fill(Color(NSColor.controlBackgroundColor))
                        #elseif os(iOS)
                        .fill(Color(UIColor.systemBackground))
                        #endif
                        .shadow(radius: 1)
                )
        }
        .position(x: antenna.position.x + dragOffset.width, 
                  y: antenna.position.y + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let newPosition = CGPoint(
                        x: antenna.position.x + value.translation.width,
                        y: antenna.position.y + value.translation.height
                    )
                    onPositionChanged(newPosition)
                    dragOffset = .zero
                }
        )
    }
}

// MARK: - Antenna Device Row
struct AntennaDeviceRow: View {
    let device: UWBDevice
    let position: CGPoint?
    let isPositioned: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(device.identifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let position = position {
                    Text("位置: (\(Int(position.x)), \(Int(position.y)))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            VStack {
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
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPositioned ? Color(.systemGreen).opacity(0.1) : Color(.systemOrange).opacity(0.1))
        )
    }
}

#Preview {
    NavigationStack {
        AntennaPositioningView()
            .environmentObject(NavigationRouterModel.shared)
    }
}