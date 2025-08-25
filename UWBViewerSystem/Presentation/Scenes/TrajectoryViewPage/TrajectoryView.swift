import SwiftUI

struct TrajectoryView: View {
    @EnvironmentObject var router: NavigationRouterModel
    @StateObject private var viewModel = TrajectoryViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderSection()
            
            HStack(spacing: 20) {
                TrajectoryMapSection(viewModel: viewModel)
                
                DataControlSection(viewModel: viewModel)
            }
            
            TrajectoryAnalysisSection(viewModel: viewModel)
            
            NavigationButtonsSection()
        }
        .navigationTitle("センシングデータ軌跡")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #elseif os(iOS)
        .background(Color(UIColor.systemBackground))
        #endif
        .onAppear {
            viewModel.initialize()
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private func HeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("センシングデータの軌跡確認")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("取得したUWBセンシングデータをマップ上で可視化し、移動軌跡や位置精度を分析できます。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Navigation Buttons
    @ViewBuilder
    private func NavigationButtonsSection() -> some View {
        HStack(spacing: 20) {
            Button("戻る") {
                router.pop()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("新しいセンシングを開始") {
                router.navigateTo(.indoorMapRegistration)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Trajectory Map Section
struct TrajectoryMapSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("軌跡マップ")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Button("リセット") {
                        viewModel.resetView()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("エクスポート") {
                        viewModel.exportTrajectoryData()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
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
                
                // アンテナ位置
                ForEach(viewModel.antennaPositions) { antenna in
                    AntennaMarkerView(antenna: antenna)
                }
                
                // 軌跡パス
                if !viewModel.trajectoryPoints.isEmpty {
                    TrajectoryPath(points: viewModel.trajectoryPoints, color: viewModel.trajectoryColor)
                }
                
                // 現在位置
                if let currentPosition = viewModel.currentPosition {
                    CurrentPositionMarker(position: currentPosition)
                }
                
                // 選択されたデータポイント
                if let selectedPoint = viewModel.selectedDataPoint {
                    SelectedPointMarker(point: selectedPoint)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 500)
            #if os(macOS)
            .background(Color(NSColor.controlBackgroundColor))
            #elseif os(iOS)
            .background(Color(UIColor.systemBackground))
            #endif
            .cornerRadius(8)
            .shadow(radius: 2)
            .onTapGesture { location in
                viewModel.handleMapTap(at: location)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Data Control Section
struct DataControlSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SessionSelectionSection(viewModel: viewModel)
            
            PlaybackControlSection(viewModel: viewModel)
            
            FilteringSection(viewModel: viewModel)
        }
        .frame(width: 350)
    }
}

// MARK: - Session Selection Section
struct SessionSelectionSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("セッション選択")
                .font(.headline)
            
            if viewModel.availableSessions.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("利用可能なセッションがありません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                #if os(macOS)
                .background(Color(NSColor.controlColor))
                #elseif os(iOS)
                .background(Color(UIColor.systemGray6))
                #endif
                .cornerRadius(8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.availableSessions) { session in
                            TrajectorySessionRowView(
                                session: session,
                                isSelected: viewModel.selectedSession?.id == session.id,
                                onSelect: {
                                    viewModel.selectSession(session)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

// MARK: - Playback Control Section
struct PlaybackControlSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("再生制御")
                .font(.headline)
            
            VStack(spacing: 10) {
                // 時間スライダー
                if viewModel.hasTrajectoryData {
                    VStack(spacing: 5) {
                        HStack {
                            Text(viewModel.currentTimeString)
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            Text(viewModel.totalTimeString)
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                        
                        Slider(
                            value: $viewModel.currentTimeIndex,
                            in: 0...Double(max(0, viewModel.trajectoryPoints.count - 1)),
                            step: 1
                        )
                        .disabled(!viewModel.hasTrajectoryData)
                    }
                }
                
                // 再生ボタン
                HStack {
                    Button(action: {
                        if viewModel.isPlaying {
                            viewModel.pausePlayback()
                        } else {
                            viewModel.startPlayback()
                        }
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.hasTrajectoryData)
                    
                    Button("停止") {
                        viewModel.stopPlayback()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasTrajectoryData)
                    
                    Spacer()
                    
                    Text("速度: \(String(format: "%.1f", viewModel.playbackSpeed))x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 速度制御
                HStack {
                    Text("0.5x")
                        .font(.caption2)
                    Slider(value: $viewModel.playbackSpeed, in: 0.5...5.0, step: 0.5)
                    Text("5.0x")
                        .font(.caption2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    #if os(macOS)
                    .fill(Color(NSColor.controlColor))
                    #elseif os(iOS)
                    .fill(Color(UIColor.systemGray6))
                    #endif
            )
        }
    }
}

// MARK: - Filtering Section
struct FilteringSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("フィルタリング")
                .font(.headline)
            
            VStack(spacing: 10) {
                Toggle("軌跡を表示", isOn: $viewModel.showTrajectory)
                Toggle("アンテナを表示", isOn: $viewModel.showAntennas)
                Toggle("データポイントを表示", isOn: $viewModel.showDataPoints)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("精度フィルタ")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("最小精度")
                        Slider(value: $viewModel.minAccuracy, in: 0...1, step: 0.1)
                        Text("\(Int(viewModel.minAccuracy * 100))%")
                            .font(.caption)
                    }
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("時間範囲")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        DatePicker("開始", selection: $viewModel.startTimeFilter, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $viewModel.endTimeFilter, displayedComponents: .hourAndMinute)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    #if os(macOS)
                    .fill(Color(NSColor.controlColor))
                    #elseif os(iOS)
                    .fill(Color(UIColor.systemGray6))
                    #endif
            )
        }
    }
}

// MARK: - Trajectory Analysis Section
struct TrajectoryAnalysisSection: View {
    @ObservedObject var viewModel: TrajectoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("軌跡分析")
                .font(.headline)
            
            if viewModel.hasTrajectoryData {
                HStack(spacing: 30) {
                    AnalysisCard(
                        title: "総移動距離",
                        value: String(format: "%.1f m", viewModel.totalDistance),
                        icon: "arrow.triangle.swap",
                        color: .blue
                    )
                    
                    AnalysisCard(
                        title: "平均速度",
                        value: String(format: "%.2f m/s", viewModel.averageSpeed),
                        icon: "speedometer",
                        color: .green
                    )
                    
                    AnalysisCard(
                        title: "最大速度",
                        value: String(format: "%.2f m/s", viewModel.maxSpeed),
                        icon: "gauge.high",
                        color: .orange
                    )
                    
                    AnalysisCard(
                        title: "測定時間",
                        value: viewModel.totalTimeString,
                        icon: "clock",
                        color: .purple
                    )
                    
                    AnalysisCard(
                        title: "データポイント数",
                        value: "\(viewModel.trajectoryPoints.count)",
                        icon: "point.3.connected.trianglepath.dotted",
                        color: .red
                    )
                }
            } else {
                VStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("分析データがありません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(macOS)
                .fill(Color(NSColor.controlColor))
                #elseif os(iOS)
                .fill(Color(UIColor.systemGray6))
                #endif
        )
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct AntennaMarkerView: View {
    let antenna: AntennaVisualization
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(antenna.color)
                        .frame(width: 32, height: 32)
                )
                .shadow(radius: 1)
            
            Text(antenna.name)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        #if os(macOS)
                        .fill(Color(NSColor.controlBackgroundColor))
                        #elseif os(iOS)
                        .fill(Color(UIColor.systemBackground))
                        #endif
                        .shadow(radius: 0.5)
                )
        }
        .position(antenna.screenPosition)
    }
}

struct TrajectoryPath: View {
    let points: [TrajectoryPoint]
    let color: Color
    
    var body: some View {
        Path { path in
            guard !points.isEmpty else { return }
            
            path.move(to: points[0].screenPosition)
            for point in points.dropFirst() {
                path.addLine(to: point.screenPosition)
            }
        }
        .stroke(color, lineWidth: 2)
        .shadow(radius: 1)
    }
}

struct CurrentPositionMarker: View {
    let position: CGPoint
    
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(radius: 2)
            .position(position)
    }
}

struct SelectedPointMarker: View {
    let point: TrajectoryPoint
    
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.yellow)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("時刻: \(DateFormatter.timeFormatter.string(from: point.timestamp))")
                Text("位置: (\(String(format: "%.1f", point.position.x)), \(String(format: "%.1f", point.position.y)))")
                Text("精度: \(Int(point.accuracy * 100))%")
            }
            .font(.caption2)
            .padding(4)
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
        .position(point.screenPosition)
    }
}

struct TrajectorySessionRowView: View {
    let session: SensingSession
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(session.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(session.dataPoints) points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(session.duration)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
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

struct AnalysisCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(macOS)
                .fill(Color(NSColor.controlBackgroundColor))
                #elseif os(iOS)
                .fill(Color(UIColor.systemBackground))
                #endif
                .shadow(radius: 1)
        )
    }
}

#Preview {
    NavigationStack {
        TrajectoryView()
            .environmentObject(NavigationRouterModel.shared)
    }
}