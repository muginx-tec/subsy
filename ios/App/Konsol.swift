import CoreImage
import Foundation
import Security
import UIKit

/// PS5'e doğrudan bağlantı (deneme). Bağlantının kendisini biz yazmıyoruz: açık kaynak kütüphane
/// (libchiaki) ve Pylux'un köprü dosyaları yapıyor (ios/App/Baglanti, AGPL-3.0). Bu sınıf yalnız o
/// köprünün hazır çağrılarını sırayla kullanır: PS5'i bul, bir kez kaydol, bağlan, kareyi al.
///
/// Kumanda göndermiyoruz: oyuncu kendi kumandasıyla TV'den oynar, telefon yalnız görüntüyü alır.
final class Konsol: ObservableObject {
    static let shared = Konsol()

    /// Konsol "ekrandaki içerik Uzaktan Oynama'da gösterilemez" dedi (ör. YouTube açık). Kütüphane bunu köprüdeki
    /// geri çağrıyla bildirir (Baglanti/KAYNAK.md); geri çağrı yokken uygulama çöküyordu (2026-11-18).
    @Published var gosterilemez = false

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("SubsyGosterilemez"), object: nil, queue: .main) { [weak self] n in
            guard let self, self.session != nil else { return }
            self.gosterilemez = (n.object as? NSNumber)?.boolValue ?? false
            self.yaz(self.gosterilemez ? "konsol: içerik Uzaktan Oynama'da gösterilemiyor" : "konsol: içerik yeniden gösterilebiliyor")
        }
    }

    enum Durum: Equatable { case bos, kaydoluyor, baglaniyor, bagli, koptu(String) }

    @Published var hosts: [PyluxDiscoveredHost] = []
    /// Uykudaki konsol uyandırılıyor (bağlanmadan önce). 2026-11-23: bağlantı hatalarının çoğu "Bağlan"dan 0 sn sonra geliyordu;
    /// uygulama uykudaki konsolu hiç uyandırmıyordu.
    @Published var uyandiriliyor = false
    /// Son bağlantı denemesi neden olmadı (kullanıcıya gösterilir); boşsa yok.
    @Published var baglantiHatasi = ""
    /// Son eşleştirme denemesi olmadı (kullanıcıya gösterilir). Önceden yalnız deneme kaydına yazılıyordu, kullanıcı hiçbir şey görmüyordu.
    @Published var eslesmeHatasi = false
    /// Son oturum ne zaman bitti: PS5, oturum kapandıktan sonraki ~3 sn içinde gelen isteği reddediyor (chiaki-ng #25);
    /// kullanıcılar hatadan 0 sn sonra yeniden basıyordu (kişi başı ortanca 6, en çok 85 hata).
    private var sonBitis = Date.distantPast
    @Published var durum: Durum = .bos
    @Published var gunluk: [String] = []
    @Published var sonKare: UIImage?
    @Published var kareSayisi = 0
    @Published var kareBoyu = ""

    /// Her çözülmüş kare buraya düşer (çözücünün iş parçacığında). Okuma zinciri sonra buraya bağlanacak.
    var kareGeldi: ((CVPixelBuffer) -> Void)?

    private var discovery: PyluxDiscoveryService?
    private var regist: PyluxRegistService?
    private var session: ChiakiSessionRef?
    private var decoder: PyluxVideoDecoder?
    private var receiver: SessionEventReceiver?
    private let ci = CIContext()
    private var sayac = 0
    private var sonOnizleme = Date.distantPast

    // MARK: Altyazı (okuma + çeviri)

    struct Satir: Identifiable, Equatable {
        let id: Int
        var konusan: String?
        var metin: String
        var renk: Int          // 0, 1, 2: kırmızı, turuncu, sarı
    }

    /// Tam ekran altyazıda gösterilen konuşma; en yenisi sonda.
    @Published var satirlar: [Satir] = []
    @Published var sonSure = ""
    /// Yapay zekâ çevirisi seçili ama kullanıcı Pro değil (sunucu reddetti); altyazı ekranında not gösterilir.
    @Published var proNotu = false
    /// Son repliği kim çevirdi: "bulut" (yapay zekâ, Pro) ya da "telefon". Altyazı ekranının sağ üstünde görünür.
    @Published var cevirmen = "telefon"
    /// Telefonun çevirisi dil paketi olmadığı için yapılamadı: altyazı ekranında "Dil paketini indir" çıkar.
    @Published var paketEksik = false
    /// Günlük ücretsiz süre doldu (UcretsizSure): altyazı ekranında süre bitti kartı.
    @Published var ucretsizBitti = false
    /// Analiz için: altyazı ekranının açıldığı an ve çeviren başına yeni replik sayısı.
    private var altyaziBas: Date?
    private var replikSayisi: [String: Int] = [:]
    private var bulunduBildirildi = false

    private var okumaAcik = false
    /// Kutu ayar ekranı açıkken: okuma sürer ama çevrilmez; okunan ham yazı ekranda gösterilir.
    var kutuAyari = false
    @Published var sonOkunan = ""
    private var okuyor = false
    private var sonOkuma = 0.0
    private let okumaKuyrugu = DispatchQueue(label: "konsol.okuma", qos: .userInitiated)
    private var sonKaynak = ""
    private var siradakiId = 0
    private var adRenkleri: [String: Int] = [:]

    /// Kareden altyazı okumayı başlatır; çeviri uygulamanın tek çeviri hattından (Pipeline) geçer,
    /// yani telefonla / yapay zekâ ile seçimi, sözlük ve elemeler aynen geçerlidir.
    func altyaziyiBaslat() {
        // Deneme: konsolsuz görünüş denemesi için örnek konuşma (uydurma replikler, oyun ve karakter adı yok).
        if ProcessInfo.processInfo.arguments.contains("-altyaziOnizleme") && satirlar.isEmpty {
            satirlar = Onizleme.replikler.enumerated().map { Satir(id: $0.offset + 1, konusan: nil, metin: $0.element, renk: $0.offset % 2) }
        }
        Pipeline.main?.onKonsolResult = { [weak self] r in self?.cevrildi(r) }
        cevirmen = CloudTranslator.enabled ? "bulut" : "telefon"
        proNotu = false; paketEksik = false; ucretsizBitti = false   // altyazı ekranı 2 sn içinde gerçek durumu koyar
        altyaziBas = Date(); replikSayisi = [:]
        Analiz.olay("altyazi_acildi", ["ornek_kipi": ornekKipi, "ceviri_yolu": cevirmen == "bulut" ? "yapay_zeka" : "telefon", "bagli": durum == .bagli,
                                       "pro_durumu": MainActor.assumeIsolated { ProMagaza.shared.satinAlinmis ? "abone" : (ProMagaza.shared.denemede ? "deneme" : "yok") }])
        if ornekKipi {
            ornekBesle()
            ornekZamanlayici = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.ornekBesle() }
            }
            return
        }
        okumaAcik = true
        yaz("altyazı okuma açık")
    }

    /// Altyazı açıkken uygulama arka plana geçerse ya da kapanırsa özet kaybolmasın: o ana kadarkini gönder, sayacı sıfırla.
    func altyaziOzetiGonder() {
        guard altyaziBas != nil else { return }
        let acikti = okumaAcik || ornekKipi
        altyaziOzeti()
        if acikti { altyaziBas = Date(); replikSayisi = [:] }
    }

    private func altyaziOzeti() {
        if let bas = altyaziBas {
            Analiz.olay("altyazi_kapandi", ["sure_sn": Int(Date().timeIntervalSince(bas)), "ornek_kipi": ornekKipi,
                                            "replik": replikSayisi.values.reduce(0, +), "replik_yapay_zeka": replikSayisi["bulut"] ?? 0,
                                            "replik_telefon": replikSayisi["telefon"] ?? 0, "pro_gerekli": proNotu, "paket_eksik": paketEksik,
                                            "gosterilemez": gosterilemez])
            altyaziBas = nil
        }
    }

    func altyaziyiDurdur() {
        altyaziOzeti()
        okumaAcik = false
        Pipeline.main?.onKonsolResult = nil
        ornekZamanlayici?.invalidate(); ornekZamanlayici = nil
        ornekKipi = false
    }

    #if DEBUG
    /// Yalnız deneme derlemesi: telefon ve yapay zekâ çevirisini karşılaştırmak için (Selim, 2026-11-17).
    /// Documents/ceviri_kaydi.tsv: saat, çeviren, süre ms, İngilizce aslı, çeviri. Mağaza sürümünde yok.
    private func cevirKaydi(_ r: Pipeline.Result) {
        guard let klasor = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = klasor.appendingPathComponent("ceviri_kaydi.tsv")
        let saat = ISO8601DateFormatter().string(from: Date())
        let temiz = { (s: String) in s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
        let satir = [saat, r.engine.hasPrefix("bulut") ? "yapay_zeka" : "telefon", String(Int(r.translateMs)),
                     temiz(r.original), temiz((r.speaker.map { $0 + ": " } ?? "") + r.translated)].joined(separator: "\t") + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(satir.utf8)); try? h.close()
        } else {
            try? ("saat\tceviren\tms\taslı\tceviri\n" + satir).write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif

    #if DEBUG
    private var sonResimMetni = ""
    private var sonResimZamani = 0.0
    /// Yalnız deneme derlemesi (Selim, 2026-11-19: "sarı ile çizilen alanın resmini çeksin kaydetsin, 20-30 replik
    /// toplayalım"): okunan kutunun görüntüsü ve Vision'ın gördüğü satırlar ayrı ayrı saklanır; oyunun konuşanları
    /// nasıl ayırdığına (ayrı satır, renk, tire) bakmak için. Documents/kutu2/<saat>.jpg + kutu2/liste.tsv. En çok 300 resim (ilk 79 resim eski kutu/ klasöründe).
    /// Okuma kuyruğunda çağrılır. Mağaza sürümünde yok.
    private func kutuResmiKaydet(_ image: CIImage, satirlar: [String]) {
        let metin = MetinOkuyucu.sade(satirlar.joined(separator: " "))
        let simdi = Date().timeIntervalSince1970
        guard metin.count >= 6, metin != sonResimMetni, simdi - sonResimZamani > 1.0,
              let kok = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let klasor = kok.appendingPathComponent("kutu3", isDirectory: true)
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let var_ = (try? FileManager.default.contentsOfDirectory(atPath: klasor.path))?.filter { $0.hasSuffix(".jpg") }.count ?? 0
        guard var_ < 300, let renk = CGColorSpace(name: CGColorSpace.sRGB),
              let veri = ci.jpegRepresentation(of: image, colorSpace: renk) else { return }
        sonResimMetni = metin; sonResimZamani = simdi
        let b = DateFormatter(); b.dateFormat = "HHmmss_SSS"
        let ad = b.string(from: Date()) + ".jpg"
        try? veri.write(to: klasor.appendingPathComponent(ad))
        let satir = ad + "\t" + satirlar.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: " ⏎ ") + "\n"
        let liste = klasor.appendingPathComponent("liste.tsv")
        if let h = try? FileHandle(forWritingTo: liste) { h.seekToEndOfFile(); h.write(Data(satir.utf8)); try? h.close() }
        else { try? satir.write(to: liste, atomically: true, encoding: .utf8) }
    }
    #endif

    // MARK: Konsolsuz örnek (App Store incelemecisi ve konsolu yanında olmayan kullanıcı için)
    /// Açıkken altyazı ekranı, uydurma İngilizce replikleri birkaç saniyede bir gerçek çeviri hattından
    /// geçirir: telefonla ya da yapay zekâ ile çeviri aynen çalışır, yalnız kaynak konsol değil.
    @Published var ornekKipi = false
    private var ornekZamanlayici: Timer?
    private var ornekSira = 0

    func ornegiHazirla() {
        satirlar = []; sonKaynak = ""; adRenkleri = [:]
        ornekKipi = true
        ornekSira = 0
    }

    private func ornekBesle() {
        let metin = Onizleme.ornekIngilizce[ornekSira % Onizleme.ornekIngilizce.count]
        ornekSira += 1
        Pipeline.main?.handle(text: metin, capturedAt: Date().timeIntervalSince1970, ocrMs: 0, place: "konsol")
    }

    private func cevrildi(_ r: Pipeline.Result) {
        guard r.place == "konsol" else { return }
        if r.proGerekli { proNotu = true }   // bu oturumda kalıcı: Pro bitti, telefonla çevriliyor
        // Çeviri yapılamadıysa (ör. telefonda dil paketi yok) sessiz kalma: altyazı ekranının altına yaz.
        if let hata = r.error {
            if hata == Pipeline.ucretsizBittiHatasi { ucretsizBitti = true; return }   // altyazı ekranı kartı gösterir
            if hata == L("Dil paketi indirilmemiş") { paketEksik = true }
            sonSure = L("Çeviri yapılamadı. Ayarlar'a bak.") + " (\(hata))"; return
        }
        guard !r.translated.isEmpty else { return }
        #if DEBUG
        cevirKaydi(r)
        #endif
        paketEksik = false
        cevirmen = r.engine.hasPrefix("bulut") ? "bulut" : "telefon"
        // Aynı satırın düzeltilmiş okuması yeni satır açmaz, eskisinin yerine geçer.
        let a = MetinOkuyucu.sade(r.original), b = MetinOkuyucu.sade(sonKaynak)
        let ayni = !b.isEmpty && (a.contains(b) || b.contains(a) || a.prefix(14) == b.prefix(14))
        sonKaynak = r.original
        let renk: Int
        if let ad = r.speaker {
            if adRenkleri[ad] == nil { adRenkleri[ad] = adRenkleri.count % 3 }
            renk = adRenkleri[ad] ?? 0
        } else if ayni, let son = satirlar.last {
            renk = son.renk
        } else {
            renk = ((satirlar.last?.renk ?? 1) + 1) % 2   // adsız oyunda replikler sırayla iki renk
        }
        if ayni, !satirlar.isEmpty {
            satirlar[satirlar.count - 1].metin = r.translated
            satirlar[satirlar.count - 1].konusan = r.speaker
        } else {
            siradakiId += 1
            replikSayisi[cevirmen, default: 0] += 1
            if !ornekKipi { Analiz.birKez("ilk_ceviri", ["ceviren": cevirmen]) }
            satirlar.append(Satir(id: siradakiId, konusan: r.speaker, metin: r.translated, renk: renk))
            if satirlar.count > 60 { satirlar.removeFirst(satirlar.count - 60) }   // geriye kaydırıp okumak için
        }
        sonSure = "okuma \(Int(r.ocrMs)) ms · çeviri \(Int(r.translateMs)) ms (\(r.engine))"
    }

    /// Çözücünün iş parçacığında: saniyede en çok 4 kare okunur, biri bitmeden öbürü başlamaz.
    private func oku(_ buffer: CVPixelBuffer) {
        let now = Date().timeIntervalSince1970
        guard okumaAcik || kutuAyari, !okuyor, now - sonOkuma > 0.25 else { return }
        okuyor = true
        sonOkuma = now
        okumaKuyrugu.async { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            // Kare zaten düz ve yatay geliyor: yön düzeltmesi, siyah şerit denetimi gerekmez.
            let image = MetinOkuyucu.kutu(of: buffer, box: Kutu.kayitli)
            let satirlar = MetinOkuyucu.satirlar(image, context: self.ci)
            let text = MetinOkuyucu.altyaziSatirlari(satirlar).joined(separator: " ")
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            #if DEBUG
            if self.okumaAcik { self.kutuResmiKaydet(image, satirlar: satirlar) }
            #endif
            self.okuyor = false
            DispatchQueue.main.async {
                if self.kutuAyari { self.sonOkunan = text; return }
                Pipeline.main?.handle(text: text, capturedAt: now, ocrMs: ms, place: "konsol")
            }
        }
    }

    // MARK: PSN hesap numarası ve kayıt anahtarları

    /// PSN hesap numarası (base64, 8 bayt). Şimdilik kurulumda "-psnHesap <değer>" ile bir kez verilir;
    /// üründe Sony'nin kendi giriş sayfasından alınacak.
    var hesapNo: String {
        get { UserDefaults.standard.string(forKey: "psnHesap") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "psnHesap") }
    }

    func adoptLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-psnHesap"), i + 1 < args.count { hesapNo = args[i + 1] }
        // Deneme için: saklı PSN hesap numarasını siler, böylece giriş ekranı yeniden çıkar.
        if args.contains("-psnCikis") { hesapNo = ""; UserDefaults.standard.removeObject(forKey: "psnAd") }
    }

    /// Kayıtta PS5'in verdiği iki anahtar. Gizlidir: Anahtar Zinciri'nde durur, kayda yazılmaz.
    var kayitli: Bool { Kasa.oku("ps5RegistKey") != nil && Kasa.oku("ps5RpKey") != nil }

    func kaydiSil() {
        Kasa.sil("ps5RegistKey"); Kasa.sil("ps5RpKey")
        yaz("kayıt silindi")
        objectWillChange.send()
    }

    // MARK: Bulma

    func aramayiBaslat() {
        guard discovery == nil else { return }
        _ = chiaki_session_bridge_init()
        bulunduBildirildi = false
        Analiz.olay("konsol_arama_basladi", ["eslesmis": kayitli])
        discovery = PyluxDiscoveryService { [weak self] found in
            guard let self else { return }
            self.hosts = found.filter { $0.hostAddr != nil }
            if !self.hosts.isEmpty && !self.bulunduBildirildi {
                self.bulunduBildirildi = true
                Analiz.olay("konsol_bulundu", ["sayi": self.hosts.count, "ps5": self.hosts.contains { $0.isPS5 }])
            }
        }
        yaz("ağda PS5 aranıyor")
    }

    func aramayiDurdur() {
        discovery?.shutdown()
        discovery = nil
    }

    // MARK: Kayıt (bir kez; PS5'te Ayarlar > Sistem > Uzaktan Oynama > Cihaz Bağla ekranındaki 8 haneli kod)

    func kaydol(host: PyluxDiscoveredHost, pin: String) {
        guard let addr = host.hostAddr else { return }
        guard let account = Data(base64Encoded: hesapNo), account.count == 8 else {
            yaz("PSN hesap numarası yok ya da bozuk"); return
        }
        guard let code = UInt32(pin.filter(\.isNumber)), pin.filter(\.isNumber).count == 8 else {
            yaz("kod 8 haneli olmalı"); return
        }
        let info = PyluxRegistInfo()
        info.target = host.isPS5 ? .PS5 : .PS4_GE8
        info.host = addr
        info.broadcast = false
        info.psnAccountId = account
        info.pin = code
        durum = .kaydoluyor
        eslesmeHatasi = false
        Analiz.olay("eslesme_basladi", ["ps5": host.isPS5])
        yaz("kayıt isteği gönderildi: \(addr)")
        regist = PyluxRegistService(info: info) { [weak self] result, data, _ in
            guard let self else { return }
            self.regist = nil
            if result == .success, let data {
                Kasa.yaz("ps5RegistKey", data.rpRegistKey)
                Kasa.yaz("ps5RpKey", data.rpKey)
                self.yaz("KAYIT TAMAM: \(data.serverNickname ?? "PS5")")
                Analiz.olay("eslesme_tamam")
                self.eslesmeHatasi = false
            } else {
                self.eslesmeHatasi = result != .canceled
                Analiz.olay("eslesme_hata", ["iptal": result == .canceled])
                self.yaz(result == .canceled ? "kayıt iptal" : "KAYIT OLMADI (kod yanlış ya da süresi dolmuş olabilir)")
            }
            self.durum = .bos
        }
    }

    // MARK: Bağlanma

    /// Eşleştirmede saklanan anahtardan "uyan" paketinin kimliği: anahtarın içeriği onaltılık yazı (Pylux HostModels.swift ile aynı).
    private var uyandirmaKimligi: UInt64? {
        guard let key = Kasa.oku("ps5RegistKey") else { return nil }
        let yazi = String(decoding: key.prefix(while: { $0 != 0 }), as: UTF8.self)
        return UInt64(yazi, radix: 16)
    }

    /// Bağlan: konsol uykudaysa önce uyandır, hazır olunca bağlan; az önce oturum bittiyse birkaç saniye bekle.
    func baglan(host: PyluxDiscoveredHost) {
        guard session == nil, !uyandiriliyor, host.hostAddr != nil else { return }
        baglantiHatasi = ""
        let bekle = max(0, 4 - Date().timeIntervalSince(sonBitis))
        if host.state == .ready {
            if bekle > 0 {
                durum = .baglaniyor
                DispatchQueue.main.asyncAfter(deadline: .now() + bekle) { [weak self] in
                    guard let self else { return }
                    if self.durum == .baglaniyor { self.durum = .bos }
                    self.baglanSimdi(host: self.guncel(host) ?? host)
                }
            } else {
                baglanSimdi(host: host)
            }
            return
        }
        // Uykuda: uyan paketi, sonra konsol "hazır" diyene kadar en çok 20 sn bekle (45 sn uzundu: ağdan açma ayarı kapalı
        // konsolda kullanıcı boşuna bekliyordu, Selim 2026-11-23). Kullanıcı PS tuşuyla açarsa da hazır olunca bağlanır.
        guard let addr = host.hostAddr, let kimlik = uyandirmaKimligi else { baglanSimdi(host: host); return }
        uyandiriliyor = true
        Analiz.olay("konsol_uyandirma", ["ps5": host.isPS5])
        yaz("konsol uykuda, uyandırılıyor: \(addr)")
        let basla = Date()
        func dene() {
            PyluxDiscoveryService.wakeupHost(addr, credential: kimlik, ps5: host.isPS5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.uyandiriliyor else { return }
                if let h = self.guncel(host), h.state == .ready {
                    self.uyandiriliyor = false
                    Analiz.olay("konsol_uyandi", ["sn": Int(Date().timeIntervalSince(basla))])
                    // Uyanan konsolun Uzaktan Oynama servisi birkaç saniye geç açılıyor.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.baglanSimdi(host: h) }
                } else if Date().timeIntervalSince(basla) > 20 {
                    self.uyandiriliyor = false
                    Analiz.olay("konsol_uyanmadi")
                    self.baglantiHatasi = L("Konsol uyanmadı. Kumandadaki PS tuşuyla aç, sonra yeniden bağlan.") + " "
                        + L("Bir dahakine kendiliğinden uyanması için PS5'te: Ayarlar > Sistem > Güç Tasarrufu > Dinlenme Modunda Kullanılabilen Özellikler > Ağdan PS5'i Açmayı Etkinleştir.")
                } else {
                    dene()
                }
            }
        }
        dene()
    }

    /// Aramadaki en güncel hâli (durum: hazır / uykuda).
    private func guncel(_ host: PyluxDiscoveredHost) -> PyluxDiscoveredHost? {
        hosts.first { $0.hostId != nil && $0.hostId == host.hostId } ?? hosts.first { $0.hostAddr == host.hostAddr }
    }

    private func baglanSimdi(host: PyluxDiscoveredHost) {
        guard session == nil, let addr = host.hostAddr else { return }
        gosterilemez = false
        guard let registKey = Kasa.oku("ps5RegistKey"), let rpKey = Kasa.oku("ps5RpKey") else {
            yaz("önce kayıt gerekli"); return
        }
        let account = Data(base64Encoded: hesapNo) ?? Data(count: 8)
        _ = chiaki_session_bridge_init()

        // 720p yeter: altyazı okumak için, sabahki ekran okuma 888x500 karede çalışıyordu.
        let width: UInt32 = 1280, height: UInt32 = 720
        let decoder = PyluxVideoDecoder(width: Int32(width), height: Int32(height), codec: .H264)
        decoder.frameCallback = { [weak self] buffer, _ in self?.kare(buffer) }

        let receiver = SessionEventReceiver()
        receiver.eventBlock = { [weak self] ptr in
            guard let ptr else { return }
            let event = ptr.assumingMemoryBound(to: ChiakiSessionBridgeEvent.self).pointee
            // quit_reason_str çoğu zaman boş geliyordu (PostHog'da 1.808 hatanın hepsinde neden ""); kodu ve kütüphanenin
            // kendi açıklamasını da al.
            let ek = event.quit_reason_str.map { String(cString: $0) } ?? ""
            let kod = Int(event.quit_reason)
            let ad = String(cString: chiaki_session_bridge_quit_reason_string(Int32(event.quit_reason)))
            let reason = ek.isEmpty ? ad : ek
            DispatchQueue.main.async { self?.olay(event.type, reason: reason, kod: kod, pinYanlis: event.login_pin_incorrect) }
        }

        var info = ChiakiSessionBridgeConnectInfo()
        var err: Int32 = 0
        let ref: ChiakiSessionRef? = addr.withCString { hostPtr in
            info.host = hostPtr
            info.ps5 = host.isPS5
            info.video_width = width
            info.video_height = height
            info.video_max_fps = 30
            info.video_bitrate = 10_000
            info.video_codec = 0
            info.enable_dualsense = false
            info.auto_regist = false
            info.service_type = 0
            _ = withUnsafeMutableBytes(of: &info.regist_key) { registKey.copyBytes(to: $0, count: min(16, registKey.count)) }
            _ = withUnsafeMutableBytes(of: &info.morning) { rpKey.copyBytes(to: $0, count: min(16, rpKey.count)) }
            _ = withUnsafeMutableBytes(of: &info.psn_account_id) { account.copyBytes(to: $0, count: min(8, account.count)) }
            return withUnsafeMutablePointer(to: &info) {
                chiaki_session_bridge_create($0, pylux_session_event_callback, receiver.retainedOpaquePointer(), &err)
            }
        }
        guard let ref else {
            receiver.invalidate()
            yaz("oturum açılamadı: \(String(cString: chiaki_session_bridge_error_string(err)))")
            Analiz.olay("baglanti_hata", ["asama": "olustur", "kod": Int(err)])
            return
        }
        self.decoder = decoder
        self.receiver = receiver
        self.session = ref
        sayac = 0
        kareSayisi = 0
        chiaki_session_bridge_set_video_sample_cb(ref, PyluxVideoDecoderVideoSampleCallback, Unmanaged.passUnretained(decoder).toOpaque())

        let started = chiaki_session_bridge_start(ref)
        guard started == 0 else {
            session = nil; self.decoder = nil; self.receiver = nil
            chiaki_session_bridge_free(ref)
            receiver.invalidate()
            yaz("oturum başlamadı: \(String(cString: chiaki_session_bridge_error_string(started)))")
            Analiz.olay("baglanti_hata", ["asama": "baslat", "kod": Int(started)])
            return
        }
        durum = .baglaniyor
        Analiz.olay("baglanti_basladi", ["ps5": host.isPS5])
        yaz("bağlanılıyor: \(addr)")

        // Oturum bitince (biz durdurunca ya da PS5 kapatınca) temizliği tek yerde yap.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = chiaki_session_bridge_join(ref)
            DispatchQueue.main.sync {
                guard let self else { return }
                self.session = nil
                self.decoder = nil
                self.receiver = nil
                self.gosterilemez = false
                if self.durum == .bagli || self.durum == .baglaniyor { self.durum = .bos }
            }
            chiaki_session_bridge_free(ref)
            receiver.invalidate()
        }
    }

    func kop() {
        guard let session else { return }
        yaz("bağlantı kapatılıyor")
        _ = chiaki_session_bridge_stop(session)
    }

    private func olay(_ type: ChiakiSessionBridgeEventType, reason: String, kod: Int = -1, pinYanlis: Bool) {
        switch type {
        case ChiakiSessionBridgeEventConnected:
            durum = .bagli
            Analiz.olay("baglandi")
            yaz("BAĞLANDI")
        case ChiakiSessionBridgeEventQuit:
            let bagliydi = durum == .bagli
            Analiz.olay(bagliydi ? "baglanti_koptu" : "baglanti_hata",
                        ["asama": "oturum", "neden": reason, "kod": kod, "arka_plan": UIApplication.shared.applicationState == .background])
            sonBitis = Date()
            if !bagliydi {
                baglantiHatasi = L("Konsol bağlantıyı kabul etmedi. PS5'te Uzaktan Oynama'nın açık olduğuna ve konsolun başka bir cihaza bağlı olmadığına bak; birkaç saniye sonra yeniden dene.")
            }
            durum = .koptu(reason)
            yaz("oturum bitti: \(reason)")
        case ChiakiSessionBridgeEventLoginPinRequest:
            Analiz.olay("konsol_pin_istedi", ["yanlis": pinYanlis])
            yaz(pinYanlis ? "PS5 giriş kodu yanlış" : "PS5 bu kullanıcı için giriş kodu istiyor (desteklenmiyor, kodsuz kullanıcı seç)")
        default:
            break
        }
    }

    /// Çözücünün iş parçacığında çağrılır.
    private func kare(_ buffer: CVPixelBuffer) {
        kareGeldi?(buffer)
        oku(buffer)
        sayac += 1
        let now = Date()
        guard now.timeIntervalSince(sonOnizleme) > (kutuAyari ? 0.15 : 0.5) else { return }
        sonOnizleme = now
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = ci.createCGImage(image, from: image.extent) else { return }
        let ui = UIImage(cgImage: cg)
        let count = sayac
        DispatchQueue.main.async {
            self.sonKare = ui
            self.kareSayisi = count
            self.kareBoyu = "\(w)x\(h)"
        }
    }

    private func yaz(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let text = "\(f.string(from: Date())) \(line)"
        if Thread.isMainThread { gunluk.append(text) } else { DispatchQueue.main.async { self.gunluk.append(text) } }
        NSLog("[konsol] %@", line)
    }
}

/// Anahtar Zinciri: kayıt anahtarları burada durur, yedeğe ve başka cihaza gitmez.
enum Kasa {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.selimbagdatli.subsy.konsol",
         kSecAttrAccount as String: key]
    }

    static func yaz(_ key: String, _ value: Data) {
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = value
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func oku(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func sil(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
