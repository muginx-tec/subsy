import Foundation

/// Konsolun karesinden okunan altyazıyı alır, eler, sabitler, çevirir ve sonucu bildirir.
final class Pipeline {
    struct Result {
        var original: String
        var speaker: String?        // çevrilmiş konuşan adı ("Hemşire"); yoksa nil
        var body: String            // İngilizce metnin addan sonraki kısmı
        var translated: String      // yalnız metnin çevirisi, ad hariç
        var engine: String = "telefon"   // "bulut" ya da "telefon"
        var place: String
        var ocrMs: Double
        var translateMs: Double
        var totalMs: Double     // kare geldikten çeviri hazır olana kadar
        var error: String?
        /// Yapay zekâ çevirisi seçili ama sunucu "Pro gerekli" dedi; telefonla çevrildi.
        var proGerekli = false
    }

    let translator = Translator()
    /// Uygulamanın tek çeviri hattı. Kendi PS5 bağlantımız (Konsol) okuduğu yazıyı buraya verir.
    static weak var main: Pipeline?
    var onResult: ((Result) -> Void)?
    var onKonsolResult: ((Result) -> Void)?   // tam ekran altyazı (kendi bağlantımız)
    var onClear: (() -> Void)?
    var onSkip: ((String) -> Void)?   // çevrilmeyen yazı ve nedeni (kayıt için)

    private var lastText = ""
    private var generation = 0

    // MARK: Sabitleme
    // Aynı altyazı her okumada bir iki harf farklı çıkar. Benzer okumaları tek altyazı sayarız;
    // ilk okuma hemen gösterilir, sonradan ancak iki kez doğrulanmış daha iyi bir okuma onun yerini alır.
    private var variants: [String: Int] = [:]   // bu altyazının görülen okumaları ve kaç kez görüldükleri
    private var shownSource = ""                // şu an çevirisi gösterilen okuma

    private func trigrams(_ s: String) -> Set<String> {
        let c = Array(MetinOkuyucu.sade(s))
        guard c.count >= 3 else { return [String(c)] }
        return Set((0...(c.count - 3)).map { String(c[$0..<$0 + 3]) })
    }

    /// İki okuma aynı altyazının hâlleri mi: üçlü harf dizilerinin yarısından fazlası ortaksa evet.
    private func sameSubtitle(_ a: String, _ b: String) -> Bool {
        let x = trigrams(a), y = trigrams(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(min(x.count, y.count)) >= 0.5
    }

    /// Son okunan replikler (İngilizce, konuşan adıyla) ve zamanları: bulut çevirisine bağlam olarak gider.
    private var recent: [(String, Double)] = []

    /// Konuşan adının çevirisi ("Nurse" → "Hemşire", "Joel" → "Joel"); bir kez çevrilir, saklanır.
    private var speakerNames: [String: String] = [:]

    /// Altyazı dili değişti: çevirmen oturumu ve saklanan ad çevirileri eski dile ait, bırakılır.
    func dilDegisti() {
        translator.reset()
        speakerNames = [:]
        recent = []
        lastText = ""; shownSource = ""; variants = [:]
    }
    private func speakerName(_ name: String) async -> String {
        if let known = speakerNames[name] { return known }
        let t = (try? await translator.translate(name))?.trimmingCharacters(in: CharacterSet(charactersIn: " .:")) ?? name
        let out = t.isEmpty || t.count > 24 ? name : t
        speakerNames[name] = out
        return out
    }

    func handle(text raw: String, capturedAt: Double, ocrMs: Double, place: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != lastText else { return }
        lastText = text
        // Tek kelimelik, noktalamasız yazı altyazı değildir: düğme, sekme, etiket ("Browse", "Freeform").
        let words = text.split(separator: " ")
        if words.count == 1, !text.contains(where: { ".!?…,".contains($0) }) {
            onSkip?("tek kelime, altyazı değil · \"\(text.prefix(40))\"")
            return
        }
        // Tamamı büyük harf olan yazı altyazı değildir: jenerik, menü, bölüm başlığı (2026-11-16 ekran görüntüsü).
        let letters = text.filter(\.isLetter)
        if letters.count >= 4, !letters.contains(where: \.isLowercase) {
            onSkip?("büyük harfli yazı, altyazı değil · \"\(text.prefix(50))\"")
            return
        }

        // Harf içermeyen okuma (arayüz kırıntısı, sayaç) altyazı değildir.
        guard text.filter(\.isLetter).count >= 3 else {
            generation += 1
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.variants = [:]; self.shownSource = ""
                self.onClear?()
            }
            return
        }

        if !shownSource.isEmpty, sameSubtitle(text, shownSource) {
            generation += 1 // bekleyen "temizle" varsa iptal olsun
            variants[text, default: 0] += 1
            let count = variants[text] ?? 0, shownCount = variants[shownSource] ?? 1
            let a = MetinOkuyucu.sade(text), b = MetinOkuyucu.sade(shownSource)
            if a == b || b.contains(a) { return }                       // aynısı ya da eksik hâli
            let fuller = a.contains(b) && count >= 2                     // gösterileni kapsayan daha tam okuma
            let confirmed = count >= 2 && count >= shownCount + 1        // daha sık görülen okuma
            guard fuller || confirmed else { return }
        } else {
            variants = [text: 1]
        }
        shownSource = text
        generation += 1
        let gen = generation

        Task { @MainActor in
            let t0 = CFAbsoluteTimeGetCurrent()
            var translated = ""
            var failure: String?
            let (name, body) = Phrasebook.splitSpeaker(text)
            var speaker: String?
            var engine = "telefon"
            var proGerekli = false
            // Bağlam: son 30 saniyede okunan en çok 4 replik (bu replik hariç). 8 replik ve 90 saniye
            // denendi (2026-11-16); Selim oyunda cevabın uzadığını gördü, 4'e dönüldü.
            let nowT = Date().timeIntervalSince1970
            recent = recent.filter { nowT - $0.1 < 30 }
            let previous = recent.suffix(4).map(\.0)
            if recent.last?.0 != text { recent.append((text, nowT)); if recent.count > 8 { recent.removeFirst() } }
            do {
                if CloudTranslator.enabled, CloudTranslator.configured {
                    do {
                        let (t, modelMs) = try await CloudTranslator.translate(body, previous: previous)
                        translated = t; engine = "bulut \(modelMs) ms"
                    } catch { // sunucu yok, yavaş ya da hata: telefonun çevirisine düş, altyazı boş kalmasın
                        if (error as? CloudTranslator.Failure)?.message == "Pro gerekli" { proGerekli = true }
                        onSkip?("bulut çevirisi olmadı, telefona düşüldü · \((error as? CloudTranslator.Failure)?.message ?? error.localizedDescription)")
                        translated = try await translator.translate(Phrasebook.normalize(body))
                    }
                } else {
                    translated = try await translator.translate(Phrasebook.normalize(body))
                }
                if let name { speaker = await speakerName(name) }
            } catch { failure = error.localizedDescription }
            guard gen == generation || shownSource == text else { return } // bu arada altyazı değişti
            let translateMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            let totalMs = (Date().timeIntervalSince1970 - capturedAt) * 1000
            let result = Result(original: text, speaker: speaker, body: body, translated: translated, engine: engine, place: place, ocrMs: ocrMs,
                                translateMs: translateMs, totalMs: totalMs, error: failure, proGerekli: proGerekli)
            onResult?(result)
            onKonsolResult?(result)
        }
    }
}
