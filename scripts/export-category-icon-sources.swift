import AppKit
import Foundation

struct CategorySymbol {
    let name: String
    let symbol: String
    let color: NSColor
    let usesWhiteGlyph: Bool
}

let categories = [
    CategorySymbol(name: "Event", symbol: "calendar.badge.plus", color: .systemTeal, usesWhiteGlyph: true),
    CategorySymbol(name: "Registry", symbol: "gift.fill", color: .systemPurple, usesWhiteGlyph: false),
    CategorySymbol(name: "Link", symbol: "link", color: .systemTeal, usesWhiteGlyph: false),
    CategorySymbol(name: "Venue", symbol: "building.2.fill", color: .systemIndigo, usesWhiteGlyph: true),
    CategorySymbol(name: "Attire", symbol: "hanger", color: .systemPink, usesWhiteGlyph: false),
    CategorySymbol(name: "Flowers", symbol: "camera.macro", color: .systemOrange, usesWhiteGlyph: false),
    CategorySymbol(name: "Food", symbol: "fork.knife", color: .systemYellow, usesWhiteGlyph: true),
    CategorySymbol(name: "Photography", symbol: "camera.aperture", color: .systemTeal, usesWhiteGlyph: false),
    CategorySymbol(name: "Music", symbol: "music.note.list", color: .systemGreen, usesWhiteGlyph: true),
    CategorySymbol(name: "Decor", symbol: "lamp.ceiling.fill", color: .systemPurple, usesWhiteGlyph: true),
    CategorySymbol(name: "Invitations", symbol: "envelope.open.fill", color: .systemBlue, usesWhiteGlyph: true),
    CategorySymbol(name: "Honeymoon", symbol: "suitcase.rolling.fill", color: .systemTeal, usesWhiteGlyph: false),
    CategorySymbol(name: "Other", symbol: "ellipsis", color: .systemPink, usesWhiteGlyph: false),
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/gatherory-category-icon-sources")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvasSize = NSSize(width: 1024, height: 1024)
for category in categories {
    let configuration = NSImage.SymbolConfiguration(
        pointSize: 620,
        weight: .medium,
        scale: .large
    ).applying(NSImage.SymbolConfiguration(paletteColors: [category.usesWhiteGlyph ? .white : category.color]))
    guard let symbol = NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else {
        fputs("Unable to create \(category.symbol)\n", stderr)
        continue
    }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = canvasSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()
    let symbolSize = symbol.size
    let symbolRect = NSRect(
        x: (canvasSize.width - symbolSize.width) / 2,
        y: (canvasSize.height - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: symbolRect)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: outputDirectory.appendingPathComponent("\(category.name).png"))
}
