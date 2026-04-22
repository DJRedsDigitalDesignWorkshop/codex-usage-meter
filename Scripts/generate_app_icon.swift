import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: swift Scripts/generate_app_icon.swift <appiconset-path>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

struct IconSpec {
    let pointSize: Int
    let scale: Int

    var pixelSize: Int { pointSize * scale }
    var filename: String { "icon_\(pointSize)x\(pointSize)@\(scale)x.png" }
}

let specs: [IconSpec] = [
    .init(pointSize: 16, scale: 1),
    .init(pointSize: 16, scale: 2),
    .init(pointSize: 32, scale: 1),
    .init(pointSize: 32, scale: 2),
    .init(pointSize: 128, scale: 1),
    .init(pointSize: 128, scale: 2),
    .init(pointSize: 256, scale: 1),
    .init(pointSize: 256, scale: 2),
    .init(pointSize: 512, scale: 1),
    .init(pointSize: 512, scale: 2),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225

    let backgroundPath = NSBezierPath(
        roundedRect: bounds.insetBy(dx: size * 0.035, dy: size * 0.035),
        xRadius: cornerRadius,
        yRadius: cornerRadius
    )

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.05, green: 0.33, blue: 0.86, alpha: 1.0)
    ])!
    gradient.draw(in: backgroundPath, angle: 90)

    NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
    backgroundPath.lineWidth = max(2, size * 0.018)
    backgroundPath.stroke()

    let highlightPath = NSBezierPath(
        roundedRect: NSRect(
            x: size * 0.11,
            y: size * 0.54,
            width: size * 0.78,
            height: size * 0.26
        ),
        xRadius: size * 0.14,
        yRadius: size * 0.14
    )
    NSColor(calibratedWhite: 1.0, alpha: 0.12).setFill()
    highlightPath.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.2)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let font = NSFont.systemFont(ofSize: size * 0.52, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]

    let text = NSString(string: "%")
    let textRect = NSRect(
        x: size * 0.14,
        y: size * 0.18,
        width: size * 0.72,
        height: size * 0.56
    )
    text.draw(in: textRect, withAttributes: attrs)

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

let contents: [String: Any] = [
    "images": specs.map { spec in
        [
            "filename": spec.filename,
            "idiom": "mac",
            "scale": "\(spec.scale)x",
            "size": "\(spec.pointSize)x\(spec.pointSize)"
        ]
    },
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let contentsURL = outputDirectory.appendingPathComponent("Contents.json")
let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: contentsURL)

for spec in specs {
    let image = drawIcon(size: CGFloat(spec.pixelSize))
    guard let data = pngData(from: image) else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to render \(spec.filename)"])
    }

    try data.write(to: outputDirectory.appendingPathComponent(spec.filename))
}
