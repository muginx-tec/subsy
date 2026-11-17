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

    enum Durum: Equatable { case bos, kaydoluyor, baglaniyor, bagli, koptu(String) }

    @Published var hosts: [PyluxDiscoveredHost] = []
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

    func altyaziyiDurdur() {
        okumaAcik = false
        Pipeline.main?.onKonsolResult = nil
        ornekZamanlayici?.invalidate(); ornekZamanlayici = nil
        ornekKipi = false
    }

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
        proNotu = r.proGerekli
        // Çeviri yapılamadıysa (ör. telefonda dil paketi yok) sessiz kalma: altyazı ekranının altına yaz.
        if let hata = r.error { sonSure = L("Çeviri yapılamadı. Ayarlar'a bak.") + " (\(hata))"; return }
        guard !r.translated.isEmpty else { return }
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
            let text = MetinOkuyucu.oku(image, context: self.ci)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
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
        discovery = PyluxDiscoveryService { [weak self] found in
            self?.hosts = found.filter { $0.hostAddr != nil }
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
        yaz("kayıt isteği gönderildi: \(addr)")
        regist = PyluxRegistService(info: info) { [weak self] result, data, _ in
            guard let self else { return }
            self.regist = nil
            if result == .success, let data {
                Kasa.yaz("ps5RegistKey", data.rpRegistKey)
                Kasa.yaz("ps5RpKey", data.rpKey)
                self.yaz("KAYIT TAMAM: \(data.serverNickname ?? "PS5")")
            } else {
                self.yaz(result == .canceled ? "kayıt iptal" : "KAYIT OLMADI (kod yanlış ya da süresi dolmuş olabilir)")
            }
            self.durum = .bos
        }
    }

    // MARK: Bağlanma

    func baglan(host: PyluxDiscoveredHost) {
        guard session == nil, let addr = host.hostAddr else { return }
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
            let reason = event.quit_reason_str.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async { self?.olay(event.type, reason: reason, pinYanlis: event.login_pin_incorrect) }
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
            return
        }
        durum = .baglaniyor
        yaz("bağlanılıyor: \(addr)")

        // Oturum bitince (biz durdurunca ya da PS5 kapatınca) temizliği tek yerde yap.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = chiaki_session_bridge_join(ref)
            DispatchQueue.main.sync {
                guard let self else { return }
                self.session = nil
                self.decoder = nil
                self.receiver = nil
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

    private func olay(_ type: ChiakiSessionBridgeEventType, reason: String, pinYanlis: Bool) {
        switch type {
        case ChiakiSessionBridgeEventConnected:
            durum = .bagli
            yaz("BAĞLANDI")
        case ChiakiSessionBridgeEventQuit:
            durum = .koptu(reason)
            yaz("oturum bitti: \(reason)")
        case ChiakiSessionBridgeEventLoginPinRequest:
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
