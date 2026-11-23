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
        // Unvanlı ad ("Ms. Sharleen:", "Dr. Miller:") sınır değildir: "Ms." deki nokta cümle sonu sanılıp replik
        // "Ms." ve "Sharleen: ..." diye bölünüyor, eldeki "Ms." atılıyor ve o konuşanın HİÇBİR repliği çevrilmiyordu
        // (Selim oyunda gördü, 2026-11-20). Tek başına kalan kısa kısaltma bir sonraki parçayla birleştirilir.
        var birlesik: [String] = []
        for p in out.map({ $0.trimmingCharacters(in: .whitespaces) }) where !p.isEmpty {
            if let son = birlesik.last, !son.contains(":"), !son.contains(" "), son.count <= 5, son.hasSuffix(".") {
                birlesik[birlesik.count - 1] = son + " " + p
            } else {
                birlesik.append(p)
            }
        }
        return birlesik
    }
    /// Repliğin başındaki dil etiketi ("In Spanish: ...") oyunun notudur, çevrilmez.
    private static let dilEtiketi = try! NSRegularExpression(pattern: #"^In [A-Z][a-z]+:\s*"#)
    static func etiketsiz(_ s: String) -> String {
        dilEtiketi.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    // MARK: Bozuk okunan konuşan adı (Selim, 2026-11-20: "bazen başlıkla geliyor, bazen s.Sharleen: diye")
    /// Ad küçük ve renkli yazıldığı için baş harfleri okunmayabiliyor ("s. Sharleen", "Sharleen") ya da başına kırıntı
    /// yapışıyor ("CAVE Jason"). Küçük harfle başlayan önek ad sayılmadığı için başlık kayboluyor, ad repliğin içinde kalıyordu.
    /// Karar sıklığa göre: oturumda en az 2 kez ve bu önekten daha sık görülmüş bir ad, önekin sonuna uyuyorsa ya da önek
    /// o adın sonuysa o ad kullanılır. ("Uzun olan doğrudur" denendi: tek bir "CAVE Jason" bütün Jason'ları bozdu.)
    /// 323 gerçek okumada: tanınmayan ad 21 → 1.
    private var adSayaci: [String: Int] = [:]
    private static let onekKalibi = try! NSRegularExpression(pattern: #"^\s*([^:\n]{1,30}):\s+\S"#)
    private static let bozukUnvan = try! NSRegularExpression(pattern: #"^[a-z]{1,3}\.\s*([A-Z][\p{L}' .-]{2,22})$"#)
    private func yalin(_ s: String) -> String { String(s.lowercased().filter(\.isLetter)) }
    private func adDuzelt(_ text: String) -> String {
        let ns = text as NSString
        guard let m = Pipeline.onekKalibi.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let iki = text.firstIndex(of: ":") else { return text }
        let onek = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let govde = text[text.index(after: iki)...].trimmingCharacters(in: .whitespaces)
        let k = yalin(onek)
        guard k.count >= 3 else { return text }
        let kendi = adSayaci[onek] ?? 0
        for (ad, n) in adSayaci.sorted(by: { $0.value > $1.value }) where n >= 2 && ad != onek && n > kendi {
            let a = yalin(ad)
            guard a.count >= 3 else { continue }
            if (a.hasSuffix(k) && a.count - k.count <= 4) || (k.hasSuffix(a) && k.count > a.count) || a == k {
                return ad + ": " + govde
            }
        }
        let o = onek as NSString   // henüz sayı yokken: "s. Sharleen" → "Sharleen"
        if let b = Pipeline.bozukUnvan.firstMatch(in: onek, range: NSRange(location: 0, length: o.length)) {
            return o.substring(with: b.range(at: 1)) + ": " + govde
        }
        return text
    }

    // MARK: Çeviri hafızası (Selim, 2026-11-20)
    /// Aynı replik yeniden görününce (oyun tekrar gösterdi, görev yazısı ekranda duruyor) sunucuya yeniden sorulmaz,
    /// ilk çeviri gösterilir: tutarlı, anında ve bedava. Yalnız telefonun belleğinde, uygulama kapanınca gider.
    /// 4 kelimeden kısa replik bağlama bağlıdır ("Yeah", "Alright, then!"): onun çevirisi yalnız 20 saniye geçerli.
    private var hafiza: [String: (ceviri: String, zaman: Double)] = [:]
    private func hafizaAnahtari(_ body: String) -> String {
        "\(CloudTranslator.game)|\(Diller.secili.kod)|\(MetinOkuyucu.sade(body))"
    }

    /// İki okuma KESİN aynı altyazının hâlleri mi: neredeyse aynı uzunluk ve üçlü harf dizilerinin dörtte üçü ortak.
    private func kesinAyni(_ a: String, _ b: String) -> Bool {
        let x = trigrams(a), y = trigrams(b)
        let sa = MetinOkuyucu.sade(a), sb = MetinOkuyucu.sade(b)
        guard !x.isEmpty, !y.isEmpty else { return sa == sb }
        return abs(sa.count - sb.count) <= max(6, sb.count / 6)
            && Double(x.intersection(y).count) / Double(max(x.count, y.count)) >= 0.75
    }

    /// Yeni yazının sonunda, ekranda zaten duran yazıyla ortak bir kuyruk varsa (görev hedefi, tuş ipucu) onu ayırır:
    /// "Andrew: Take a minute... Purchase a longarm" → "Andrew: Take a minute...". En az 2 kelime ve 8 harflik ortak
    /// kuyruk aranır ve geriye en az 3 harflik bir replik kalmalıdır; yoksa yazı olduğu gibi döner.
    private func kuyruksuz(_ text: String, _ onceki: String) -> String {
        let t = text.split(separator: " "), o = onceki.split(separator: " ")
        var n = 0
        while n < t.count, n < o.count, t[t.count - 1 - n] == o[o.count - 1 - n] { n += 1 }
        guard n >= 2, n < t.count else { return text }
        let kuyruk = t[(t.count - n)...].joined(separator: " ")
        let kalan = t[..<(t.count - n)].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " •-"))
        guard kuyruk.filter(\.isLetter).count >= 8, kalan.filter(\.isLetter).count >= 3 else { return text }
        return kalan
    }

    /// Son okunan replikler (İngilizce, konuşan adıyla) ve zamanları: bulut çevirisine bağlam olarak gider.
    private var recent: [(String, Double)] = []

    /// Konuşan adının çevirisi ("Nurse" → "Hemşire", "Joel" → "Joel"); bir kez çevrilir, saklanır.
    private var speakerNames: [String: String] = [:]

    /// Altyazı dili değişti: çevirmen oturumu ve saklanan ad çevirileri eski dile ait, bırakılır.
    func dilDegisti() {
        translator.reset()
        speakerNames = [:]
        recent = []; hafiza = [:]; adSayaci = [:]
        lastText = ""; shownSource = ""; variants = [:]
    }
    private func speakerName(_ name: String) async -> String {
        if let known = speakerNames[name] { return known }
        let t = (try? await translator.translate(name))?.trimmingCharacters(in: CharacterSet(charactersIn: " .:")) ?? name
        let out = t.isEmpty || t.count > 24 ? name : t
        speakerNames[name] = out
        return out
    }

    /// Telefonun çevirisi; günlük ücretsiz süre (UcretsizSure) dolduysa çevirmez.
    private func telefonla(_ body: String) async throws -> String {
        if await MainActor.run(body: { UcretsizSure.bitti }) {
            throw NSError(domain: "UcretsizSure", code: 1, userInfo: [NSLocalizedDescriptionKey: Pipeline.ucretsizBittiHatasi])
        }
        return try await translator.translate(Phrasebook.normalize(body))
    }
    static let ucretsizBittiHatasi = "ucretsiz_sure_bitti"

    func handle(text raw: String, capturedAt: Double, ocrMs: Double, place: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kutuda iki replik birden varsa: daha önce görülmemiş ilk parça işlenir (eskisi yeniden çevrilmez);
        // hepsi görüldüyse sonuncusu. Sıradaki okumada sıra öbür parçaya gelir.
        let parcalar = Pipeline.replikler(text)
        if parcalar.count > 1 {
            text = parcalar.first { p in !recent.contains { sameSubtitle(p, $0.0) } } ?? parcalar[parcalar.count - 1]
        }
        text = adDuzelt(text)
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
            let a = MetinOkuyucu.sade(text), b = MetinOkuyucu.sade(shownSource)
            if a == b || b.contains(a) { return }                       // aynısı ya da eksik hâli
            if kesinAyni(text, shownSource) {
                // KESİN aynı altyazının başka okunuşu (okuma oynaması): yeniden çevrilmez; yerine ancak daha tam ya da
                // daha sık görülen okuma geçer.
                variants[text, default: 0] += 1
                let count = variants[text] ?? 0, shownCount = variants[shownSource] ?? 1
                // Yalnız sonu oynayan okuma aynı repliktir (Selim: "sonuna bir kaç satır eklendiyse çevirme").
                let ortak = zip(a, b).prefix { $0 == $1 }.count
                if ortak * 5 >= min(a.count, b.count) * 4, abs(a.count - b.count) <= max(6, b.count / 6) { return }
                let fuller = a.contains(b) && count >= 2                 // gösterileni kapsayan daha tam okuma
                let confirmed = count >= 2 && count >= shownCount + 1    // daha sık görülen okuma
                guard fuller || confirmed else { return }
            } else {
                // ŞÜPHELİ: gösterilene benziyor ama kesin aynı değil. Atılmaz, yeni replik sayılır (Selim, 2026-11-20:
                // "kesinse atsın, şüpheliyse çevirsin"). Eskiden burada replik ikinci kez görülmeyi bekliyor, o görüş
                // hiç gelmediği için sessizce kayboluyordu: ekranda sabit bir görev yazısı dururken ("Purchase a
                // longarm") ardından gelen her replik onun "daha tam okunuşu" sanılıyordu (300 karede 34 atma, 17 replik).
                text = kuyruksuz(text, shownSource)
                variants = [text: 1]
            }
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
            if let name { adSayaci[name, default: 0] += 1 }
            var speaker: String?
            var engine = "telefon"
            var proGerekli = false
            var atla = false
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
                    atla = h.ceviri.isEmpty   // sunucu bu yazıyı az önce "altyazı değil" diye atlatmıştı: yeniden sorma
                } else if CloudTranslator.enabled, CloudTranslator.configured {
                    do {
                        let (t, modelMs) = try await CloudTranslator.translate(body, previous: previous)
                        translated = t; engine = "bulut \(modelMs) ms"
                        hafiza[anahtar] = (t, nowT)
                        if hafiza.count > 300 { hafiza = hafiza.filter { nowT - $0.value.zaman < 600 } }
                    } catch where (error as? CloudTranslator.Failure)?.message == "atla" {
                        atla = true
                        hafiza[anahtar] = ("", nowT)   // boş çeviri = atlandı; aynı yazı 10 dk yeniden gönderilmez
                    } catch { // sunucu yok, yavaş ya da hata: telefonun çevirisine düş, altyazı boş kalmasın
                        if (error as? CloudTranslator.Failure)?.message == "Pro gerekli" { proGerekli = true; CloudTranslator.proYokKapat() }
                        onSkip?("bulut çevirisi olmadı, telefona düşüldü · \((error as? CloudTranslator.Failure)?.message ?? error.localizedDescription)")
                        translated = try await telefonla(body)
                    }
                } else {
                    translated = try await telefonla(body)
                }
                if let name { speaker = await speakerName(name) }
            } catch { failure = error.localizedDescription }
            if atla {
                // Altyazı değil: ekrana satır eklenmez, sonraki repliklerin bağlamına da girmez.
                recent.removeAll { $0.0 == text }
                if shownSource == text { shownSource = ""; variants = [:] }
                onSkip?("sunucu atlattı, altyazı değil · \"\(text.prefix(40))\"")
                return
            }
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
