import Foundation

public struct SensingSession: Identifiable, Codable {
    public let id: String
    public let name: String  // ファイル名からセッション名に変更
    public let startTime: Date
    public let endTime: Date?
    public let isActive: Bool
    public let dataPoints: Int
    public let createdAt: Date
    public let duration: String

    public init(name: String, startTime: Date = Date(), dataPoints: Int = 0, isActive: Bool = true) {
        id = UUID().uuidString
        self.name = name
        self.startTime = startTime
        endTime = nil
        self.isActive = isActive
        self.dataPoints = dataPoints
        createdAt = startTime

        // Durationの計算
        if let end = endTime {
            let interval = end.timeIntervalSince(startTime)
            duration = String(format: "%.1fs", interval)
        } else {
            duration = "進行中"
        }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date,
        endTime: Date?,
        isActive: Bool = true,
        dataPoints: Int = 0,
        createdAt: Date? = nil,
        duration: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.dataPoints = dataPoints
        self.createdAt = createdAt ?? startTime

        if let duration {
            self.duration = duration
        } else if let end = endTime {
            let interval = end.timeIntervalSince(startTime)
            self.duration = String(format: "%.1fs", interval)
        } else {
            self.duration = "進行中"
        }
    }

    // 旧データとの互換性のための初期化メソッド
    @available(*, deprecated, message: "Use the new initializer with name parameter")
    public init(fileName: String, startTime: Date = Date(), dataPoints: Int = 0) {
        self.init(name: fileName, startTime: startTime, dataPoints: dataPoints, isActive: true)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: createdAt)
    }
}
