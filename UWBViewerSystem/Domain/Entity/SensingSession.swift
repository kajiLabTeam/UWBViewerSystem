import Foundation

struct SensingSession: Identifiable, Codable {
    let id: String
    let fileName: String
    let startTime: Date
    let endTime: Date?
    let dataPoints: Int
    let createdAt: Date
    let duration: String
    
    init(fileName: String, startTime: Date = Date(), dataPoints: Int = 0) {
        self.id = UUID().uuidString
        self.fileName = fileName
        self.startTime = startTime
        self.endTime = nil
        self.dataPoints = dataPoints
        self.createdAt = startTime
        
        // Durationの計算
        if let end = endTime {
            let interval = end.timeIntervalSince(startTime)
            self.duration = String(format: "%.1fs", interval)
        } else {
            self.duration = "進行中"
        }
    }
    
    init(id: String = UUID().uuidString, fileName: String, startTime: Date, endTime: Date?, dataPoints: Int, createdAt: Date? = nil, duration: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.startTime = startTime
        self.endTime = endTime
        self.dataPoints = dataPoints
        self.createdAt = createdAt ?? startTime
        
        if let duration = duration {
            self.duration = duration
        } else if let end = endTime {
            let interval = end.timeIntervalSince(startTime)
            self.duration = String(format: "%.1fs", interval)
        } else {
            self.duration = "進行中"
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: createdAt)
    }
}