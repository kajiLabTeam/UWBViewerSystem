import SwiftUI

/// データ表示専用画面
/// リアルタイムデータ表示とファイル管理に特化し、参考デザイン「Stitch Design-5.png」に対応
struct DataDisplayView: View {
    @StateObject private var viewModel = DataDisplayViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var selectedDisplayMode: DisplayMode = .realtime
    @State private var selectedDevice: String?
    
    enum DisplayMode: String, CaseIterable {
        case realtime = "リアルタイム"
        case history = "履歴データ"
        case files = "ファイル管理"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            displayModeSelector
            
            contentArea
            
            Spacer()
        }
        .padding()
        .navigationTitle("データ表示")
        .onAppear {
            viewModel.startRealtimeUpdates()
        }
        .onDisappear {
            viewModel.stopRealtimeUpdates()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("UWBデータ表示・分析")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("リアルタイムUWBデータの表示、履歴データの分析、ファイル管理を行います")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Display Mode Selector
    private var displayModeSelector: some View {
        Picker("表示モード", selection: $selectedDisplayMode) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    // MARK: - Content Area
    @ViewBuilder
    private var contentArea: some View {
        switch selectedDisplayMode {
        case .realtime:
            realtimeDataView
        case .history:
            historyDataView
        case .files:
            fileManagementView
        }
    }
    
    // MARK: - Realtime Data View
    private var realtimeDataView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("リアルタイムデータ")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if viewModel.isConnected {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("接続中")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("未接続")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if viewModel.realtimeData.isEmpty {
                EmptyDataView(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "データなし",
                    subtitle: "UWBセンサーからのデータが受信されていません"
                )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(viewModel.realtimeData, id: \.deviceName) { data in
                        DeviceRealtimeDataCard(
                            data: data,
                            isSelected: selectedDevice == data.deviceName
                        ) {
                            selectedDevice = selectedDevice == data.deviceName ? nil : data.deviceName
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - History Data View
    private var historyDataView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("履歴データ")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: viewModel.refreshHistoryData) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            
            if viewModel.historyData.isEmpty {
                EmptyDataView(
                    icon: "clock",
                    title: "履歴なし",
                    subtitle: "まだ保存されたデータがありません"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.historyData, id: \.id) { session in
                            HistorySessionCard(session: session) {
                                viewModel.loadSessionData(session)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - File Management View
    private var fileManagementView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("ファイル管理")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: viewModel.openStorageFolder) {
                    HStack {
                        Image(systemName: "folder")
                        Text("フォルダを開く")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }
            
            if viewModel.receivedFiles.isEmpty {
                EmptyDataView(
                    icon: "doc",
                    title: "ファイルなし",
                    subtitle: "まだ受信されたファイルがありません"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.receivedFiles, id: \.name) { file in
                            FileItemCard(file: file) {
                                viewModel.openFile(file)
                            }
                        }
                    }
                }
            }
            
            // ファイル転送進捗
            if !viewModel.fileTransferProgress.isEmpty {
                VStack(spacing: 8) {
                    Text("ファイル転送中")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(Array(viewModel.fileTransferProgress.keys), id: \.self) { endpointId in
                        if let progress = viewModel.fileTransferProgress[endpointId] {
                            FileTransferProgressView(
                                endpointId: endpointId,
                                progress: progress
                            )
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Realtime Data Card
struct DeviceRealtimeDataCard: View {
    let data: DeviceRealtimeData
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.blue)
                Text(data.deviceName)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if let latestData = data.latestData {
                VStack(spacing: 8) {
                    DataRow(label: "距離", value: String(format: "%.2f m", latestData.distance))
                    DataRow(label: "仰角", value: String(format: "%.1f°", latestData.elevation))
                    DataRow(label: "方位角", value: String(format: "%.1f°", latestData.azimuth))
                    DataRow(label: "RSSI", value: String(format: "%.0f dBm", latestData.rssi))
                }
                
                HStack {
                    Text("NLOS: \(latestData.nlos != 0 ? "Yes" : "No")")
                        .font(.caption)
                    .foregroundColor(latestData.nlos != 0 ? .orange : .green)
                
                Spacer()
                
                Text("Seq: \(latestData.seqCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Text(DateFormatter.timeOnly.string(from: Date(timeIntervalSince1970: latestData.timestamp)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("データなし")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Data Row
struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - History Session Card
struct HistorySessionCard: View {
    let session: SensingSession
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(session.dataPoints) points")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(session.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: onTap) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - File Item Card
struct FileItemCard: View {
    let file: DataDisplayFile
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: file.isCSV ? "doc.text" : "doc")
                .foregroundColor(file.isCSV ? .green : .blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(file.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: onTap) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - File Transfer Progress View
struct FileTransferProgressView: View {
    let endpointId: String
    let progress: Int
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("端末: \(endpointId)")
                    .font(.caption)
                Spacer()
                Text("\(progress)%")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            ProgressView(value: Double(progress), total: 100)
                .progressViewStyle(LinearProgressViewStyle())
        }
    }
}

// MARK: - Empty Data View
struct EmptyDataView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    DataDisplayView()
        .environmentObject(NavigationRouterModel())
}