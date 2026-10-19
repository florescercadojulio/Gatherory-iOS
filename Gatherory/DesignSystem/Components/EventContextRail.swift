import SwiftUI

/// A data-independent event index shared by live Home and authored previews.
struct EventContextRail<ID: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let itemIDs: [ID]
    let selectedID: ID
    let previewIndex: Int?
    let title: (ID) -> String
    let annotation: (ID) -> String?
    let onPreview: (ID) -> Void
    let onCommit: (ID) -> Void
    var usesCompactBubble = false
    var accessibilityAnnotation: ((ID) -> String?)? = nil

    private var currentIndex: Int {
        if let previewIndex, itemIDs.indices.contains(previewIndex) { return previewIndex }
        return itemIDs.firstIndex(of: selectedID) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                SharedEventIndexDockShape()
                    .fill(colorScheme == .light ? .thickMaterial : .regularMaterial)
                    .overlay {
                        SharedEventIndexDockShape()
                            .stroke(Color.primary.opacity(colorScheme == .light ? 0.26 : 0.18), lineWidth: 0.5)
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            ForEach(itemIDs.indices, id: \.self) { index in
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    SharedEventIndexCandle()
                                        .fill(index == currentIndex
                                              ? AppTheme.ColorToken.accent
                                              : Color.primary.opacity(candleOpacity(at: index)))
                                        .frame(width: candleWidth(at: index), height: index == currentIndex ? 6 : 4)
                                        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: currentIndex)
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.trailing, 2)
                    }
                    .frame(width: AppTheme.Layout.screenHorizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard !itemIDs.isEmpty else { return }
                        onPreview(itemIDs[index(at: value.location.y, height: proxy.size.height)])
                    }
                    .onEnded { value in
                        guard !itemIDs.isEmpty else { return }
                        onCommit(itemIDs[index(at: value.location.y, height: proxy.size.height)])
                    }
            )
        }
        .frame(width: AppTheme.Layout.minimumTouchTarget, height: 196)
        .overlay(alignment: .trailing) {
            if let previewIndex, itemIDs.indices.contains(previewIndex),
               let label = annotation(itemIDs[previewIndex]) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(usesCompactBubble ? 1 : 2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(width: usesCompactBubble ? nil : 164)
                    .frame(minHeight: usesCompactBubble ? 28 : 32, alignment: .trailing)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.5) }
                    .frame(maxWidth: usesCompactBubble ? 164 : nil, alignment: .trailing)
                    .fixedSize(horizontal: usesCompactBubble, vertical: false)
                    .offset(x: -AppTheme.Layout.minimumTouchTarget)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: previewIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Event switcher")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tap or drag along the rail to select an event")
        .accessibilityAdjustableAction { direction in
            let nextIndex: Int
            switch direction {
            case .increment: nextIndex = min(currentIndex + 1, itemIDs.count - 1)
            case .decrement: nextIndex = max(currentIndex - 1, 0)
            @unknown default: return
            }
            guard itemIDs.indices.contains(nextIndex) else { return }
            let id = itemIDs[nextIndex]
            onPreview(id)
            onCommit(id)
        }
    }

    var accessibilityValue: String {
        guard itemIDs.indices.contains(currentIndex) else { return "No event" }
        let id = itemIDs[currentIndex]
        let summary = "\(title(id)), \(currentIndex + 1) of \(itemIDs.count)"
        guard let detail = accessibilityAnnotation?(id), !detail.isEmpty else { return summary }
        return "\(summary), \(detail)"
    }

    private func candleWidth(at index: Int) -> CGFloat {
        switch abs(index - currentIndex) {
        case 0: AppTheme.Layout.screenHorizontal - 2
        case 1: 8
        default: 4
        }
    }

    private func candleOpacity(at index: Int) -> Double {
        abs(index - currentIndex) == 1 ? 0.62 : 0.34
    }

    private func index(at yPosition: CGFloat, height: CGFloat) -> Int {
        guard !itemIDs.isEmpty, height > 0 else { return 0 }
        let clampedY = min(max(yPosition, 0), height - 0.001)
        return min(Int((clampedY / height) * CGFloat(itemIDs.count)), itemIDs.count - 1)
    }
}

private struct SharedEventIndexCandle: Shape {
    func path(in rect: CGRect) -> Path {
        let halfHeight = rect.height * 0.28
        let radius = min(rect.height / 2, 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.midY - halfHeight))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: rect.minX, y: rect.midY - halfHeight),
                      control2: CGPoint(x: rect.minX, y: rect.midY - halfHeight / 2))
        path.addCurve(to: CGPoint(x: rect.minX + radius, y: rect.midY + halfHeight),
                      control1: CGPoint(x: rect.minX, y: rect.midY + halfHeight / 2),
                      control2: CGPoint(x: rect.minX, y: rect.midY + halfHeight))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct SharedEventIndexDockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let taper = min(rect.height * 0.08, 14)
        let innerRadius = min(rect.width * 0.18, 4)
        let inverseRadius = min(rect.width * 0.36, 8)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX - inverseRadius, y: rect.minY + inverseRadius),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + inverseRadius * 0.55),
                      control2: CGPoint(x: rect.maxX - inverseRadius * 0.45, y: rect.minY + inverseRadius))
        path.addLine(to: CGPoint(x: rect.minX + innerRadius, y: rect.minY + taper))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + taper + innerRadius), control: CGPoint(x: rect.minX, y: rect.minY + taper))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - taper - innerRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + innerRadius, y: rect.maxY - taper), control: CGPoint(x: rect.minX, y: rect.maxY - taper))
        path.addLine(to: CGPoint(x: rect.maxX - inverseRadius, y: rect.maxY - inverseRadius))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX - inverseRadius * 0.45, y: rect.maxY - inverseRadius),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - inverseRadius * 0.55))
        path.closeSubpath()
        return path
    }
}
