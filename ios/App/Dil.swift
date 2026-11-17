import Foundation

/// Altyazının çevrileceği dil. Liste: GTA 6'nın altyazı vermediği, pazarı büyük diller (DURUM.md bölüm 3).
/// Telefonun hazır çevirisi hepsini desteklemeyebilir; desteklemediğini uygulama çalışırken sorar
/// (`Translator.state`). Yapay zekâ ile çeviri hepsinde çalışır.
struct Dil: Identifiable, Equatable {
    let kod: String        // "tr", "ar", "id"...
    let ad: String         // dilin kendi adı; seçim listesinde böyle görünür
    let turkce: String     // kayıt ve geliştirici için
    let sagdanSola: Bool
    var id: String { kod }
}

enum Diller {
    static let hepsi: [Dil] = [
        Dil(kod: "tr", ad: "Türkçe", turkce: "Türkçe", sagdanSola: false),
        Dil(kod: "ar", ad: "العربية", turkce: "Arapça", sagdanSola: true),
        Dil(kod: "id", ad: "Bahasa Indonesia", turkce: "Endonezce", sagdanSola: false),
        Dil(kod: "hi", ad: "हिन्दी", turkce: "Hintçe", sagdanSola: false),
        Dil(kod: "th", ad: "ไทย", turkce: "Tayca", sagdanSola: false),
        Dil(kod: "vi", ad: "Tiếng Việt", turkce: "Vietnamca", sagdanSola: false),
        Dil(kod: "nl", ad: "Nederlands", turkce: "Felemenkçe", sagdanSola: false),
        Dil(kod: "uk", ad: "Українська", turkce: "Ukraynaca", sagdanSola: false),
        Dil(kod: "el", ad: "Ελληνικά", turkce: "Yunanca", sagdanSola: false),
        Dil(kod: "cs", ad: "Čeština", turkce: "Çekçe", sagdanSola: false),
        Dil(kod: "hu", ad: "Magyar", turkce: "Macarca", sagdanSola: false),
        Dil(kod: "sv", ad: "Svenska", turkce: "İsveççe", sagdanSola: false),
    ]

    static let anahtar = "hedefDil"

    /// Seçili dil. İlk açılışta telefonun dili listedeyse o, değilse Türkçe.
    static var secili: Dil {
        get {
            if let kod = UserDefaults.standard.string(forKey: anahtar), let d = hepsi.first(where: { $0.kod == kod }) { return d }
            let telefon = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "tr"
            return hepsi.first(where: { $0.kod == telefon }) ?? hepsi[0]
        }
        set { UserDefaults.standard.set(newValue.kod, forKey: anahtar) }
    }
}
