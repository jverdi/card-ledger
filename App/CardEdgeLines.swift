import CoreImage
import Foundation

/// Recovers physical edges when printed tables dominate Vision's rectangle proposals.
/// Votes follow the image gradient direction, so fabric texture cannot join arbitrary lines.
enum CardEdgeLines {
    private struct Line { let angle: Int; let rho: Double; let strength: Double }
    private static let context = CIContext()
    static func detect(_ image: CIImage) -> CardRectangle? {
        let extent = image.extent
        let scale = min(1,512 / max(extent.width,extent.height))
        let resized = image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let cg = context.createCGImage(resized,from:resized.extent,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()),
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 20, h > 20 else { return nil }
        var gray = [Double](repeating:0,count:w*h)
        for y in 0..<h { for x in 0..<w {
            let i = y*cg.bytesPerRow+x*4
            gray[y*w+x] = 0.299*Double(bytes[i])+0.587*Double(bytes[i+1])+0.114*Double(bytes[i+2])
        } }
        let kernel = (-5...5).map { exp(-Double($0*$0)/4.5) }
        let sum = kernel.reduce(0,+)
        var horizontal = gray, smooth = gray
        for y in 0..<h { for x in 0..<w {
            var value = 0.0
            for k in -5...5 { value += gray[y*w+min(w-1,max(0,x+k))]*kernel[k+5] }
            horizontal[y*w+x] = value/sum
        } }
        for y in 0..<h { for x in 0..<w {
            var value = 0.0
            for k in -5...5 { value += horizontal[min(h-1,max(0,y+k))*w+x]*kernel[k+5] }
            smooth[y*w+x] = value/sum
        } }
        let radius = Int(ceil(hypot(Double(w),Double(h)))), bins = radius*2+1
        let cosine = (0..<180).map { cos(Double($0)*Double.pi/180) }
        let sine = (0..<180).map { sin(Double($0)*Double.pi/180) }
        var gx = gray, gy = gray
        var votes = [Double](repeating:0,count:180*bins)
        for y in 1..<(h-1) { for x in 1..<(w-1) {
            let i = y*w+x
            gx[i] = (smooth[i+1]-smooth[i-1])/2
            gy[i] = (smooth[i+w]-smooth[i-w])/2
            let magnitude = hypot(gx[i],gy[i])
            guard magnitude > 7 else { continue }
            let direction = Int((atan2(gy[i],gx[i])*180/Double.pi).rounded())
            for offset in -3...3 {
                let angle = (direction+offset+360)%180
                let rho = Int((Double(x)*cosine[angle]+Double(y)*sine[angle]).rounded())+radius
                votes[angle*bins+rho] += min(30,magnitude)
            }
        } }
        var lines: [Line] = []
        for _ in 0..<24 {
            guard let peak = votes.indices.max(by:{ votes[$0] < votes[$1] }), votes[peak] > 0 else { break }
            let angle = peak/bins, rho = peak%bins
            lines.append(Line(angle:angle,rho:Double(rho-radius),strength:votes[peak]))
            for rawAngle in (angle-5)...(angle+5) {
                let a = (rawAngle+180)%180
                let r = (0..<180).contains(rawAngle) ? rho : radius*2-rho
                for bin in max(0,r-8)...min(bins-1,r+8) { votes[a*bins+bin] = 0 }
            }
        }
        guard lines.count >= 4 else { return nil }
        func angleDistance(_ a: Int,_ b: Int) -> Int { min(abs(a-b),180-abs(a-b)) }
        func intersection(_ a: Line,_ b: Line) -> CGPoint? {
            let determinant = cosine[a.angle]*sine[b.angle]-sine[a.angle]*cosine[b.angle]
            guard abs(determinant) > 0.1 else { return nil }
            return CGPoint(x:(a.rho*sine[b.angle]-sine[a.angle]*b.rho)/determinant,
                           y:(cosine[a.angle]*b.rho-a.rho*cosine[b.angle])/determinant)
        }
        func supported(_ p: CGPoint,_ q: CGPoint,_ angle: Int) -> Bool {
            let count = max(2,Int(hypot(q.x-p.x,q.y-p.y)))
            var strong = 0
            for step in 0..<count {
                let t = Double(step)/Double(count-1)
                let x = p.x+(q.x-p.x)*t, y = p.y+(q.y-p.y)*t
                var strength = 0.0
                for offset in -2...2 {
                    let xx = min(w-2,max(1,Int((x+Double(offset)*cosine[angle]).rounded())))
                    let yy = min(h-2,max(1,Int((y+Double(offset)*sine[angle]).rounded())))
                    strength = max(strength,abs(gx[yy*w+xx]*cosine[angle]+gy[yy*w+xx]*sine[angle]))
                }
                if strength > 5 { strong += 1 }
            }
            return Double(strong)/Double(count) >= 0.8
        }
        var pairs: [(Int,Int)] = []
        for a in lines.indices { for b in (a+1)..<lines.count {
            if angleDistance(lines[a].angle,lines[b].angle) < 12 && abs(lines[a].rho-lines[b].rho) > 40 { pairs.append((a,b)) }
        } }
        var candidates: [(CardRectangle,Double)] = []
        for i in pairs.indices { for j in (i+1)..<pairs.count {
            let (a,b) = pairs[i], (c,d) = pairs[j]
            guard Set([a,b,c,d]).count == 4, angleDistance(lines[a].angle,lines[c].angle) >= 65,
                  let p0 = intersection(lines[a],lines[c]), let p1 = intersection(lines[b],lines[c]),
                  let p2 = intersection(lines[b],lines[d]), let p3 = intersection(lines[a],lines[d]) else { continue }
            let points = [p0,p1,p2,p3]
            let ordered = clockwise(points.map { CGPoint(x:$0.x/Double(w),y:$0.y/Double(h)) })
            let rectangle = CardRectangle(points:ordered,confidence:1,pixelSize:extent.size)
            guard rectangle.likelyCard else { continue }
            let sides = [c,b,d,a]
            guard (0..<4).allSatisfy({ supported(points[$0],points[($0+1)%4],lines[sides[$0]].angle) }) else { continue }
            candidates.append((rectangle,[a,b,c,d].map { lines[$0].strength }.reduce(0,+)))
        } }
        guard let maximumArea = candidates.map({ $0.0.area }).max() else { return nil }
        // Similar-area proposals are quantized versions of the same outline.
        // Prefer its strongest continuous edges rather than inflating the crop.
        return candidates.filter { $0.0.area >= maximumArea*0.97 }.max(by:{ $0.1 < $1.1 })?.0
    }
    private static func clockwise(_ points: [CGPoint]) -> [CGPoint] {
        let center = CGPoint(x:points.map(\.x).reduce(0,+)/4,y:points.map(\.y).reduce(0,+)/4)
        let sorted = points.sorted { atan2($0.y-center.y,$0.x-center.x) < atan2($1.y-center.y,$1.x-center.x) }
        let first = sorted.indices.min { sorted[$0].x+sorted[$0].y < sorted[$1].x+sorted[$1].y }!
        return (0..<4).map { sorted[(first+$0)%4] }
    }
}
