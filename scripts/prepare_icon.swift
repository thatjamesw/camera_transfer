import AppKit
import SwiftUI

// Prepare the platform mask and margins without regenerating the approved artwork.
@main
struct PrepareIcon {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 || (args.count == 4 && args[1] == "--preview-app") else {
            fatalError("Usage: prepare_icon input.png output.png | --preview-app app output.png")
        }
        if args[1] == "--preview-app" {
            let icon = NSWorkspace.shared.icon(forFile: args[2])
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
            return
        }

        let bitmap = try NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: args[1])))!
        // Centerline extents ignore stray translucent pixels outside the generated tile.
        func opaque(_ x: Int, _ y: Int) -> Bool {
            (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.98
        }
        let xs = (0..<bitmap.pixelsWide).filter { opaque($0, bitmap.pixelsHigh / 2) }
        let ys = (0..<bitmap.pixelsHigh).filter { opaque(bitmap.pixelsWide / 2, $0) }
        guard let left = xs.first, let right = xs.last, let top = ys.first, let bottom = ys.last,
              let cropped = bitmap.cgImage?.cropping(to: CGRect(x: left, y: top,
                  width: right - left + 1, height: bottom - top + 1)) else {
            fatalError("Icon source must contain an opaque tile")
        }
        // Legacy macOS icon grid: 824-point tile centered in a 1024-point canvas.
        let tile = ZStack {
            Color(red: 0.14, green: 0.16, blue: 0.19)
            Image(decorative: cropped, scale: 1)
                .resizable()
                .interpolation(.high)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 185.4, style: .continuous))
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 1
        guard let output = renderer.cgImage else { fatalError("Could not render icon") }
        try NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: args[2]))
        print("Prepared 1024px icon: source tile \(left),\(top)–\(right),\(bottom), output tile 824px with 100px margins")
    }
}
