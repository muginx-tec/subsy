import Foundation
import UIKit
import PostHog

/// Ürün analizi (PostHog, AB sunucusu). Selim, 2026-11-21: "insanları takip etmek istiyorum, kim girmiş kim nereden
/// çıkmış, kim telefon çevirisi kullanıyor, bu konuda körüz". Yalnız adımlar gider (konsol bulundu, eşleşti, bağlandı,
/// altyazı açıldı, deneme, satın alma...). Altyazı metni, PSN adı, konsol adresi gitmez. Ekran kaydı ve dokunuş
/// yakalama kapalı. Kimlik RevenueCat'tekiyle aynı rastgele UUID (`Kullanici.kimlik`). Anahtar `Config/Gizli.xcconfig`
/// (SUBSY_POSTHOG); boşsa hiçbir şey gönderilmez. Anahtar yalnız veri göndermeye yarar, okumaya yaramaz.
enum Analiz {
    private(set) static var acik = false

    static func baslat() {
        guard let anahtar = Bundle.main.object(forInfoDictionaryKey: "PostHogAnahtar") as? String,
              !anahtar.isEmpty, !anahtar.hasPrefix("$(") else { return }
        let c = PostHogConfig(projectToken: anahtar, host: "https://eu.i.posthog.com")
        c.captureApplicationLifecycleEvents = true   // kurulum, açılış, arka plana geçiş
        c.captureScreenViews = false
        c.enableSwizzling = false
        c.preloadFeatureFlags = false
        c.personProfiles = .always
        PostHogSDK.shared.setup(c)
        PostHogSDK.shared.identify(Kullanici.kimlik)
        // PostHog IP'den ilçe, posta kodu ve enlem-boylam çıkarıyordu (tablette görüldü, 2026-11-21); gizlilik sayfası
        // yalnız ülke diyor. IP'den konum çıkarma kapalı; ülke telefonun bölge ayarından gelir.
        var ortak: [String: Any] = ["altyazi_dili": Diller.secili.kod, "cihaz": UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
                                    "$geoip_disable": true, "ulke": Locale.current.region?.identifier ?? "?"]
        #if DEBUG
        ortak["deneme_derlemesi"] = true   // Selim'in ve simülatörün olayları süzülebilsin
        #endif
        PostHogSDK.shared.register(ortak)
        acik = true
    }

    static func olay(_ ad: String, _ ozellik: [String: Any] = [:]) {
        guard acik else { return }
        PostHogSDK.shared.capture(ad, properties: ozellik.isEmpty ? nil : ozellik)
    }

    /// Kurulum başına bir kez gönderilen olaylar (ilk çeviri gibi).
    static func birKez(_ ad: String, _ ozellik: [String: Any] = [:]) {
        let anahtar = "analizBirKez_" + ad
        guard acik, !UserDefaults.standard.bool(forKey: anahtar) else { return }
        UserDefaults.standard.set(true, forKey: anahtar)
        olay(ad, ozellik)
    }
}
