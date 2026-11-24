import UIKit
import GoogleMobileAds
import UserMessagingPlatform

/// Ödüllü video (AdMob): ücretsiz süresi biten kullanıcı isterse bir video izler, 30 dakika daha telefon çevirisi alır
/// (Selim, 2026-11-23: "tüm Arapça diller için yapıyoruz reklamı ve 30 dk"). Video yalnız kullanıcı "Video izle"ye basınca
/// açılır; oyunun ortasında kendiliğinden reklam yok. Kütüphane yalnız sınırın geçerli olduğu kullanıcıda (Arapça altyazı,
/// Pro / deneme yok) başlatılır; öbür kullanıcılarda Google'a hiçbir şey gitmez.
/// AB'deki kullanıcı için önce Google'ın onay penceresi (UMP); onay verilmezse Google kişiye özel olmayan reklam gösterir.
@MainActor
final class OdulluReklam: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = OdulluReklam()
    /// Video başına verilen ek süre.
    static let dakika = 30

    #if DEBUG
    /// Google'ın herkese açık deneme birimi: deneme derlemesinde gerçek reklam çekilmez (AdMob kuralı).
    private static let birim = "ca-app-pub-3940256099942544/1712485313"
    #else
    /// "Ucretsiz sure" ödüllü birimi (AdMob, 2026-11-23).
    private static let birim = "ca-app-pub-2313615411520331/2430234433"
    #endif

    @Published private(set) var hazir = false
    @Published private(set) var yukleniyor = false
    private var reklam: RewardedAd?
    private var basladi = false
    private var odulVerildi = false

    /// İlk çağrıda onay penceresi (gerekirse) ve kütüphane başlatılır, sonra bir video önceden yüklenir.
    func hazirla() {
        if basladi { if reklam == nil && !yukleniyor && Date() >= sonrakiDeneme { yukle() }; return }
        basladi = true
        UserDefaults.standard.set(true, forKey: "reklamOnayIstendi")
        ConsentInformation.shared.requestConsentInfoUpdate(with: nil) { [weak self] _ in
            Task { @MainActor in
                self?.gizlilikDurumunuOku()
                ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                    Task { @MainActor in
                        self?.gizlilikDurumunuOku()
                        guard let self, ConsentInformation.shared.canRequestAds else { return }
                        MobileAds.shared.start(completionHandler: nil)
                        self.yukle()
                    }
                }
            }
        }
    }

    // MARK: Gizlilik seçenekleri (2026-11-24, AdMob'da AB onay mesajı yayımlandı; Google ve GDPR, kullanıcının onayını
    // sonradan değiştirebileceği görünür bir giriş istiyor). Ayarlar'da yalnız UMP "gerekli" derse görünür.

    /// Onay penceresinin yeniden açılması bu kullanıcı için gerekli mi (AB/BK). Onay bilgisi okunmadıysa false.
    @Published private(set) var gizlilikGerekli = false

    /// Ayarlar açılınca: kullanıcı daha önce Google'ın onay akışından geçtiyse (sonradan Pro olmuş olsa da) durumu tazele.
    /// Hiç geçmediyse Google'a hiçbir şey gitmez.
    func gizlilikDurumunuYenile() {
        guard UserDefaults.standard.bool(forKey: "reklamOnayIstendi") else { return }
        ConsentInformation.shared.requestConsentInfoUpdate(with: nil) { [weak self] _ in
            Task { @MainActor in self?.gizlilikDurumunuOku() }
        }
    }

    private func gizlilikDurumunuOku() {
        gizlilikGerekli = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Google'ın gizlilik seçenekleri penceresini açar; kullanıcı onayını değiştirebilir.
    func gizlilikSecenekleri() {
        Analiz.olay("gizlilik_secenekleri")
        ConsentForm.presentPrivacyOptionsForm(from: Self.enUstEkran()) { [weak self] _ in
            Task { @MainActor in self?.gizlilikDurumunuOku() }
        }
    }

    // Başarısız yüklemeden sonra üstel geri çekilme (2026-11-24): altyazı ekranı 2 sn'de bir hazirla() çağırıyor; video
    // gelmeyen bir kullanıcıda (Katar, 3 dk'da 14 istek) boşa istek AdMob'da gösterim oranını düşürüyordu.
    // 30 sn, 60, 120... en çok 10 dk; başarılı yüklemede sıfırlanır. Kullanıcı düğmeye basınca beklemeden denenir.
    private var basarisiz = 0
    private var sonrakiDeneme = Date.distantPast

    /// "Video izle"ye basıldı ama video hazır değil: geri çekilmeyi beklemeden bir kez dene.
    func simdiYukle() {
        guard basladi, reklam == nil, !yukleniyor else { return }
        Analiz.olay("reklam_elle_yukle")
        yukle()
    }

    private func yukle() {
        guard !yukleniyor else { return }
        yukleniyor = true
        RewardedAd.load(with: Self.birim, request: Request()) { [weak self] ad, hata in
            Task { @MainActor in
                guard let self else { return }
                self.yukleniyor = false
                self.reklam = ad
                self.reklam?.fullScreenContentDelegate = self
                self.hazir = ad != nil
                if let hata = hata as NSError? {
                    self.basarisiz += 1
                    let bekle = min(600.0, 30.0 * pow(2.0, Double(self.basarisiz - 1)))
                    self.sonrakiDeneme = Date().addingTimeInterval(bekle)
                    Analiz.olay("reklam_yuklenemedi", ["kod": hata.code, "alan": hata.domain, "deneme": self.basarisiz])
                } else if ad != nil {
                    self.basarisiz = 0; self.sonrakiDeneme = .distantPast
                }
            }
        }
    }

    /// Videoyu açar; kullanıcı ödülü hak ederse `odul` çağrılır. Video hazır değilse hiçbir şey olmaz.
    func goster(odul: @escaping () -> Void) {
        guard let reklam else { yukle(); return }
        odulVerildi = false
        Analiz.olay("reklam_acildi")
        // En üstteki ekrandan aç (altyazı ekranı tam ekran olarak açık): nil verince Google kök ekrandan açıyordu, altyazı ekranı
        // arkada kalıp bozuluyordu (tablette videodan sonra sayaç durdu, dil değişti; 2026-11-23).
        reklam.present(from: Self.enUstEkran()) { [weak self] in
            Task { @MainActor in
                guard let self, !self.odulVerildi else { return }
                self.odulVerildi = true
                Analiz.olay("reklam_odul", ["dakika": Self.dakika])
                odul()
            }
        }
    }

    private static func enUstEkran() -> UIViewController? {
        let pencere = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        var ust = pencere?.rootViewController
        while let sonraki = ust?.presentedViewController { ust = sonraki }
        return ust
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in
            self.reklam = nil; self.hazir = false
            self.yukle()   // sonraki için bir sonrakini hazırla
        }
    }

    nonisolated func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        let e = error as NSError
        Task { @MainActor in
            Analiz.olay("reklam_gosterilemedi", ["kod": e.code, "alan": e.domain])
            self.reklam = nil; self.hazir = false
            self.yukle()
        }
    }
}
