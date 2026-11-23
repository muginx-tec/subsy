import Foundation

/// Ücretsiz (telefonla) çeviriye günlük süre sınırı (Selim, 2026-11-22: "ücretsize ya reklam ya saat olarak kısıtlayacağız",
/// "Suudi Arabistan ile başlayalım"). Neden: ücretsiz yolu olan ülkelerde (SA, TR) kimse Pro almıyor, olmayanlarda (HU, CZ) alıyor.
/// Yalnız listedeki altyazı dillerinde (bugün Arapça), Pro ya da deneme yokken geçerli. Süre saat gibi işler: altyazı ekranı açık ve konsol bağlıyken (Selim, 2026-11-23).
/// Her gün (telefonun yerel günü) sıfırlanır. Sayaç telefonda kalır, hiçbir yere gönderilmez.
/// Süre dolunca ödüllü video (OdulluReklam) ile 30 dakika daha (`ekDakika`).
enum UcretsizSure {
    /// Sınırın geçerli olduğu altyazı dilleri (Selim, 2026-11-23: "dili Arapça olan herkese yapalım"; önce yalnız Suudi mağazasıydı).
    /// Ülke yerine dil: Arapça oynayan her ülkede aynı durumda (telefon çevirisi Arapçayı destekliyor, bedava yol açık),
    /// ve dili değiştirerek atlatmak Arapça altyazıyı da kaybettirir. Sunucudan liste gelince bunun yerine o kullanılacak.
    static var diller: Set<String> = ["ar"]
    /// Günlük ücretsiz süre (Selim, 2026-11-23: "30 dk yapıyoruz"; önce 45).
    static var gunlukDakika: Int {
        #if DEBUG
        if let d = testDakika { return d }
        #endif
        return 30
    }

    #if DEBUG
    /// Deneme: `-sureDakika 3` ile günlük süre 3 dakika (Selim, 2026-11-23: "3 dk yap test edelim bitince ne olacak").
    /// Pro'su olan tablette de denensin diye Pro, dil ve çeviri yolu kontrolü atlanır; açılışta sayaç sıfırlanır.
    static let testDakika: Int? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-sureDakika"), i + 1 < a.count, let d = Int(a[i + 1]) else { return nil }
        return d
    }()
    #endif

    #if DEBUG
    private static var onizleme = false
    #endif

    static func yukle() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sureBittiOnizleme") { onizleme = true }
        if testDakika != nil {
            onizleme = true; ayarla(saniye: 0, ek: 0)
        }
        // Sayaç görünsün diye: 26 dakika kullanılmış (4 dakika kaldı, rozet turuncu).
        if ProcessInfo.processInfo.arguments.contains("-sureOnizleme") {
            onizleme = true; ayarla(saniye: 26 * 60, ek: 0)
        }
        #endif
    }

    /// Bu kullanıcıda sınır var mı.
    @MainActor static var gecerli: Bool {
        #if DEBUG
        if onizleme { return true }   // deneme açılışı: Pro'su olan cihazda da kart ve video denenebilsin
        #endif
        guard diller.contains(Diller.secili.kod) else { return false }
        // Abonelik bilgisi (RevenueCat) okunmadan sayaç işlemez: ödeyen kullanıcı yanlışlıkla kesilmesin (Selim, 2026-11-23: "okey").
        guard ProMagaza.shared.bilgiOkundu else { return false }
        return !ProMagaza.shared.aktif
    }

    private static var bugun: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Günün sayacı. Anahtar Zinciri'nde (Kasa) saklanır: uygulama silinip yeniden kurulsa da kalır, böylece silip kurarak
    /// sıfırlanamaz (Selim, 2026-11-23: "uygulamayı silip yüklersem?"). Bellekte tutulur; diske en çok 10 sn'de bir yazılır.
    private struct Kayit: Codable { var gun: String; var saniye: Double; var ek: Int }
    private static let kasaAnahtari = "ucretsizSure"
    private static var kayit: Kayit = {
        if let d = Kasa.oku(kasaAnahtari), let k = try? JSONDecoder().decode(Kayit.self, from: d) { return k }
        return Kayit(gun: bugun, saniye: 0, ek: 0)
    }()
    private static var sonYazim = Date.distantPast

    private static func kaydet(hemen: Bool = false) {
        guard hemen || Date().timeIntervalSince(sonYazim) > 10 else { return }
        sonYazim = Date()
        if let d = try? JSONEncoder().encode(kayit) { Kasa.yaz(kasaAnahtari, d) }
    }

    /// Altyazı ekranı kapanırken çağrılır: son birkaç saniye de yazılsın.
    static func simdiKaydet() { kaydet(hemen: true) }

    private static func gunuDenetle() {
        if kayit.gun != bugun { kayit = Kayit(gun: bugun, saniye: 0, ek: 0); kaydet(hemen: true) }
    }

    /// Bugün kullanılan ücretsiz süre (saniye).
    static var kullanilan: Double {
        gunuDenetle(); return kayit.saniye
    }

    /// Video izleyerek kazanılan ek dakika (bugün).
    static var ekDakika: Int {
        get { gunuDenetle(); return kayit.ek }
        set { gunuDenetle(); kayit.ek = newValue; kaydet(hemen: true) }
    }

    @MainActor static func ekle(saniye: Double) {
        guard gecerli else { return }
        gunuDenetle()
        kayit.saniye += saniye
        kaydet()
    }

    #if DEBUG
    fileprivate static func ayarla(saniye: Double, ek: Int) { gunuDenetle(); kayit.saniye = saniye; kayit.ek = ek; kaydet(hemen: true) }
    #endif

    /// Bugünkü ücretsiz süre doldu: telefonla çeviri yapılmaz.
    @MainActor static var bitti: Bool {
        guard gecerli else { return false }
        return kullanilan >= Double((gunlukDakika + ekDakika) * 60)
    }

    #if DEBUG
    static func doldur() { ayarla(saniye: Double(gunlukDakika * 60), ek: 0) }
    #endif
}
