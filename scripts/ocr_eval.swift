#!/usr/bin/swift
import Foundation
import PDFKit
import Vision
import AppKit

let pdfPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard !pdfPath.isEmpty, let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
    fputs("Usage: ocr_eval.swift <pdf>\n", stderr)
    exit(1)
}

struct Obs { let text: String; let midY: CGFloat; let minX: CGFloat }

func recognize(_ cgImage: CGImage) async throws -> [Obs] {
    try await withCheckedThrowingContinuation { cont in
        let req = VNRecognizeTextRequest { request, error in
            if let error { cont.resume(throwing: error); return }
            let results = request.results as? [VNRecognizedTextObservation] ?? []
            let mapped = results.compactMap { obs -> Obs? in
                guard let t = obs.topCandidates(1).first?.string else { return nil }
                let b = obs.boundingBox
                return Obs(text: t.trimmingCharacters(in: .whitespaces), midY: b.midY, minX: b.minX)
            }
            cont.resume(returning: mapped)
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([req]) } catch { cont.resume(throwing: error) }
    }
}

func layoutLines(from observations: [Obs]) -> [(text: String, segments: [String])] {
    let sorted = observations.sorted {
        if abs($0.midY - $1.midY) > 0.012 { return $0.midY > $1.midY }
        return $0.minX < $1.minX
    }
    var rows: [[Obs]] = []
    for obs in sorted {
        if let i = rows.indices.last, abs(rows[i][0].midY - obs.midY) <= 0.012 {
            rows[i].append(obs)
        } else { rows.append([obs]) }
    }
    return rows.map { row in
        let segs = row.sorted { $0.minX < $1.minX }.map(\.text)
        return (segs.joined(separator: " "), segs)
    }
}

Task {
    var allText = ""
    var pageStats: [(Int, Int, Int)] = []
    for i in 0..<min(doc.pageCount, 15) {
        guard let page = doc.page(at: i) else { continue }
        let rect = page.bounds(for: .mediaBox)
        let scale = 2400.0 / max(rect.width, 1)
        let img = page.thumbnail(of: CGSize(width: rect.width * scale, height: rect.height * scale), for: .mediaBox)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        if let obs = try? await recognize(cg) {
            let lines = layoutLines(from: obs)
            let text = lines.map(\.text).joined(separator: "\n")
            allText += "\n--- PAGE \(i+1) ---\n" + text
            pageStats.append((i+1, obs.count, lines.count))
        }
    }
    print("PAGES:", doc.pageCount)
    for s in pageStats { print("Page \(s.0): obs=\(s.1) lines=\(s.2)") }
    print("TOTAL_CHARS:", allText.count)
    print(allText.prefix(8000))
    exit(0)
}
RunLoop.main.run()
