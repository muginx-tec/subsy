import CoreImage
import CoreVideo
import Vision

/// Oyun karesindeki altyazıyı okur (Apple Vision, telefonda, ücretsiz).
/// Kare konsoldan düz ve yatay gelir; kullanıcının ayarladığı kutu kırpılıp okunur.
enum MetinOkuyucu {
    /// Okunacak kutu: kare içinde kutunun kapladığı alan.
    static func kutu(of pixelBuffer: CVPixelBuffer, box: Kutu) -> CIImage {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let a = image.extent
        let w = a.width * box.w, h = a.height * box.h
        let crop = CGRect(x: a.minX + a.width * box.cx - w / 2, y: a.minY + a.height * box.cy - h / 2, width: w, height: h).intersection(a)
        return image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    static func oku(_ image: CIImage, context: CIContext) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.04 // kutu yüksekliğine göre; küçük arayüz yazılarını eler
        let handler = VNImageRequestHandler(ciImage: image, options: [.ciContext: context])
        try? handler.perform([request])
        // Satırları yukarıdan aşağı, soldan sağa diz.
        return (request.results ?? [])
            .compactMap { obs -> (CGRect, String)? in
                guard let top = obs.topCandidates(1).first, top.confidence >= 0.3 else { return nil }
                let s = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.count >= 2 ? (obs.boundingBox, s) : nil
            }
            .sorted { a, b in
                if abs(a.0.midY - b.0.midY) > 0.05 { return a.0.midY > b.0.midY }
                return a.0.minX < b.0.minX
            }
            .map(\.1).joined(separator: " ")
    }

    /// Karşılaştırma için sadeleştirir: harf dışını atar, aksanları düzler ("bağlandı" = "baglandi").
    static func sade(_ s: String) -> String {
        let plain = s.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(plain.lowercased().filter { $0.isLetter })
    }
}

/// Okunacak kutu. Değerler kareye oranla (0-1); cy kutunun ortasının alttan yüksekliği.
struct Kutu: Codable, Equatable {
    var cx: Double
    var cy: Double
    var h: Double
    var w: Double

    static let varsayilan = Kutu(cx: 0.5, cy: 0.2, h: 0.4, w: 0.76)

    mutating func clamp() {
        h = min(max(h, 0.08), 1)
        w = min(max(w, 0.2), 1)
        cy = min(max(cy, h / 2), 1 - h / 2)
        cx = min(max(cx, w / 2), 1 - w / 2)
    }

    /// Kullanıcının ayarladığı kutu (telefonda saklanır).
    static var kayitli: Kutu {
        get {
            if let d = UserDefaults.standard.data(forKey: "kutu"), let b = try? JSONDecoder().decode(Kutu.self, from: d) { return b }
            return varsayilan
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "kutu") }
    }
}
