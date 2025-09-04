import Foundation
import SwiftUI

struct FloorMap: Identifiable {
    let id = UUID()
    let name: String
    let antennaCount: Int
    let width: Double
    let height: Double
    var isActive: Bool

    var formattedSize: String {
        String(format: "%.1f × %.1f m", width, height)
    }
}

class FloorMapViewModel: ObservableObject {
    @Published var floorMaps: [FloorMap] = []
    @Published var selectedFloorMap: FloorMap?

    init() {
        loadFloorMaps()
    }

    func loadFloorMaps() {
        floorMaps = [
            FloorMap(name: "1階 メインフロア", antennaCount: 4, width: 20.0, height: 15.0, isActive: true),
            FloorMap(name: "2階 研究室", antennaCount: 3, width: 15.0, height: 10.0, isActive: false),
            FloorMap(name: "地下1階 実験室", antennaCount: 6, width: 25.0, height: 20.0, isActive: false),
        ]

        selectedFloorMap = floorMaps.first { $0.isActive }

        if !floorMaps.isEmpty {
            UserDefaults.standard.set(true, forKey: "hasFloorMapConfigured")
        }
    }

    func selectFloorMap(_ map: FloorMap) {
        for i in 0..<floorMaps.count {
            floorMaps[i].isActive = (floorMaps[i].id == map.id)
        }
        selectedFloorMap = map
    }

    func toggleActiveFloorMap(_ map: FloorMap) {
        for i in 0..<floorMaps.count {
            if floorMaps[i].id == map.id {
                floorMaps[i].isActive.toggle()
                if floorMaps[i].isActive {
                    selectedFloorMap = floorMaps[i]
                    for j in 0..<floorMaps.count {
                        if j != i && floorMaps[j].isActive {
                            floorMaps[j].isActive = false
                        }
                    }
                } else if selectedFloorMap?.id == map.id {
                    selectedFloorMap = floorMaps.first { $0.isActive }
                }
                break
            }
        }
    }

    func deleteFloorMap(_ map: FloorMap) {
        floorMaps.removeAll { $0.id == map.id }

        if floorMaps.isEmpty {
            UserDefaults.standard.set(false, forKey: "hasFloorMapConfigured")
            selectedFloorMap = nil
        } else if map.isActive && !floorMaps.isEmpty {
            floorMaps[0].isActive = true
            selectedFloorMap = floorMaps[0]
        }
    }

    func addFloorMap(name: String, width: Double, height: Double, antennaCount: Int) {
        let newMap = FloorMap(
            name: name,
            antennaCount: antennaCount,
            width: width,
            height: height,
            isActive: floorMaps.isEmpty
        )

        floorMaps.append(newMap)

        if floorMaps.count == 1 {
            selectedFloorMap = newMap
        }

        UserDefaults.standard.set(true, forKey: "hasFloorMapConfigured")
    }
}
