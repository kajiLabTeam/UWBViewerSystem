import SwiftData
import SwiftUI

/// 自動アンテナキャリブレーション画面
///
/// 各アンテナの位置と角度を自動推定するためのキャリブレーション画面。
/// 複数のタグ位置（既知）でセンシングを行い、各アンテナが観測した座標から
/// アフィン変換を推定してアンテナのANTENNA_CONFIGを自動生成します。
struct AutoAntennaCalibrationView: View {
    @StateObject private var viewModel = AutoAntennaCalibrationViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            self.headerSection

            ScrollView {
                VStack(spacing: 24) {
                    // ステップコンテンツ
                    self.currentStepContent

                    // ナビゲーションボタン
                    self.navigationButtons

                    Spacer(minLength: 80)
                }
                .padding()
            }
        }
        .onAppear {
            self.viewModel.setup(modelContext: self.modelContext)
        }
        .alert("エラー", isPresented: self.$viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.viewModel.errorMessage)
        }
        .alert("キャリブレーション完了", isPresented: self.$viewModel.showSuccessAlert) {
            Button("新しいキャリブレーション", role: .none) {
                self.viewModel.resetCalibration()
            }
            Button("完了", role: .cancel) {}
        } message: {
            Text("全てのアンテナのキャリブレーションが正常に完了しました")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.blue)
                    .font(.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text("自動アンテナキャリブレーション")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ステップ \(self.viewModel.currentStep + 1) / 4: \(self.viewModel.currentStepTitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if self.viewModel.currentAntennaId != nil {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("対象アンテナ")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(self.viewModel.currentAntennaName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }

            ProgressView(value: Double(self.viewModel.currentStep), total: 3.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    // MARK: - Step Content

    @ViewBuilder
    private var currentStepContent: some View {
        switch self.viewModel.currentStep {
        case 0:
            self.antennaSelectionStep
        case 1:
            self.tagPositionSetupStep
        case 2:
            self.dataCollectionStep
        case 3:
            self.calibrationResultStep
        default:
            EmptyView()
        }
    }

    // MARK: - Step 0: アンテナ選択

    private var antennaSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ1: アンテナ選択")
                .font(.headline)

            Text("キャリブレーションを行うアンテナを1つ選択してください")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if self.viewModel.availableAntennas.isEmpty {
                Text("利用可能なアンテナがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(self.viewModel.availableAntennas) { antenna in
                        let isSelected = self.viewModel.currentAntennaId == antenna.id
                        let isCompleted = self.viewModel.completedAntennaIds.contains(antenna.id)

                        Button(action: {
                            self.viewModel.selectAntennaForCalibration(antenna.id)
                        }) {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isCompleted ? .green : (isSelected ? .blue : .gray))
                                    .font(.title3)

                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(isCompleted ? .green : (isSelected ? .blue : .gray))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(antenna.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)

                                        if isCompleted {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        }
                                    }

                                    Text(antenna.id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(
                                isCompleted ? Color.green.opacity(0.1) :
                                    isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05)
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isCompleted ? Color.green :
                                            isSelected ? Color.blue : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            if !self.viewModel.completedAntennaIds.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("完了: \(self.viewModel.completedAntennaIds.count) / \(self.viewModel.availableAntennas.count) アンテナ")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Step 1: タグ位置設定

    private var tagPositionSetupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ2: タグ位置設定")
                .font(.headline)

            Text("フロアマップ上で既知のタグ位置を3つ以上設定してください")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // フロアマップ
            if let floorMapImage = viewModel.floorMapImage,
               let floorMapInfo = viewModel.currentFloorMapInfo
            {
                FloorMapCanvas(
                    floorMapImage: floorMapImage,
                    floorMapInfo: floorMapInfo,
                    calibrationPoints: nil,
                    onMapTap: self.handleMapTap
                ) { geometry in
                    // タグマーカーを表示
                    ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) {
                        index, tagPos in
                        let normalizedPoint = geometry.realWorldToNormalized(
                            CGPoint(x: tagPos.position.x, y: tagPos.position.y)
                        )
                        let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                        ZStack {
                            Circle()
                                .fill(tagPos.isCollected ? Color.green : Color.blue)
                                .frame(width: 32, height: 32)

                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            if tagPos.isCollected {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .offset(x: 12, y: -12)
                            }
                        }
                        .position(displayPosition)
                    }
                }
            } else {
                Text("フロアマップを読み込んでいます...")
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
            }

            // タグリスト
            self.tagPositionList
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var tagPositionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("設定済みタグ位置 (\(self.viewModel.trueTagPositions.count)個)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if !self.viewModel.trueTagPositions.isEmpty {
                    Button("全てクリア") {
                        self.viewModel.clearTagPositions()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

            if self.viewModel.trueTagPositions.isEmpty {
                Text("マップをタップしてタグ位置を設定してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) {
                        index, tagPos in
                        HStack {
                            Circle()
                                .fill(tagPos.isCollected ? Color.green : Color.blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tagPos.tagId)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text(
                                    "X: \(String(format: "%.2f", tagPos.position.x))m, Y: \(String(format: "%.2f", tagPos.position.y))m"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            if tagPos.isCollected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }

                            Button(action: {
                                self.viewModel.removeTagPosition(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Step 2: データ収集

    private var dataCollectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ3: データ収集")
                .font(.headline)

            Text("タグを指定位置に配置してセンシングを実行してください")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 全体進行状況
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("進行状況")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    let completedCount = self.viewModel.trueTagPositions.filter { $0.isCollected }.count
                    Text("\(completedCount) / \(self.viewModel.trueTagPositions.count) 完了")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(completedCount == self.viewModel.trueTagPositions.count ? .green : .blue)
                }

                ProgressView(value: self.viewModel.collectionProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            // 現在のタグ位置
            if let currentTag = self.viewModel.currentTagPosition {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("現在の測定位置: \(currentTag.tagId)")
                                .font(.subheadline)
                                .fontWeight(.bold)

                            Text("X: \(String(format: "%.2f", currentTag.position.x))m, Y: \(String(format: "%.2f", currentTag.position.y))m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if currentTag.isCollected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title)
                        }
                    }
                    .padding()
                    .background(currentTag.isCollected ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // センシング中のインジケーター
                    if self.viewModel.isCollecting {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text("センシング中... (約10秒)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // マップ表示（常時表示）
                    if let floorMapImage = viewModel.floorMapImage,
                       let floorMapInfo = viewModel.currentFloorMapInfo
                    {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("フロアマップ")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            FloorMapCanvas(
                                floorMapImage: floorMapImage,
                                floorMapInfo: floorMapInfo,
                                calibrationPoints: nil,
                                onMapTap: nil
                            ) { geometry in
                                // 他のアンテナ位置マーカー（現在のアンテナ以外）
                                ForEach(self.viewModel.allAntennaPositions.filter { $0.antennaId != self.viewModel.currentAntennaId }) { antennaPos in
                                    let normalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: antennaPos.position.x, y: antennaPos.position.y)
                                    )
                                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                    let antennaDisplayData = AntennaDisplayData(
                                        id: antennaPos.antennaId,
                                        name: antennaPos.antennaName,
                                        rotation: antennaPos.rotation,
                                        color: Color.gray.opacity(0.6)
                                    )

                                    AntennaMarker(
                                        antenna: antennaDisplayData,
                                        position: displayPosition,
                                        size: geometry.antennaSizeInPixels(),
                                        sensorRange: nil,
                                        isSelected: false,
                                        isDraggable: false,
                                        showRotationControls: false
                                    )
                                }

                                // 現在キャリブレーション中のアンテナ位置（目立つように表示）
                                if let currentAntenna = self.viewModel.originalAntennaPosition {
                                    let normalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: currentAntenna.position.x, y: currentAntenna.position.y)
                                    )
                                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                    let currentAntennaDisplayData = AntennaDisplayData(
                                        id: currentAntenna.antennaId,
                                        name: currentAntenna.antennaName,
                                        rotation: currentAntenna.rotation,
                                        color: Color.blue
                                    )

                                    AntennaMarker(
                                        antenna: currentAntennaDisplayData,
                                        position: displayPosition,
                                        size: geometry.antennaSizeInPixels() * 1.5,
                                        sensorRange: geometry.sensorRangeInPixels(),
                                        isSelected: true,
                                        isDraggable: false,
                                        showRotationControls: false
                                    )
                                }

                                // タグ位置マーカー
                                ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) { index, tagPos in
                                    let normalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: tagPos.position.x, y: tagPos.position.y)
                                    )
                                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                    Circle()
                                        .fill(tagPos.isCollected ? Color.green : (index == self.viewModel.currentTagPositionIndex ? Color.orange : Color.blue))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(index + 1)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        )
                                        .position(displayPosition)
                                }

                                // 測定データポイント（センシング中のみ）
                                if self.viewModel.isCollecting {
                                    ForEach(Array(self.viewModel.currentSensingDataPoints.enumerated()), id: \.offset) { _, dataPoint in
                                        let normalizedPoint = geometry.realWorldToNormalized(
                                            CGPoint(x: dataPoint.x, y: dataPoint.y)
                                        )
                                        let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                        Circle()
                                            .fill(Color.red.opacity(0.6))
                                            .frame(width: 8, height: 8)
                                            .position(displayPosition)
                                    }
                                }
                            }
                            .frame(height: 350)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // センシング開始ボタン
                    if !currentTag.isCollected && !self.viewModel.isCollecting {
                        Button(action: {
                            self.viewModel.startCurrentTagPositionCollection()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("タグを配置してセンシング開始")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }
                    // 次の位置へ
                    else if self.viewModel.hasMoreTagPositions {
                        Button(action: {
                            self.viewModel.proceedToNextTagPosition()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("次のタグ位置へ")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                }
            }

            // データ統計
            if !self.viewModel.dataStatistics.isEmpty {
                self.dataStatisticsView
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var dataStatisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("収集データ統計")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(Array(self.viewModel.dataStatistics.keys.sorted()), id: \.self) { antennaId in
                if let tagData = viewModel.dataStatistics[antennaId] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)

                            Text(antennaId)
                                .font(.caption)
                                .fontWeight(.medium)

                            Spacer()

                            Text("計\(tagData.values.reduce(0, +))件")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }

                        ForEach(Array(tagData.keys.sorted()), id: \.self) { tagId in
                            HStack {
                                Text(tagId)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("\(tagData[tagId] ?? 0)件")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Step 3: キャリブレーション結果

    private var calibrationResultStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ステップ4: キャリブレーション結果")
                .font(.headline)

            if let result = self.viewModel.currentAntennaResult {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)

                        Text("\(self.viewModel.currentAntennaName) のキャリブレーション完了")
                            .font(.headline)
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)

                            Text(self.viewModel.currentAntennaName)
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("位置:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(
                                    "X: \(String(format: "%.3f", result.position.x))m, Y: \(String(format: "%.3f", result.position.y))m"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                            }

                            HStack {
                                Text("角度:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(String(format: "%.2f", result.angleDegrees))°")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("RMSE:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("\(String(format: "%.4f", result.rmse))m")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        result.rmse < 0.1 ? .green : (result.rmse < 0.3 ? .orange : .red)
                                    )
                            }

                            HStack {
                                Text("スケール:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(
                                    "sx: \(String(format: "%.3f", result.scaleFactors.sx)), sy: \(String(format: "%.3f", result.scaleFactors.sy))"
                                )
                                .font(.caption)
                                .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    // キャリブレーション結果のマップ表示
                    if let floorMapImage = viewModel.floorMapImage,
                       let floorMapInfo = viewModel.currentFloorMapInfo
                    {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("マップ表示")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            FloorMapCanvas(
                                floorMapImage: floorMapImage,
                                floorMapInfo: floorMapInfo,
                                calibrationPoints: nil,
                                onMapTap: nil
                            ) { geometry in
                                // すべてのアンテナ位置マーカー（他のアンテナ）
                                ForEach(self.viewModel.allAntennaPositions.filter { $0.antennaId != self.viewModel.currentAntennaId }) { antennaPos in
                                    let normalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: antennaPos.position.x, y: antennaPos.position.y)
                                    )
                                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                    let antennaDisplayData = AntennaDisplayData(
                                        id: antennaPos.antennaId,
                                        name: antennaPos.antennaName,
                                        rotation: antennaPos.rotation,
                                        color: Color.gray.opacity(0.6)
                                    )

                                    AntennaMarker(
                                        antenna: antennaDisplayData,
                                        position: displayPosition,
                                        size: geometry.antennaSizeInPixels(),
                                        sensorRange: nil,
                                        isSelected: false,
                                        isDraggable: false,
                                        showRotationControls: false
                                    )
                                }

                                // タグ位置マーカー（キャリブレーションに使用）
                                ForEach(Array(self.viewModel.trueTagPositions.enumerated()), id: \.offset) { index, tagPos in
                                    let normalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: tagPos.position.x, y: tagPos.position.y)
                                    )
                                    let displayPosition = geometry.normalizedToImageCoordinate(normalizedPoint)

                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(index + 1)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        )
                                        .position(displayPosition)
                                }

                                // 変更前のアンテナ位置（赤、半透明）
                                if let original = self.viewModel.originalAntennaPosition {
                                    let originalNormalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: original.position.x, y: original.position.y)
                                    )
                                    let originalDisplayPosition = geometry.normalizedToImageCoordinate(originalNormalizedPoint)

                                    let originalAntennaDisplayData = AntennaDisplayData(
                                        id: original.antennaId,
                                        name: "変更前",
                                        rotation: original.rotation,
                                        color: Color.red.opacity(0.5)
                                    )

                                    AntennaMarker(
                                        antenna: originalAntennaDisplayData,
                                        position: originalDisplayPosition,
                                        size: geometry.antennaSizeInPixels() * 1.1,
                                        sensorRange: nil,
                                        isSelected: false,
                                        isDraggable: false,
                                        showRotationControls: false
                                    )

                                    // 変更前から変更後への移動線
                                    let newNormalizedPoint = geometry.realWorldToNormalized(
                                        CGPoint(x: result.position.x, y: result.position.y)
                                    )
                                    let newDisplayPosition = geometry.normalizedToImageCoordinate(newNormalizedPoint)

                                    Path { path in
                                        path.move(to: originalDisplayPosition)
                                        path.addLine(to: newDisplayPosition)
                                    }
                                    .stroke(Color.purple.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4]))
                                }

                                // 推定されたアンテナ位置（新しい位置）
                                let antennaNormalizedPoint = geometry.realWorldToNormalized(
                                    CGPoint(x: result.position.x, y: result.position.y)
                                )
                                let antennaDisplayPosition = geometry.normalizedToImageCoordinate(antennaNormalizedPoint)

                                let newAntennaDisplayData = AntennaDisplayData(
                                    id: self.viewModel.currentAntennaId ?? "",
                                    name: self.viewModel.currentAntennaName,
                                    rotation: result.angleDegrees,
                                    color: Color.blue
                                )

                                AntennaMarker(
                                    antenna: newAntennaDisplayData,
                                    position: antennaDisplayPosition,
                                    size: geometry.antennaSizeInPixels() * 1.3,
                                    sensorRange: nil,
                                    isSelected: true,
                                    isDraggable: false,
                                    showRotationControls: false
                                )
                            }
                            .frame(height: 350)

                            // 凡例
                            VStack(alignment: .leading, spacing: 8) {
                                Text("凡例")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.red.opacity(0.3))
                                            .frame(width: 12, height: 12)
                                        Text("変更前")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 12, height: 12)
                                        Text("変更後")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                        Text("タグ位置")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 12, height: 12)
                                        Text("他のアンテナ")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // 次のアンテナへ進むボタン
                    if self.viewModel.hasMoreAntennas {
                        Button(action: {
                            self.viewModel.proceedToNextAntenna()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("次のアンテナへ")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    } else {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.title)

                                Text("全てのアンテナのキャリブレーションが完了しました")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)

                            Button(action: {
                                self.viewModel.resetCalibration()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("新しいキャリブレーション")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundColor(.blue)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            } else if self.viewModel.isCalibrating {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("キャリブレーション実行中...")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            } else {
                // キャリブレーション実行ボタン（データ収集完了後に表示）
                Button(action: {
                    self.viewModel.startCalibration()
                }) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                        Text("キャリブレーション実行")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(self.viewModel.canStartCalibration ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!self.viewModel.canStartCalibration)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if self.viewModel.canGoBack {
                Button("戻る") {
                    self.viewModel.goBack()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.blue)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            if self.viewModel.canProceedToNext {
                Button("次へ") {
                    self.viewModel.proceedToNext()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Handlers

    private func handleMapTap(at location: CGPoint) {
        guard self.viewModel.currentStep == 1 else { return }

        let point = Point3D(
            x: Double(location.x),
            y: Double(location.y),
            z: 0.0
        )
        self.viewModel.addTagPosition(at: point)
    }
}

// MARK: - Preview

struct AutoAntennaCalibrationView_Previews: PreviewProvider {
    static var previews: some View {
        AutoAntennaCalibrationView()
    }
}
