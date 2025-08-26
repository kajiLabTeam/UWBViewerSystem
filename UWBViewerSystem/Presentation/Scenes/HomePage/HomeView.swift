//
//  HomeView.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel.shared
    @State private var messageToSend = ""
    @EnvironmentObject var router: NavigationRouterModel
    @State private var sensingFileName = "sensing_data"  // デフォルト値を設定
    @State private var showSettingsMenu = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // ヘッダーセクション with 設定メニュー
                HStack {
                    Text("UWB制御センター")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // 設定メニューボタン
                    Menu {
                        Button(action: {
                            router.push(.fieldSettingPage)
                        }) {
                            Label("アンテナ配置設定", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        
                        Button(action: {
                            router.push(.pairingSettingPage)
                        }) {
                            Label("端末紐付け設定", systemImage: "link.circle")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            router.push(.advertiserPage)
                        }) {
                            Label("広告専用画面", systemImage: "megaphone")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("設定")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // センシング制御セクション
                VStack(spacing: 16) {
                    Text("一斉センシング制御")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // ファイル名入力
                    HStack {
                        Text("ファイル名:")
                            .frame(width: 80, alignment: .leading)
                        TextField("ファイル名を入力", text: $sensingFileName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // センシング制御ボタン
                    HStack(spacing: 12) {
                        Button(action: {
                            print("センシング開始ボタンが押されました")
                            print("ファイル名: \(sensingFileName)")
                            if sensingFileName.isEmpty {
                                sensingFileName = "sensing_\(Date().timeIntervalSince1970)"
                            }
                            viewModel.startRemoteSensing(fileName: sensingFileName)
                        }) {
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
                        .disabled(viewModel.isSensingControlActive || sensingFileName.isEmpty)
                        
                        Button(action: {
                            print("センシング停止ボタンが押されました")
                            viewModel.stopRemoteSensing()
                        }) {
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
                        .disabled(!viewModel.isSensingControlActive)
                    }
                    
                    // センシング状態表示
                    HStack {
                        Image(systemName: viewModel.isSensingControlActive ? "circle.fill" : "circle")
                            .foregroundColor(viewModel.isSensingControlActive ? .green : .gray)
                        Text(viewModel.sensingStatus)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                
                Divider()
                
                // 接続管理セクション
                VStack(spacing: 12) {
                    Text("接続管理")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            viewModel.startAdvertise()
                        }) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("広告開始")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            viewModel.startDiscovery()
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("発見開始")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.purple)
                            .cornerRadius(8)
                        }
                    }
                    
                    // 接続状態表示
                    Text(viewModel.connectState)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    // デバッグ情報表示
                    VStack(alignment: .leading, spacing: 4) {
                        Text("接続デバッグ情報:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Text("Endpoints: \(viewModel.connectedEndpoints.count)台")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("DeviceNames: \(viewModel.connectedDeviceNames.count)台")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !viewModel.connectedEndpoints.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.connectedEndpoints), id: \.self) { endpoint in
                                    Text("- \(endpoint)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        if !viewModel.connectedDeviceNames.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.connectedDeviceNames), id: \.self) { deviceName in
                                    Text("- \(deviceName)")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        
                        // テスト用ボタン
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Button("テスト送信") {
                                    viewModel.sendData(text: "TEST_MESSAGE")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                                
                                Button("PING送信") {
                                    viewModel.sendData(text: "PING_TEST")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                            }
                            
                            HStack(spacing: 8) {
                                Button("センシングテスト") {
                                    print("直接センシング開始コマンドを送信")
                                    viewModel.sendData(text: "SENSING_START:test_file")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                                
                                Button("停止テスト") {
                                    print("直接センシング停止コマンドを送信")
                                    viewModel.sendData(text: "SENSING_STOP")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(6)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
                
                // リアルタイムデータ表示セクション
                if viewModel.isReceivingRealtimeData {
                    VStack(spacing: 16) {
                        HStack {
                            Text("リアルタイムセンシングデータ")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            // デバッグ情報表示
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("端末数: \(viewModel.deviceRealtimeDataList.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("接続中: \(viewModel.connectedDeviceNames.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // グリッド表示用のレイアウト設定
                        let columns = [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ]
                        
                        // 端末ごとのデータをグリッド表示
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.deviceRealtimeDataList) { deviceData in
                                DeviceRealtimeCard(
                                    deviceData: deviceData, 
                                    isSensingActive: viewModel.isSensingControlActive
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(16)
                }
                
                // 受信データ履歴表示（デバッグ用）
                if !viewModel.receivedDataList.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("受信データ履歴（最新5件）")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button("クリア") {
                                viewModel.receivedDataList.removeAll()
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                        }
                        
                        VStack(spacing: 4) {
                            ForEach(viewModel.receivedDataList.suffix(5), id: \.0) { data in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("From: \(data.0)")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                        
                                        Text(data.1)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.05))
                    .cornerRadius(16)
                }
                
                Divider()
                
                // 専用広告画面への遷移
                VStack(spacing: 12) {
                    Button(action: {
                        router.push(.advertiserPage)
                    }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("広告専用画面を開く")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    
                    Text("端末確認機能付きの広告専用画面")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // ファイル転送進捗表示
                if !viewModel.fileTransferProgress.isEmpty {
                    VStack(spacing: 12) {
                        Text("ファイル転送中")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        ForEach(Array(viewModel.fileTransferProgress.keys), id: \.self) { endpointId in
                            if let progress = viewModel.fileTransferProgress[endpointId] {
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("デバイス: \(endpointId)")
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
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(16)
                }
                
                // 受信ファイル一覧
                if !viewModel.receivedFiles.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Text("受信ファイル")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.openFileStorageFolder()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("フォルダーを開く")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // 保存場所の表示
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("保存場所:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(viewModel.fileStoragePath)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(6)
                        
                        ForEach(viewModel.receivedFiles.prefix(5)) { file in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.fileName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("デバイス: \(file.deviceName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(file.formattedSize) • \(file.formattedDate)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    NSWorkspace.shared.selectFile(file.fileURL.path, inFileViewerRootedAtPath: "")
                                }) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Finderで表示")
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        
                        if viewModel.receivedFiles.count > 5 {
                            Text("他 \(viewModel.receivedFiles.count - 5) 件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(16)
                }
                
                // ファイル保存場所の表示（常時表示）
                VStack(spacing: 12) {
                    HStack {
                        Text("ファイル保存設定")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.openFileStorageFolder()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("保存フォルダーを開く")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("センシング終了後、CSVファイルが以下の場所に自動保存されます：")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("保存場所:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(viewModel.fileStoragePath.isEmpty ? "Documents/UWBFiles/" : viewModel.fileStoragePath)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Spacer()
                        }
                        
                        Text("ファイル名形式: yyyyMMdd_HHmmss_[端末名]_[元ファイル名].csv")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(16)
            }
            .padding()
        }
    }
}

// 端末別リアルタイムデータ表示コンポーネント
struct DeviceRealtimeCard: View {
    @ObservedObject var deviceData: DeviceRealtimeData
    let isSensingActive: Bool
    
    // 状態判定
    private var deviceStatus: (text: String, color: Color) {
        if !isSensingActive {
            return ("停止", .gray)
        } else if deviceData.hasIssue {
            return ("問題あり", .red)
        } else {
            return ("正常", .green)
        }
    }
    
    private var backgroundColors: (fill: Color, stroke: Color) {
        if !isSensingActive {
            return (Color.gray.opacity(0.05), Color.gray.opacity(0.2))
        } else if deviceData.hasIssue {
            return (Color.red.opacity(0.1), Color.red.opacity(0.4))
        } else {
            return (Color.gray.opacity(0.05), Color.green.opacity(0.3))
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // 端末名とステータス
            HStack {
                Text(deviceData.deviceName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Spacer()
                
                // 状態インジケーター
                HStack(spacing: 3) {
                    Circle()
                        .fill(deviceStatus.color)
                        .frame(width: 8, height: 8)
                    Text(deviceStatus.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(deviceStatus.color)
                }
            }
            
            // データ表示部分
            if let latestData = deviceData.latestData, isSensingActive {
                EnhancedRealtimeDataDisplay(data: latestData, isConnected: !deviceData.hasIssue)
            } else if isSensingActive {
                NoDataDisplay(deviceName: deviceData.deviceName, isConnected: deviceData.isActive)
            } else {
                StoppedDisplay()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColors.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(backgroundColors.stroke, lineWidth: 1)
                )
        )
        .onReceive(deviceData.objectWillChange) { _ in
            // データ変更時の追加処理（必要に応じて）
            print("DeviceRealtimeCard: データが更新されました - \(deviceData.deviceName)")
        }
    }
}

// データがない場合の表示コンポーネント
struct NoDataDisplay: View {
    let deviceName: String
    let isConnected: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            if isConnected {
                Text("接続中 - データ待機")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        EnhancedDataValueView(title: "Elevation", value: "--", color: .gray)
                        EnhancedDataValueView(title: "Azimuth", value: "--", color: .gray)
                    }
                    HStack(spacing: 12) {
                        EnhancedDataValueView(title: "Distance", value: "--", color: .gray)
                        EnhancedDataValueView(title: "RSSI", value: "--", color: .gray)
                    }
                }
                
                Text("センサーデータが送信されていません")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            } else {
                Text("接続なし")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fontWeight(.medium)
                
                Text("端末が切断されています")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }
}

// センシング停止状態の表示コンポーネント
struct StoppedDisplay: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("センシング停止中")
                .font(.caption)
                .foregroundColor(.gray)
                .fontWeight(.medium)
            
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    EnhancedDataValueView(title: "Elevation", value: "--", color: .gray)
                    EnhancedDataValueView(title: "Azimuth", value: "--", color: .gray)
                }
                HStack(spacing: 12) {
                    EnhancedDataValueView(title: "Distance", value: "--", color: .gray)
                    EnhancedDataValueView(title: "RSSI", value: "--", color: .gray)
                }
            }
            
            Text("センシング開始ボタンを押してください")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// 強化されたリアルタイムデータ表示コンポーネント（グリッド用・数値大きく・正式名称）
struct EnhancedRealtimeDataDisplay: View {
    let data: RealtimeData
    let isConnected: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            // メインデータ（2x2レイアウト・大きな数値）
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    EnhancedDataValueView(title: "Elevation", value: String(format: "%.1f°", data.elevation), color: .blue)
                    EnhancedDataValueView(title: "Azimuth", value: String(format: "%.1f°", data.azimuth), color: .green)
                }
                HStack(spacing: 12) {
                    EnhancedDataValueView(title: "Distance", value: String(format: "%.2fm", data.distance), color: .orange)
                    EnhancedDataValueView(title: "RSSI", value: String(format: "%.0f", data.rssi), color: .purple)
                }
            }
            
            // サブ情報（小さく）
            HStack {
                VStack(spacing: 2) {
                    Text("NLOS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(data.nlos)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Sequence")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(data.seqCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Updated")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(data.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isConnected ? Color.gray.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

// 強化されたデータ値表示コンポーネント（大きな数値・正式名称）
struct EnhancedDataValueView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// コンパクトなリアルタイムデータ表示コンポーネント（グリッド用）
struct CompactRealtimeDataDisplay: View {
    let data: RealtimeData
    let isConnected: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // メインデータ（2行レイアウト）
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    CompactDataValueView(title: "E", value: String(format: "%.1f°", data.elevation), color: .blue)
                    CompactDataValueView(title: "A", value: String(format: "%.1f°", data.azimuth), color: .green)
                }
                HStack(spacing: 8) {
                    CompactDataValueView(title: "D", value: String(format: "%.1fm", data.distance), color: .orange)
                    CompactDataValueView(title: "R", value: String(format: "%.0f", data.rssi), color: .purple)
                }
            }
            
            // サブ情報
            HStack {
                Text("N:\(data.nlos)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("S:\(data.seqCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(data.formattedTime)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isConnected ? Color.gray.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

// コンパクトなデータ値表示コンポーネント（グリッド用）
struct CompactDataValueView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// コンパクトな履歴データ表示コンポーネント（グリッド用）
struct CompactHistoryDataDisplay: View {
    let dataHistory: [RealtimeData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("履歴")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ForEach(Array(dataHistory.suffix(2).reversed().enumerated()), id: \.element.id) { index, data in
                HStack(spacing: 4) {
                    Text("\(String(format: "%.0f", data.elevation))°")
                        .font(.caption2)
                        .frame(width: 25, alignment: .trailing)
                        .foregroundColor(.blue)
                    Text("\(String(format: "%.0f", data.azimuth))°")
                        .font(.caption2)
                        .frame(width: 25, alignment: .trailing)
                        .foregroundColor(.green)
                    Text("\(String(format: "%.1f", data.distance))m")
                        .font(.caption2)
                        .frame(width: 25, alignment: .trailing)
                        .foregroundColor(.orange)
                    Spacer()
                    Text(data.formattedTime.suffix(8))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .opacity(1.0 - Double(index) * 0.4)
            }
        }
        .padding(4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(4)
    }
}

// データ値表示コンポーネント
struct DataValueView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

// 履歴データ表示コンポーネント
struct HistoryDataDisplay: View {
    let dataHistory: [RealtimeData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("履歴（最新3件）")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ForEach(Array(dataHistory.suffix(3).reversed().enumerated()), id: \.element.id) { index, data in
                HStack {
                    Text("E: \(String(format: "%.1f", data.elevation))°")
                        .font(.caption2)
                        .frame(width: 45, alignment: .leading)
                        .foregroundColor(.blue)
                    Text("A: \(String(format: "%.1f", data.azimuth))°")
                        .font(.caption2)
                        .frame(width: 45, alignment: .leading)
                        .foregroundColor(.green)
                    Text("D: \(String(format: "%.1f", data.distance))m")
                        .font(.caption2)
                        .frame(width: 40, alignment: .leading)
                        .foregroundColor(.orange)
                    Spacer()
                    Text(data.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .opacity(1.0 - Double(index) * 0.3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
}

#Preview {
    HomeView()
}
