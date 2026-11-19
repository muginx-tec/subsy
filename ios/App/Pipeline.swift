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

    // MARK: İki replik birden (Selim, 2026-11-20)
    /// Oyun yeni repliği gösterdiğinde eskisi bir an daha ekranda kalır; kutuda ikisi birden okunur
    /// ("... you do not want. Locals: Yo..."). Cümle sonundan sonra gelen "Ad:" kalıbı yeni repliğin başıdır.
    /// Yalnız konuşan adı açık oyunlarda işe yarar; ad yoksa metin tek parça döner. "In Spanish:" ad değil, etikettir.
    private static let sinir = try! NSRegularExpression(
        pattern: #"(?<=[.!?…"”])\s+(?=(?!In [A-Z])[A-Z][\p{L}'.-]*(?: [A-Z][\p{L}'.-]*){0,2}: \S)"#)
    static func replikler(_ text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = [], bas = 0
        for m in sinir.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: bas, length: m.range.location - bas)))
            bas = m.range.location + m.range.length
        }
        out.append(ns.substring(from: bas))
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// Repliğin başındaki dil etiketi ("In Spanish: ...") oyunun notudur, çevrilmez.
    private static let dilEtiketi = try! NSRegularExpression(pattern: #"^In [A-Z][a-z]+:\s*"#)
    static func etiketsiz(_ s: String) -> String {
        dilEtiketi.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    // MARK: Çeviri hafızası (Selim, 2026-11-20)
    /// Aynı replik yeniden görününce (oyun tekrar gösterdi, görev yazısı ekranda duruyor) sunucuya yeniden sorulmaz,
    /// ilk çeviri gösterilir: tutarlı, anında ve bedava. Yalnız telefonun belleğinde, uygulama kapanınca gider.
    /// 4 kelimeden kısa replik bağlama bağlıdır ("Yeah", "Alright, then!"): onun çevirisi yalnız 20 saniye geçerli.
    private var hafiza: [String: (ceviri: String, zaman: Double)] = [:]
    private func hafizaAnahtari(_ body: String) -> String {
        "\(CloudTranslator.game)|\(Diller.secili.kod)|\(MetinOkuyucu.sade(body))"
    }

    /// Son okunan replikler (İngilizce, konuşan adıyla) ve zamanları: bulut çevirisine bağlam olarak gider.
    private var recent: [(String, Double)] = []

    /// Konuşan adının çevirisi ("Nurse" → "Hemşire", "Joel" → "Joel"); bir kez çevrilir, saklanır.
    private var speakerNames: [String: String] = [:]

    /// Altyazı dili değişti: çevirmen oturumu ve saklanan ad çevirileri eski dile ait, bırakılır.
    func dilDegisti() {
        translator.reset()
        speakerNames = [:]
        recent = []; hafiza = [:]
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
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kutuda iki replik birden varsa: daha önce görülmemiş ilk parça işlenir (eskisi yeniden çevrilmez);
        // hepsi görüldüyse sonuncusu. Sıradaki okumada sıra öbür parçaya gelir.
        let parcalar = Pipeline.replikler(text)
        if parcalar.count > 1 {
            text = parcalar.first { p in !recent.contains { sameSubtitle(p, $0.0) } } ?? parcalar[parcalar.count - 1]
        }
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
            // Yalnız sonu oynayan okuma aynı repliktir, yeniden çevrilmez; ilk çeviri kalır (Selim, 2026-11-20:
            // "sonuna bir kaç satır eklendiyse çevirme"). Örnek: repliğin sonuna yapışan plaka her karede başka
            // okununca aynı cümle iki kez çevriliyor, ikincisi ekranda kalıyordu. Replik gerçekten uzadıysa
            // (ikinci satır geldi) aşağıdaki kurallar geçerli.
            let ortak = zip(a, b).prefix { $0 == $1 }.count
            if ortak * 5 >= min(a.count, b.count) * 4, abs(a.count - b.count) <= max(6, b.count / 6) { return }
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
            var (name, body) = Phrasebook.splitSpeaker(Pipeline.etiketsiz(text))
            body = Pipeline.etiketsiz(body)
            if body.isEmpty { body = text; name = nil }
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
                let anahtar = hafizaAnahtari(body)
                let omur = body.split(separator: " ").count >= 4 ? 600.0 : 20.0
                if CloudTranslator.enabled, CloudTranslator.configured, let h = hafiza[anahtar], nowT - h.zaman < omur {
                    translated = h.ceviri; engine = "bulut hafıza"
                } else if CloudTranslator.enabled, CloudTranslator.configured {
                    do {
                        let (t, modelMs) = try await CloudTranslator.translate(body, previous: previous)
                        translated = t; engine = "bulut \(modelMs) ms"
                        hafiza[anahtar] = (t, nowT)
                        if hafiza.count > 300 { hafiza = hafiza.filter { nowT - $0.value.zaman < 600 } }
                    } catch { // sunucu yok, yavaş ya da hata: telefonun çevirisine düş, altyazı boş kalmasın
                        if (error as? CloudTranslator.Failure)?.message == "Pro gerekli" { proGerekli = true; CloudTranslator.proYokKapat() }
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
