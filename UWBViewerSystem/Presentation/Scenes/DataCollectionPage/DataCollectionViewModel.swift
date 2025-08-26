import SwiftUI
import Foundation
import Combine

// MARK: - ViewModel

@MainActor
class DataCollectionViewModel: ObservableObject {
    static let shared = DataCollectionViewModel()
    
    @Published var isSensingActive = false
    @Published var sensingStatus = "センシング停止中"
    @Published var currentFileName = ""
    @Published var dataPointCount = 0
    @Published var connectedDeviceCount = 0
    @Published var elapsedTime = "00:00"
    @Published var recentSessions: [SensingSession] = []
    
    private var currentSession: SensingSession?
    private var sensingTimer: Timer?
    private var startTime: Date?
    private let homeViewModel = HomeViewModel.shared
    
    init() {
        loadRecentSessions()
        setupObservers()
    }
    
    deinit {
        sensingTimer?.invalidate()
    }
    
    private func setupObservers() {
        // HomeViewModelからの状態を監視
        homeViewModel.$isSensingControlActive
            .assign(to: &$isSensingActive)
        
        homeViewModel.$sensingStatus
            .assign(to: &$sensingStatus)
        
        homeViewModel.$connectedEndpoints
            .map { $0.count }
            .assign(to: &$connectedDeviceCount)
        
        homeViewModel.$deviceRealtimeDataList
            .map { $0.count }
            .assign(to: &$dataPointCount)
    }
    
    // MARK: - Sensing Control
    
    func startSensing(fileName: String) {
        guard !fileName.isEmpty else { return }
        
        currentFileName = fileName
        currentSession = SensingSession(fileName: fileName, dataPoints: 0)
        startTime = Date()
        
        // HomeViewModelのセンシング開始
        homeViewModel.startRemoteSensing(fileName: fileName)
        
        // タイマー開始
        startTimer()
        
        sensingStatus = "センシング実行中"
        isSensingActive = true
    }
    
    func stopSensing() {
        // HomeViewModelのセンシング停止
        homeViewModel.stopRemoteSensing()
        
        // セッションを完了
        if let session = currentSession, let _ = startTime {
            let endTime = Date()
            let completedSession = SensingSession(
                id: session.id,
                fileName: session.fileName,
                startTime: session.startTime,
                endTime: endTime,
                dataPoints: dataPointCount,
                createdAt: session.createdAt
            )
            
            // 最近のセッションに追加
            recentSessions.insert(completedSession, at: 0)
            if recentSessions.count > 10 {
                recentSessions.removeLast()
            }
            
            saveRecentSessions()
        }
        
        // 状態をリセット
        stopTimer()
        currentSession = nil
        currentFileName = ""
        sensingStatus = "センシング停止中"
        isSensingActive = false
    }
    
    // MARK: - Timer Management
    
    private func startTimer() {
        sensingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }
    
    private func stopTimer() {
        sensingTimer?.invalidate()
        sensingTimer = nil
        elapsedTime = "00:00"
    }
    
    private func updateElapsedTime() {
        guard let startTime = startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Data Persistence
    
    private func saveRecentSessions() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(recentSessions) {
            UserDefaults.standard.set(encoded, forKey: "RecentSensingSessions")
        }
    }
    
    private func loadRecentSessions() {
        if let data = UserDefaults.standard.data(forKey: "RecentSensingSessions") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode([SensingSession].self, from: data) {
                recentSessions = decoded
            }
        }
    }
}