import AppKit
import Foundation

let names = [
    "Event", "Registry", "Link", "Venue",
    "Attire", "Flowers", "Food", "Photography",
    "Music", "Decor", "Invitations", "Honeymoon",
    "Other"
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Gatherory/Assets.xcassets")
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/GatheroryCategoryGlassPreview.png")
let columns = 4
let cell = CGSize(width: 224, height: 244)
let padding: CGFloat = 40
let header: CGFloat = 86
let rows = Int(ceil(Double(names.count) / Double(columns)))
let canvas = NSSize(
    width: padding * 2 + CGFloat(columns) * cell.width,
    height: padding * 2 + header + CGFloat(rows) * cell.height
)

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width * 2),
    pixelsHigh: Int(canvas.height * 2),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
NSRect(origin: .zero, size: canvas).fill()

let title = "Gatherory category glass buttons"
title.draw(
    at: NSPoint(x: padding, y: canvas.height - padding - 32),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 27, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
)

for (index, name) in names.enumerated() {
    let column = index % columns
    let row = index / columns
    let x = padding + CGFloat(column) * cell.width
    let y = canvas.height - padding - header - CGFloat(row + 1) * cell.height
    let iconRect = NSRect(x: x + 48, y: y + 50, width: 128, height: 128)
    let labelRect = NSRect(x: x, y: y + 16, width: cell.width, height: 22)
    let path = assets.appendingPathComponent("IdeaCategoryGlass\(name).imageset/CategoryIcon@2x.png")

    if let image = NSImage(contentsOf: path) {
        image.draw(in: iconRect)
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    name.draw(
        in: labelRect,
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    )
}

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
