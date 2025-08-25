import SwiftUI

struct DeviceSelectionView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = DeviceSelectionViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderSection()
            
            DeviceListSection(viewModel: viewModel)
            
            SelectedDevicesSection(viewModel: viewModel)
            
            NavigationButtonsSection(viewModel: viewModel)
        }
        .navigationTitle("デバイス選択")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("接続するデバイスを選択してください")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("UWBアンテナとして使用するデバイスを選択してください。最低3台以上の選択が推奨されます。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Navigation Buttons
    @ViewBuilder
    private func NavigationButtonsSection(viewModel: DeviceSelectionViewModel) -> some View {
        HStack(spacing: 20) {
            Button("戻る") {
                router.pop()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("次へ") {
                viewModel.saveSelectedDevices()
                router.push(.antennaPositioning)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceed)
        }
        .padding()
    }
}

// MARK: - Device List Section
struct DeviceListSection: View {
    @ObservedObject var viewModel: DeviceSelectionViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("利用可能なデバイス")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("検索中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(viewModel.isScanning ? "停止" : "再検索") {
                    if viewModel.isScanning {
                        viewModel.stopScanning()
                    } else {
                        viewModel.startScanning()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if viewModel.availableDevices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("デバイスが見つかりません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("デバイスの電源が入っていることを確認してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                #if os(macOS)
                .background(Color(NSColor.controlColor))
                #elseif os(iOS)
                .background(Color(UIColor.systemGray6))
                #endif
                .cornerRadius(8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.availableDevices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: viewModel.selectedDevices.contains(device.id),
                            onToggle: {
                                viewModel.toggleDeviceSelection(device.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Selected Devices Section
struct SelectedDevicesSection: View {
    @ObservedObject var viewModel: DeviceSelectionViewModel
    
    var body: some View {
        if !viewModel.selectedDevices.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("選択済みデバイス")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(viewModel.selectedDevices.count) 台選択")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemBlue).opacity(0.1))
                        .cornerRadius(4)
                }
                
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.getSelectedDevices()) { device in
                        SelectedDeviceRow(
                            device: device,
                            onRemove: {
                                viewModel.toggleDeviceSelection(device.id)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let device: UWBDevice
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(device.identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Label("RSSI: \(device.rssi)", systemImage: "wifi")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        ConnectionStatusBadge(status: device.connectionStatus)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color(.systemBlue).opacity(0.1) : {
                          #if os(macOS)
                          return Color(NSColor.controlColor)
                          #elseif os(iOS)
                          return Color(UIColor.systemGray6)
                          #endif
                      }())
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selected Device Row
struct SelectedDeviceRow: View {
    let device: UWBDevice
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(device.identifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBlue).opacity(0.1))
        )
    }
}

// MARK: - Connection Status Badge
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(4)
    }
}

#Preview {
    NavigationStack {
        DeviceSelectionView()
            .environmentObject(NavigationRouterModel.shared)
    }
}