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
        if basladi { if reklam == nil && !yukleniyor { yukle() }; return }
        basladi = true
        ConsentInformation.shared.requestConsentInfoUpdate(with: nil) { [weak self] _ in
            Task { @MainActor in
                ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                    Task { @MainActor in
                        guard let self, ConsentInformation.shared.canRequestAds else { return }
                        MobileAds.shared.start(completionHandler: nil)
                        self.yukle()
                    }
                }
            }
        }
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
                if hata != nil { Analiz.olay("reklam_yuklenemedi") }
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
        Task { @MainActor in
            Analiz.olay("reklam_gosterilemedi")
            self.reklam = nil; self.hazir = false
            self.yukle()
        }
    }
}
