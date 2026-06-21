import Foundation
import QuickLookThumbnailing
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: thumb <file.glb> [size]\n".data(using: .utf8)!)
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let size = args.count >= 3 ? (Double(args[2]) ?? 512) : 512

let request = QLThumbnailGenerator.Request(
    fileAt: inputURL,
    size: CGSize(width: size, height: size),
    scale: 1.0,
    representationTypes: .all
)

let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent + ".thumb.png")

var done = false
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
    defer { done = true }
    guard let rep = rep else {
        FileHandle.standardError.write("error: \(error?.localizedDescription ?? "no representation")\n".data(using: .utf8)!)
        return
    }
    let image = rep.nsImage
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("error: failed to encode PNG\n".data(using: .utf8)!)
        return
    }
    do {
        try png.write(to: outURL)
        print(outURL.path)
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    }
}

while !done {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
