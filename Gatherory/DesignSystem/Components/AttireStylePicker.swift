import SwiftUI

/// A shared attire control for event creation and event ideas. Keeping this in
/// the design system gives both flows the same options, selection treatment,
/// accessibility value, and horizontal-scrolling behavior.
struct AttireStylePicker: View {
    @Binding var selection: AttireStyle

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ForEach(AttireStyle.allCases) { style in
                    let isSelected = selection == style

                    Button {
                        withAnimation(.snappy) {
                            selection = style
                        }
                    } label: {
                        VStack(spacing: 6) {
                            AttireStyleSilhouette(
                                style: style,
                                color: isSelected ? .white : .primary
                            )
                            .frame(width: 44, height: 54)

                            Text(style.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(width: 92, height: 88)
                        .background(
                            isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .strokeBorder(
                                    isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.cardBorder,
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Attire style")
    }
}

private struct AttireStyleSilhouette: View {
    let style: AttireStyle
    let color: Color

    var body: some View {
        Canvas { context, size in
            if style == .any {
                drawNeutralFigure(in: &context, size: size, xOffset: -size.width * 0.15, scale: 0.78)
                drawNeutralFigure(in: &context, size: size, xOffset: size.width * 0.15, scale: 0.78)
                return
            }

            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.38,
                    y: size.height * 0.03,
                    width: size.width * 0.24,
                    height: size.width * 0.24
                )),
                with: .color(color)
            )

            var garment = Path()
            switch style {
            case .blackTie:
                garment.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.68))
                garment.closeSubpath()

            case .formal:
                garment.move(to: CGPoint(x: size.width * 0.39, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.96))
                garment.addLine(to: CGPoint(x: size.width * 0.16, y: size.height * 0.96))
                garment.closeSubpath()

            case .cocktail:
                garment.move(to: CGPoint(x: size.width * 0.36, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.70))
                garment.addLine(to: CGPoint(x: size.width * 0.26, y: size.height * 0.70))
                garment.closeSubpath()
                garment.addRect(CGRect(x: size.width * 0.33, y: size.height * 0.68, width: size.width * 0.10, height: size.height * 0.29))
                garment.addRect(CGRect(x: size.width * 0.57, y: size.height * 0.68, width: size.width * 0.10, height: size.height * 0.29))

            case .garden:
                garment.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.90))
                garment.addQuadCurve(
                    to: CGPoint(x: size.width * 0.22, y: size.height * 0.90),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 1.04)
                )
                garment.closeSubpath()

            case .casual:
                garment.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.31))
                garment.addLine(to: CGPoint(x: size.width * 0.75, y: size.height * 0.31))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.63))
                garment.closeSubpath()

            case .any:
                break
            }
            context.fill(garment, with: .color(color))

            if style == .blackTie {
                var lapels = Path()
                lapels.move(to: CGPoint(x: size.width * 0.38, y: size.height * 0.31))
                lapels.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.47))
                lapels.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.31))
                context.stroke(lapels, with: .color(color.opacity(0.45)), lineWidth: 2)

                let bow = Path(roundedRect: CGRect(
                    x: size.width * 0.43,
                    y: size.height * 0.29,
                    width: size.width * 0.14,
                    height: size.height * 0.07
                ), cornerRadius: 2)
                context.fill(bow, with: .color(color))
            }

            if style == .garden {
                var leaf = Path()
                leaf.addEllipse(in: CGRect(
                    x: size.width * 0.57,
                    y: size.height * 0.50,
                    width: size.width * 0.12,
                    height: size.height * 0.18
                ))
                context.stroke(leaf, with: .color(color.opacity(0.55)), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawNeutralFigure(
        in context: inout GraphicsContext,
        size: CGSize,
        xOffset: CGFloat,
        scale: CGFloat
    ) {
        let centerX = size.width * 0.5 + xOffset
        let headSize = size.width * 0.22 * scale
        context.fill(
            Path(ellipseIn: CGRect(
                x: centerX - headSize / 2,
                y: size.height * 0.08,
                width: headSize,
                height: headSize
            )),
            with: .color(color)
        )

        var body = Path()
        body.move(to: CGPoint(x: centerX - size.width * 0.16 * scale, y: size.height * 0.35))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.16 * scale, y: size.height * 0.35))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.11 * scale, y: size.height * 0.70))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.06 * scale, y: size.height * 0.96))
        body.addLine(to: CGPoint(x: centerX - size.width * 0.06 * scale, y: size.height * 0.96))
        body.addLine(to: CGPoint(x: centerX - size.width * 0.11 * scale, y: size.height * 0.70))
        body.closeSubpath()
        context.fill(body, with: .color(color))
    }
}
