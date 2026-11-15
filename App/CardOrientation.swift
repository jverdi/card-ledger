import UIKit
import Vision

struct OrientationEvidence {
    let quarterTurns: Int
    var score: Double = 0
    var characters: Int = 0
    var words: Set<String> = []
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
        let accurate = try evidence(in:sample,level:.accurate)
        let decision = choose(accurate)
        if decision.confident { return decision }
        // Accurate OCR returns word-level boxes, so a one-word statistics cell
        // cannot tell us reading direction. Fast OCR provides character positions
        // and resolves those cases without assuming the back matches the front.
        let vocabulary = Set(accurate.flatMap { $0.words })
        let characters = try evidence(in:sample,level:.fast,referenceWords:vocabulary)
        return choose(characters.map { fast in
            let prior = accurate.first { $0.quarterTurns == fast.quarterTurns }
            return OrientationEvidence(quarterTurns:fast.quarterTurns,
                score:fast.score + (prior?.score ?? 0) * 0.35,
                characters:fast.characters + (prior?.characters ?? 0))
        })
    }
    static func isUpright(first: CGPoint, last: CGPoint, size: CGSize) -> Bool {
        let dx = (last.x-first.x) * size.width
        let dy = (last.y-first.y) * size.height
        return dx > 4 && abs(dy) < dx * 0.45
    }
    private static func words(in text:String) -> [String] {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .split(whereSeparator:{ !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    private static func evidence(in sample: UIImage, level: VNRequestTextRecognitionLevel, referenceWords:Set<String> = []) throws -> [OrientationEvidence] {
        var evidence: [OrientationEvidence] = []
        for turns in 0..<4 {
            try Task.checkCancellation()
            let candidateImage = Imaging.rotated(sample,quarterTurns:turns)
            guard let cg = candidateImage.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage:cg,orientation:.up).perform([request])
            var candidate = OrientationEvidence(quarterTurns:turns)
            for observation in request.results ?? [] {
                // Fast Vision often reports 0.5 for correctly recognized words.
                // Accept that tier only when the accurate pass independently read
                // the same tokens; upside-down OCR gibberish gets no vote.
                guard let text = observation.topCandidates(1).first,
                      text.confidence >= (level == .fast ? 0.45:0.65) else { continue }
                let tokens = words(in:text.string)
                if level == .fast && (tokens.isEmpty || !tokens.allSatisfy({ referenceWords.contains($0) })) { continue }
                candidate.words.formUnion(tokens)
                let string = text.string
                let characters = string.filter { $0.isLetter || $0.isNumber }
                guard characters.count >= 3 else { continue }
                let startEnd = string.index(after:string.startIndex)
                let lastStart = string.index(before:string.endIndex)
                guard let first = try? text.boundingBox(for:string.startIndex..<startEnd),
                      let last = try? text.boundingBox(for:lastStart..<string.endIndex),
                      isUpright(first:CGPoint(x:first.boundingBox.midX,y:first.boundingBox.midY),
                                last:CGPoint(x:last.boundingBox.midX,y:last.boundingBox.midY),
                                size:candidateImage.size) else { continue }
                // Prominent labels carry more weight than tiny legal text printed
                // on a different axis. Numbers in statistics tables also count.
                let height = observation.boundingBox.height * candidateImage.size.height / max(sample.size.width,sample.size.height)
                let prominence = min(2,max(0.35,sqrt(Double(height / 0.025))))
                candidate.characters += characters.count
                candidate.score += Double(min(characters.count,48)) * Double(text.confidence) * prominence
            }
            #if DEBUG
            let confidences = (request.results ?? []).compactMap { $0.topCandidates(1).first?.confidence }.map { String(format:"%.2f",$0) }.joined(separator:",")
            print("Orientation level=\(level.rawValue) turns=\(turns) score=\(candidate.score) characters=\(candidate.characters) confidences=[\(confidences)]")
            #endif
            evidence.append(candidate)
        }
        return evidence
    }
}
