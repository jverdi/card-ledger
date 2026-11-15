import UIKit
import CryptoKit

/// A local, brightness-independent comparison of the cropped artwork. This is
/// evidence for a review prompt, never proof of an exact catalog/parallel match.
enum CardVisualMatch {
    private final class Fingerprint: NSObject {
        let rotations: [[Double]]
        init(_ pixels: [Double]) {
            var image = pixels
            var turns: [[Double]] = []
            for _ in 0..<4 {
                turns.append(image)
                image = (0..<1024).map { index in image[(31 - index % 32) * 32 + index / 32] }
            }
            rotations = turns
        }
    }
    private static let images: NSCache<NSString,Fingerprint> = {
        let cache = NSCache<NSString,Fingerprint>(); cache.countLimit = 512; return cache
    }()
    private static let comparisons: NSCache<NSString,NSNumber> = {
        let cache = NSCache<NSString,NSNumber>(); cache.countLimit = 2048; return cache
    }()
    private static func key(_ data: Data) -> String {
        SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
    }
    private static func fingerprint(_ data: Data, key: String) -> Fingerprint? {
        if let cached = images.object(forKey:key as NSString) { return cached }
        guard let image = UIImage(data:data) else { return nil }
        // UIImage.draw also honors EXIF orientation. Square normalization lets
        // independent portrait/landscape rotations be compared in all four turns.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let small = UIGraphicsImageRenderer(size:CGSize(width:32,height:32),format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x:0,y:0,width:32,height:32))
            image.draw(in:CGRect(x:0,y:0,width:32,height:32))
        }
        guard let cg = small.cgImage,
              let context = CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:32,
                                      space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue),
              let buffer = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(cg,in:CGRect(x:0,y:0,width:32,height:32))
        let bytes = buffer.bindMemory(to:UInt8.self,capacity:1024)
        let result = Fingerprint((0..<1024).map { Double(bytes[$0]) })
        images.setObject(result,forKey:key as NSString)
        return result
    }
    static func similarity(_ a: Data?, _ b: Data?) -> Double {
        guard let a, let b else { return 0 }
        let ka = key(a), kb = key(b), pair = ([ka,kb].sorted().joined(separator:":")) as NSString
        if let cached = comparisons.object(forKey:pair) { return cached.doubleValue }
        guard let first = fingerprint(a,key:ka), let second = fingerprint(b,key:kb) else { return 0 }
        var best = 0.0
        // Ignore the frame/border and allow small crop drift. Pearson correlation
        // removes uniform exposure/contrast changes. Flat/blank images are rejected.
        let fixed = first.rotations[0]
        for rotated in second.rotations {
            for dy in -2...2 { for dx in -2...2 {
                var sx = 0.0, sy = 0.0, xx = 0.0, yy = 0.0, xy = 0.0
                for y in 4..<28 { for x in 4..<28 {
                    let p = fixed[y*32+x], q = rotated[(y+dy)*32+x+dx]
                    sx += p; sy += q; xx += p*p; yy += q*q; xy += p*q
                } }
                let vx = xx-sx*sx/576, vy = yy-sy*sy/576
                guard vx/576 >= 64, vy/576 >= 64 else { continue }
                best = max(best,(xy-sx*sy/576)/sqrt(vx*vy))
            } }
        }
        comparisons.setObject(NSNumber(value:best),forKey:pair)
        return best
    }
}
