import UIKit
import Vision

struct OrientationEvidence {
    let quarterTurns: Int
    var score: Double = 0
    var characters: Int = 0
}
struct OrientationDecision {
    let quarterTurns: Int
    let confident: Bool
}
enum CardOrientation {
    // A rectangle alone cannot tell us which end of the artwork is up.
    static func choose(_ evidence: [OrientationEvidence]) -> OrientationDecision {
        let ranked = evidence.sorted { $0.score > $1.score }
        guard let best = ranked.first, best.characters >= 8, best.score >= 6 else {
            return OrientationDecision(quarterTurns:0,confident:false)
        }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        guard best.score >= runnerUp * 1.25 + 2 else {
            return OrientationDecision(quarterTurns:0,confident:false)
        }
        return OrientationDecision(quarterTurns:best.quarterTurns,confident:true)
    }
    static func detect(_ image: UIImage) throws -> OrientationDecision {
        let scale = min(1,1200 / max(image.size.width,image.size.height))
        let size = CGSize(width:image.size.width * scale,height:image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let sample = UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
        var evidence: [OrientationEvidence] = []
        for turns in 0..<4 {
            try Task.checkCancellation()
            let candidateImage = Imaging.rotated(sample,quarterTurns:turns)
            guard let cg = candidateImage.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage:cg,orientation:.up).perform([request])
            var candidate = OrientationEvidence(quarterTurns:turns)
            for observation in request.results ?? [] {
                guard let text = observation.topCandidates(1).first, text.confidence >= 0.65 else { continue }
                let letters = text.string.filter { $0.isLetter }
                let count = letters.count
                let latin = letters.folding(options:.diacriticInsensitive,locale:Locale(identifier:"en_US_POSIX"))
                guard count >= 3, latin.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value)) }) else { continue }
                // Vision may read rotated text. Compare the first and last words' positions
                // so successfully recognizing upside-down text is not mistaken for upright.
                let string = text.string
                let startEnd = string.index(after:string.startIndex)
                let lastStart = string.index(before:string.endIndex)
                guard let first = try? text.boundingBox(for:string.startIndex..<startEnd),
                      let last = try? text.boundingBox(for:lastStart..<string.endIndex) else { continue }
                let dx = (last.boundingBox.midX-first.boundingBox.midX) * candidateImage.size.width
                let dy = (last.boundingBox.midY-first.boundingBox.midY) * candidateImage.size.height
                let separatedWords = abs(dx) + abs(dy) > 4
                if separatedWords && !(dx > 4 && abs(dy) < dx * 0.45) { continue }
                // Single-word observations have word-precision boxes in accurate mode.
                // Their confidence still contributes, but cannot outweigh clear multiword evidence.
                let weight = separatedWords ? 1.0 : 0.35
                candidate.characters += count
                candidate.score += Double(min(count,48)) * Double(text.confidence) * weight
            }
            evidence.append(candidate)
        }
        return choose(evidence)
    }
}
