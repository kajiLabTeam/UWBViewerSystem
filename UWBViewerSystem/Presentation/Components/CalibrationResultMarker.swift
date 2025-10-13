//
//  CalibrationResultMarker.swift
//  UWBViewerSystem
//

import SwiftUI

/// キャリブレーション結果を表示するマーカーコンポーネント
struct CalibrationResultMarker: View {
    let point: MapCalibrationPoint
    let position: CGPoint
    let size: CGFloat
    let isSelected: Bool
    let isDraggable: Bool
    let onPositionChanged: ((CGPoint) -> Void)?
    let onTap: (() -> Void)?

    @State private var dragOffset = CGSize.zero

    init(
        point: MapCalibrationPoint,
        position: CGPoint,
        size: CGFloat = 16,
        isSelected: Bool = false,
        isDraggable: Bool = false,
        onPositionChanged: ((CGPoint) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.point = point
        self.position = position
        self.size = size
        self.isSelected = isSelected
        self.isDraggable = isDraggable
        self.onPositionChanged = onPositionChanged
        self.onTap = onTap
    }

    private var displaySize: CGFloat {
        self.isSelected ? self.size * 1.3 : self.size
    }

    private var markerColor: Color {
        switch self.point.pointIndex {
        case 1:
            return .red
        case 2:
            return .green
        case 3:
            return .blue
        default:
            return .purple
        }
    }

    var body: some View {
        ZStack {
            // 外側の円（選択時のハイライト）
            if self.isSelected {
                Circle()
                    .stroke(self.markerColor, lineWidth: 3)
                    .frame(width: self.displaySize + 8, height: self.displaySize + 8)
                    .opacity(0.6)
            }

            // メインの円
            Circle()
                .fill(self.markerColor.opacity(0.9))
                .frame(width: self.displaySize, height: self.displaySize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: self.isSelected ? 4 : 2)

            // ポイント番号の表示
            Text("\(self.point.pointIndex)")
                .font(.system(size: self.displaySize * 0.5, weight: .bold))
                .foregroundColor(.white)

            // 座標情報のツールチップ（選択時のみ）
            if self.isSelected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Point \(self.point.pointIndex)")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text(
                        "Map: (\(String(format: "%.1f", self.point.mapCoordinate.x)), \(String(format: "%.1f", self.point.mapCoordinate.y)))"
                    )
                    .font(.caption2)
                    Text(
                        "Real: (\(String(format: "%.2f", self.point.realWorldCoordinate.x))m, \(String(format: "%.2f", self.point.realWorldCoordinate.y))m)"
                    )
                    .font(.caption2)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.8))
                )
                .foregroundColor(.white)
                .offset(y: -self.displaySize - 70)
                .zIndex(1000)
            }
        }
        .position(
            x: self.position.x + self.dragOffset.width,
            y: self.position.y + self.dragOffset.height
        )
        .scaleEffect(self.isSelected ? 1.15 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: self.isSelected)
        .zIndex(self.isSelected ? 60 : 15)
        .onTapGesture {
            self.onTap?()
        }
        .gesture(
            self.isDraggable
                ? DragGesture()
                .onChanged { value in
                    self.dragOffset = value.translation
                }
                .onEnded { value in
                    let newPosition = CGPoint(
                        x: position.x + value.translation.width,
                        y: self.position.y + value.translation.height
                    )
                    self.onPositionChanged?(newPosition)
                    self.dragOffset = .zero
                } : nil
        )
    }
}
