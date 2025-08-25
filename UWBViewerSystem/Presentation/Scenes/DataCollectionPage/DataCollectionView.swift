import SwiftUI

/// データ取得専用画面
/// センシング制御に特化し、参考デザイン「Stitch Design-4.png」に対応
struct DataCollectionView: View {
    @StateObject private var viewModel = DataCollectionViewModel()
    @EnvironmentObject var router: NavigationRouterModel
    @State private var sensingFileName = ""
    @State private var showFileNameAlert = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            Divider()
            
            sensingControlCard
            
            if viewModel.isSensingActive {
                currentSessionCard
            }
            
            recentSessionsCard
            
            Spacer()
        }
        .padding()
        .navigationTitle("データ取得")
        .alert("ファイル名が必要です", isPresented: $showFileNameAlert) {
            Button("OK") { }
        } message: {
            Text("センシングを開始するには、ファイル名を入力してください。")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("UWBデータ収集制御")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("UWBセンサーからのリアルタイムデータを収集し、指定したファイルに保存します")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Sensing Control Card
    private var sensingControlCard: some View {
        VStack(spacing: 20) {
            Text("センシング制御")
                .font(.headline)
                .fontWeight(.semibold)
            
            // ファイル名入力
            VStack(alignment: .leading, spacing: 8) {
                Text("ファイル名")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("例: experiment_001", text: $sensingFileName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isSensingActive)
                    
                    Text(".csv")
                        .foregroundColor(.secondary)
                }
            }
            
            // 制御ボタン
            HStack(spacing: 16) {
                Button(action: startSensing) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("センシング開始")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.green, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(viewModel.isSensingActive || sensingFileName.isEmpty)
                
                Button(action: stopSensing) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("センシング終了")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.orange]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(!viewModel.isSensingActive)
            }
            
            // 状態表示
            statusIndicator
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Status Indicator
    private var statusIndicator: some View {
        HStack {
            Circle()
                .fill(viewModel.isSensingActive ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
            
            Text(viewModel.sensingStatus)
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            if viewModel.isSensingActive {
                Text("経過時間: \(viewModel.elapsedTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(viewModel.isSensingActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Current Session Card
    private var currentSessionCard: some View {
        VStack(spacing: 16) {
            Text("現在のセッション")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                HStack {
                    Text("ファイル名:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.currentFileName)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("データポイント数:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(viewModel.dataPointCount)")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("接続端末数:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(viewModel.connectedDeviceCount)")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Recent Sessions Card
    private var recentSessionsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("最近のセッション")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    router.push(.dataDisplayPage)
                }) {
                    Text("全て表示")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if viewModel.recentSessions.isEmpty {
                Text("まだセッションがありません")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.recentSessions.prefix(3), id: \.fileName) { session in
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Actions
    private func startSensing() {
        guard !sensingFileName.isEmpty else {
            showFileNameAlert = true
            return
        }
        
        viewModel.startSensing(fileName: sensingFileName)
    }
    
    private func stopSensing() {
        viewModel.stopSensing()
    }
}

// MARK: - Session Row View
struct SessionRowView: View {
    let session: SensingSession
    
    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.fileName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.dataPoints) points")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(session.duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    DataCollectionView()
        .environmentObject(NavigationRouterModel())
}