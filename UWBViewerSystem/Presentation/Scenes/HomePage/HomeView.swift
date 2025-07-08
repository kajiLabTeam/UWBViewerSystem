//
//  HomeView.swift
//  UWBViewerSystem
//
//  Created by はるちろ on R 7/04/07.
//
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var messageToSend = ""
    @EnvironmentObject var router: NavigationRouterModel
    @State private var sensingFileName = ""
    
    var body: some View {
        VStack(spacing: 20) {
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
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(16)
            
            // リアルタイムデータ表示セクション
            if viewModel.isReceivingRealtimeData {
                VStack(spacing: 16) {
                    Text("リアルタイムセンシングデータ")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    // 端末ごとのデータ表示
                    ForEach(viewModel.deviceRealtimeDataList) { deviceData in
                        DeviceRealtimeCard(deviceData: deviceData)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
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
            
            Spacer()
        }
        .padding()
    }
}

// 端末別リアルタイムデータ表示コンポーネント
struct DeviceRealtimeCard: View {
    let deviceData: DeviceRealtimeData
    
    var body: some View {
        VStack(spacing: 12) {
            // 端末名とステータス
            HStack {
                Text(deviceData.deviceName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // 接続状態インジケーター
                HStack(spacing: 4) {
                    Circle()
                        .fill(deviceData.isRecentlyUpdated ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(deviceData.isRecentlyUpdated ? "接続中" : "未接続")
                        .font(.caption)
                        .foregroundColor(deviceData.isRecentlyUpdated ? .green : .red)
                }
            }
            
            // データ表示部分
            if let latestData = deviceData.latestData {
                RealtimeDataDisplay(data: latestData)
                
                // 履歴データ
                if deviceData.dataHistory.count > 1 {
                    HistoryDataDisplay(dataHistory: deviceData.dataHistory)
                }
            } else {
                Text("データ待機中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// リアルタイムデータ表示コンポーネント
struct RealtimeDataDisplay: View {
    let data: RealtimeData
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                DataValueView(title: "Elevation", value: String(format: "%.2f°", data.elevation), color: .blue)
                DataValueView(title: "Azimuth", value: String(format: "%.2f°", data.azimuth), color: .green)
                DataValueView(title: "Distance", value: String(format: "%.2fm", data.distance), color: .orange)
                DataValueView(title: "RSSI", value: String(format: "%.1f", data.rssi), color: .purple)
            }
            
            HStack {
                Text("NLOS: \(data.nlos)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Seq: \(data.seqCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("更新: \(data.formattedTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
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
