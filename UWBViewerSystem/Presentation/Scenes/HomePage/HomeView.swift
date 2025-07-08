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

#Preview {
    HomeView()
}
