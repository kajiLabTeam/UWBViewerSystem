import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
class IndoorMapRegistrationViewModel: ObservableObject {
    @Published var selectedMapFile: URL?
    #if os(macOS)
    @Published var mapPreviewImage: NSImage?
    #elseif os(iOS)
    @Published var mapPreviewImage: UIImage?
    #endif
    @Published var mapName = ""
    @Published var buildingName = ""
    @Published var floorName = ""
    @Published var realWidth = ""
    @Published var realHeight = ""
    @Published var description = ""
    
    var canProceed: Bool {
        selectedMapFile != nil &&
        !mapName.isEmpty &&
        !buildingName.isEmpty &&
        !floorName.isEmpty &&
        !realWidth.isEmpty &&
        !realHeight.isEmpty
    }
    
    func selectMapFile() {
        print("🗺️ ファイル選択開始")
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "マップファイルを選択"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        print("🗺️ NSOpenPanel設定完了")
        
        if panel.runModal() == .OK {
            print("🗺️ ファイル選択成功")
            if let url = panel.url {
                print("🗺️ 選択されたファイル: \(url.path)")
                selectedMapFile = url
                loadMapPreview(from: url)
                
                // ファイル名からマップ名を自動設定
                if mapName.isEmpty {
                    mapName = url.deletingPathExtension().lastPathComponent
                    print("🗺️ マップ名自動設定: \(mapName)")
                }
            }
        }
        #elseif os(iOS)
        // iOSではUIDocumentPickerViewControllerを使用（UIViewController経由で実装）
        // この関数は実際にはViewから呼ばれるべきでiOSでは直接は実装できない
        // 代わりにファイル選択のトリガーとしてのみ使用
        #endif
    }
    
    private func loadMapPreview(from url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            loadPDFPreview(from: url)
        } else {
            #if os(macOS)
            mapPreviewImage = NSImage(contentsOf: url)
            #elseif os(iOS)
            if let data = try? Data(contentsOf: url) {
                mapPreviewImage = UIImage(data: data)
            }
            #endif
        }
    }
    
    private func loadPDFPreview(from url: URL) {
        #if os(macOS)
        // PDFの場合は最初のページを画像として読み込み
        guard let pdfDoc = PDFDocument(url: url),
              let page = pdfDoc.page(at: 0) else { return }
        
        let pageRect = page.bounds(for: .mediaBox)
        let render = NSImage(size: pageRect.size)
        
        render.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: 0, y: pageRect.size.height)
            context.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        render.unlockFocus()
        
        mapPreviewImage = render
        #elseif os(iOS)
        // iOSでのPDF読み込み
        guard let pdfDoc = PDFDocument(url: url),
              let page = pdfDoc.page(at: 0) else { return }
        
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        
        mapPreviewImage = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: pageRect.size.height)
            cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
        }
        #endif
    }
    
    func saveMapData() {
        // マップデータを保存する処理
        let mapData = IndoorMapData(
            id: UUID().uuidString,
            name: mapName,
            buildingName: buildingName,
            floorName: floorName,
            filePath: selectedMapFile?.path ?? "",
            realWidth: Double(realWidth) ?? 0,
            realHeight: Double(realHeight) ?? 0,
            description: description,
            createdAt: Date()
        )
        
        // UserDefaultsまたは他の永続化方法で保存
        if let encoded = try? JSONEncoder().encode(mapData) {
            UserDefaults.standard.set(encoded, forKey: "CurrentIndoorMap")
        }
    }
}

// MARK: - Data Model
struct IndoorMapData: Codable {
    let id: String
    let name: String
    let buildingName: String
    let floorName: String
    let filePath: String
    let realWidth: Double
    let realHeight: Double
    let description: String
    let createdAt: Date
}

import PDFKit