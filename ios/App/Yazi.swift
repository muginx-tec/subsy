import Foundation

/// Uygulamanın kendi yazıları iOS'un standart çeviri düzeniyle çevrilir (String Catalog:
/// `Localizable.xcstrings`). Kaynak dil Türkçe: kodda yazı Türkçe durur, `L("...")` karşılığını bulur.
/// Katalog elle düzenlenmez: `ceviri/olustur.py` onu `ceviri/` klasöründeki dil dosyalarından üretir.
///
/// Hangi dil: kullanıcı uygulamanın içinden (ana sayfanın sağ üstü ya da Ayarlar) bir dil seçtiyse o;
/// seçmediyse telefonun dili. Uygulama içi seçim anında geçerli olur, yeniden açmak gerekmez.
enum ArayuzDili {
    static let anahtar = "arayuzDili"

    /// Kullanıcının uygulama içinden seçtiği dil kodu; seçmediyse nil.
    static var secilen: String? {
        get { UserDefaults.standard.string(forKey: anahtar) }
        set { UserDefaults.standard.set(newValue, forKey: anahtar); paket = nil }
    }

    /// Şu an geçerli arayüz dili sağdan sola mı (Arapça).
    static var sagdanSola: Bool {
        let kod = secilen ?? (Bundle.main.preferredLocalizations.first ?? "tr")
        return kod.hasPrefix("ar")
    }

    private static var paket: Bundle?
    fileprivate static func cevir(_ tr: String) -> String {
        guard let kod = secilen else { return NSLocalizedString(tr, comment: "") }   // telefonun dili
        if kod == "tr" { return tr }                                                   // kaynak dil
        if paket == nil, let yol = Bundle.main.path(forResource: kod, ofType: "lproj") { paket = Bundle(path: yol) }
        return paket?.localizedString(forKey: tr, value: tr, table: nil) ?? tr
    }
}

func L(_ tr: String) -> String { ArayuzDili.cevir(tr) }
