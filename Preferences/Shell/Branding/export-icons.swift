import AppKit

// Only standard icon rendition work: resample the approved master and apply
// the same rounded tile silhouette at every output scale.
let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let resources = sourceDirectory.deletingLastPathComponent().appendingPathComponent("Resources")
let sourceURL = sourceDirectory.appendingPathComponent("MetisLogo.png")
guard let source = NSImage(contentsOf: sourceURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot open MetisLogo.png")
}

for (name, points) in [("Metis", 29), ("MetisBrand", 56)] {
    for scale in 1...3 {
        let pixels = points * scale
        let size = CGFloat(pixels)
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Cannot create icon context")
        }
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: size * 0.22,
                              cornerHeight: size * 0.22, transform: nil))
        context.clip()
        context.interpolationQuality = .high
        context.draw(sourceImage, in: bounds)
        let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let target = resources.appendingPathComponent("\(name)\(suffix).png")
        try representation.representation(using: .png, properties: [:])!.write(to: target)
        print("\(target.lastPathComponent): \(pixels) × \(pixels)")
    }
}
