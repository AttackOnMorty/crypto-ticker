import AppKit

let canvasSize = 1024
let dotDiameter: CGFloat = 56
let columns: [CGFloat] = [312, 392, 472, 552, 632, 712]
let rows: [CGFloat] = [216, 290, 364, 438, 512, 586, 660, 734, 808]

let occupied: Set<[Int]> = Set(
    (0...8).map { [0, $0] }
        + (1...4).map { [$0, 0] }
        + (1...4).map { [$0, 4] }
        + (1...4).map { [$0, 8] }
        + (1...3).map { [5, $0] }
        + (5...7).map { [5, $0] }
)

func bitmap(size: Int) -> NSBitmapImageRep {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    representation.size = NSSize(width: size, height: size)
    return representation
}

func drawMaster() -> NSBitmapImageRep {
    let representation = bitmap(size: canvasSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

    NSColor.white.setFill()
    for cell in occupied {
        let centerX = columns[cell[0]]
        let centerY = CGFloat(canvasSize) - rows[cell[1]]
        NSBezierPath(
            ovalIn: NSRect(
                x: centerX - dotDiameter / 2,
                y: centerY - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
        ).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return representation
}

func resized(_ source: NSBitmapImageRep, to size: Int) -> NSBitmapImageRep {
    let destination = bitmap(size: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: destination)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    source.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
    return destination
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputs = [
    ("16-mac.png", 16),
    ("16-mac@2x.png", 32),
    ("32-mac.png", 32),
    ("32-mac@2x.png", 64),
    ("128-mac.png", 128),
    ("128-mac@2x.png", 256),
    ("256-mac.png", 256),
    ("256-mac@2x.png", 512),
    ("512-mac.png", 512),
    ("512-mac@2x.png", 1024),
]

let master = drawMaster()
for (filename, size) in outputs {
    let image = size == canvasSize ? master : resized(master, to: size)
    try image.representation(using: .png, properties: [:])!.write(
        to: outputDirectory.appendingPathComponent(filename)
    )
}
