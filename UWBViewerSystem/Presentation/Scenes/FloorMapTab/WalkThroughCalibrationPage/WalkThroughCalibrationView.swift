//
//  WalkThroughCalibrationView.swift
//  UWBViewerSystem
//
//  Walk-throughキャリブレーション画面
//

import SwiftData
import SwiftUI

/// Walk-throughキャリブレーション画面
struct WalkThroughCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = WalkThroughCalibrationViewModel()

    let floorMapId: String

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            self.headerSection

            Divider()

            // メインコンテンツ
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // 左側: フロアマップとステータス
                    VStack(spacing: 16) {
                        self.floorMapSection
                            .frame(height: geometry.size.height * 0.6)

                        self.statusSection
                    }
                    .frame(width: geometry.size.width * 0.6)
                    .padding()

                    Divider()

                    // 右側: コントロールと結果
                    VStack(spacing: 20) {
                        self.controlSection

                        if self.viewModel.currentPhase == .completed {
                            self.resultSection
                        }

                        Spacer()
                    }
                    .frame(width: geometry.size.width * 0.4)
                    .padding()
                }
            }
        }
        .onAppear {
            self.viewModel.setup(modelContext: self.modelContext, floorMapId: self.floorMapId)
        }
        .alert("エラー", isPresented: self.$viewModel.showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .navigationTitle("Walk-through キャリブレーション")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Image(systemName: self.viewModel.currentPhase.iconName)
                .font(.title2)
                .foregroundColor(self.viewModel.currentPhase.color)

            VStack(alignment: .leading) {
                Text(self.viewModel.currentPhase.rawValue)
                    .font(.headline)
                    .foregroundColor(self.viewModel.currentPhase.color)

                Text(self.viewModel.currentPhase.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !self.viewModel.isMotionAvailable {
                Label("モーションセンサー未対応", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Floor Map Section

    private var floorMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("フロアマップ")
                .font(.headline)

            ZStack {
                // フロアマップ画像
                if let image = self.viewModel.floorMapImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .overlay {
                            Text("フロアマップなし")
                                .foregroundColor(.secondary)
                        }
                }

                // UWB観測点の描画
                self.uwbPointsOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private var uwbPointsOverlay: some View {
        GeometryReader { geometry in
            ForEach(self.viewModel.uwbPoints) { point in
                Circle()
                    .fill(point.isLineOfSight ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .position(self.transformPoint(point.point, in: geometry.size))
            }
        }
    }

    private func transformPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        // 座標をビューサイズにスケーリング（仮実装）
        let scale = min(size.width, size.height) / 20  // 20m範囲を想定
        let centerX = size.width / 2
        let centerY = size.height / 2
        return CGPoint(
            x: centerX + point.x * scale,
            y: centerY - point.y * scale  // Y軸反転
        )
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                self.statusItem(
                    icon: "figure.walk",
                    title: "歩数",
                    value: "\(self.viewModel.stepCount)"
                )

                self.statusItem(
                    icon: "ruler",
                    title: "距離",
                    value: String(format: "%.1fm", self.viewModel.walkDistance)
                )

                self.statusItem(
                    icon: "clock",
                    title: "時間",
                    value: String(format: "%.1f秒", self.viewModel.elapsedTime)
                )

                self.statusItem(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "UWB観測",
                    value: "\(self.viewModel.uwbObservationCount)"
                )
            }

            if self.viewModel.currentPhase == .walking {
                HStack(spacing: 20) {
                    self.statusItem(
                        icon: "location.north",
                        title: "方位",
                        value: String(format: "%.0f°", self.viewModel.currentHeadingDegrees)
                    )

                    self.statusItem(
                        icon: "speedometer",
                        title: "加速度",
                        value: String(format: "%.2fG", self.viewModel.currentAccelerationG)
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func statusItem(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(minWidth: 70)
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(spacing: 16) {
            Text("操作")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch self.viewModel.currentPhase {
            case .ready, .failed:
                self.startButton

            case .walking:
                self.stopButton

            case .processing:
                self.processingIndicator

            case .completed:
                self.completedControls
            }

            // 警告メッセージ
            if !self.viewModel.warningMessages.isEmpty {
                self.warningsSection
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var startButton: some View {
        Button(action: {
            self.viewModel.startWalkThrough()
        }) {
            Label("歩行開始", systemImage: "play.fill")
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!self.viewModel.isMotionAvailable)
    }

    private var stopButton: some View {
        Button(action: {
            self.viewModel.stopWalkThrough()
        }) {
            Label("歩行終了", systemImage: "stop.fill")
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private var processingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)

            Text("キャリブレーション計算中...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var completedControls: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    await self.viewModel.saveCalibrationResults()
                }
            }) {
                Label("結果を保存", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)

            Button(action: {
                self.viewModel.resetCalibration()
            }) {
                Label("やり直す", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("警告", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.orange)

            ForEach(self.viewModel.warningMessages, id: \.self) { message in
                Text("• \(message)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("キャリブレーション結果")
                .font(.headline)

            if let result = self.viewModel.calibrationResult {
                VStack(alignment: .leading, spacing: 8) {
                    self.resultRow(
                        title: "マッチング点数",
                        value: "\(result.matchedPointCount)点"
                    )

                    self.resultRow(
                        title: "歩行距離",
                        value: String(format: "%.2fm", result.trajectoryLength)
                    )

                    self.resultRow(
                        title: "平均RMSE",
                        value: String(format: "%.4fm", result.rmse)
                    )

                    self.resultRow(
                        title: "推定アンテナ数",
                        value: "\(result.antennaConfigs.count)個"
                    )

                    Divider()

                    // アンテナごとの結果
                    ForEach(Array(result.antennaConfigs.keys.sorted()), id: \.self) { antennaId in
                        if let config = result.antennaConfigs[antennaId] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(antennaId)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text(
                                    "位置: (\(String(format: "%.2f", config.x)), \(String(format: "%.2f", config.y)))m"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)

                                Text("角度: \(String(format: "%.1f", config.angleDegrees))°")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func resultRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WalkThroughCalibrationView(floorMapId: "preview-floor-map")
    }
}
