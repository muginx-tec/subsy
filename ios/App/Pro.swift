import FacebookCore
import RevenueCat
import StoreKit
import SwiftUI
import UIKit

/// Telefonun bize tanıttığı kalıcı kimlik: RevenueCat'te app_user_id, sunucuda X-Kullanici. Rastgele
/// bir UUID; kişisel bilgi taşımaz. Anahtar Zinciri'nde durur, uygulama silinip kurulsa da aynı kalır
/// (paylaşana 1 saat deneme kişi başı bir kez verilsin diye).
enum Kullanici {
    static let kimlik: String = {
        #if DEBUG
        // Yalniz deneme derlemesi: "-yeniKullanici" ile acilirsa kimlik yenilenir, uygulama hic kurulmamis
        // biri gibi davranir (2 saatlik deneme karti yeniden gorunur). Her kullanim RevenueCat'te yeni bir
        // musteri acar; sayilari kirletmemek icin yalniz gerektiginde kullan.
        if ProcessInfo.processInfo.arguments.contains("-yeniKullanici") {
            let yeni = UUID().uuidString.lowercased()
            Kasa.yaz("kullanici", Data(yeni.utf8))
            return yeni
        }
        #endif
        if let d = Kasa.oku("kullanici"), let s = String(data: d, encoding: .utf8), !s.isEmpty { return s }
        let yeni = UUID().uuidString.lowercased()
        Kasa.yaz("kullanici", Data(yeni.utf8))
        return yeni
    }()
}

/// Pro: uygulamanın ücretli paketi (yapay zekâ ile çeviri). Satın alma RevenueCat üzerinden Apple'ın
/// sistemiyle yapılır. **Asıl kilit sunucuda**: sunucu RevenueCat'e "bu kullanıcı Pro mu" diye sorar
/// (sunucu/sunucu.py). Telefondaki `aktif` yalnız ekranda ne gösterileceği içindir.
/// Fiyat kodda yazmaz: mağazadan, kullanıcının ülkesinin para birimiyle gelir.
@MainActor
final class ProMagaza: ObservableObject {
    static let shared = ProMagaza()

    /// RevenueCat'in AÇIK iOS anahtarı (appl_ ile başlar). Gizli değildir, uygulamada durması normaldir.
    /// Boşken RevenueCat hiç başlatılmaz ve ekran "Yakında" der. Selim RevenueCat projesini açınca doldurulacak.
    static let rcAnahtar = "appl_HZHRhPcKnbVQiKfGYvlErYJHMfU"   // RevenueCat projesi "Subsy" (679e5efb), 2026-11-17
    /// RevenueCat'teki yetki kimliği; sunucudaki GT_RC_YETKI ile aynı olmalı.
    static let yetki = "pro"
    /// Paylaşana 1 saat Pro. Kapalı (Selim, 2026-11-17: "Remove it from 1.0"): Apple 3.2.2 ödül karşılığı eylemi
    /// yasaklıyor, 1.0 incelemesini riske atmasın. Kod duruyor; onaydan sonra 1.1'de açılacak.
    static let paylasOdulu = false
    /// Paylaşım şartı olmadan, kişi başı bir kez 2 saatlik yapay zekâ denemesi (Selim, 2026-11-18:
    /// "2 saat deneme süresi", "bir paylaşım falan yapmadan koyalım"). Süreyi sunucu verir (GT_DENEME_SANIYE).
    static let ucretsizDeneme = true
    /// App Store Connect'te bu kimliklerle açılacak abonelikler (açmak Selim'in işi). RevenueCat'te
    /// "pro" yetkisine ve varsayılan teklife bağlanacaklar.
    /// App Store Connect'te açık (2026-11-17, "Subsy Pro" grubu): haftalık, aylık, yıllık.
    static let urunKimlikleri = ["com.selimbagdatli.subsy.pro.haftalik",
                                 "com.selimbagdatli.subsy.pro.aylik",
                                 "com.selimbagdatli.subsy.pro.yillik"]

    static func sureAdi(_ urunKimligi: String) -> String {
        if urunKimligi.hasSuffix("haftalik") { return L("Haftalık") }
        if urunKimligi.hasSuffix("yillik") { return L("Yıllık") }
        return L("Aylık")
    }

    @Published var paketler: [Package] = []
    @Published private(set) var satinAlinmis = false
    /// Aktif aboneliğin ürün kimliği (hangi paket alındı); yoksa nil.
    @Published private(set) var aktifUrun: String?
    /// Sunucunun verdiği deneme süresinin bitişi (paylaşana 1 saat). Yoksa nil.
    @Published var denemeBitis: Date?
    @Published var denemeKullanildi = false
    /// Sunucuda Pro kilidi açık mı. AÇIK başlar ve yalnız sunucu açıkça "kapalı" derse kapanır.
    /// Eskiden kapalı başlıyordu: sunucunun cevabı gelmeden (ya da istek düşünce) Pro olmayan kişi
    /// "Yapay zekâ ile çevir"i paket ekranı görmeden işaretleyebiliyordu (2026-11-18, mağaza sürümü 1.0).
    @Published var kilit = true
    @Published var mesaj = ""
    @Published var calisiyor = false
    /// Fiyatlar mağazadan gelene kadar true. Eskiden bu arada "Yakında / herkese açık" yazıyordu; incelemeci
    /// yavaş ağda bunu görürse yanıltıcı olur (mağaza oturumunun bulgusu, 2026-11-17).
    @Published var paketlerYukleniyor = true
    /// Şu an hangi işin beklendiği: paket kimliği, "geri" (geri yükleme) ya da "deneme". Düğmede dönen gösterge için.
    @Published var islenen: String?

    var denemede: Bool { (denemeBitis ?? .distantPast) > Date() }
    var aktif: Bool { satinAlinmis || denemede }
    /// Abonelik bilgisi RevenueCat'ten en az bir kez okundu mu (okunmadan "satın almamış" sayılmasın).
    @Published private(set) var bilgiOkundu = false
    /// 2 saatlik deneme kullanıldı, süresi bitti ve satın alma yok.
    var denemeBitti: Bool { bilgiOkundu && kilit && denemeKullanildi && !denemede && !satinAlinmis }
    /// Deneme bitince satış ekranı altyazı ekranında bir kez açılır (Selim, 2026-11-21: "deneme bitince satış ekranı
    /// çıkaralım, direkt oyunun içinde"). Kişi başı deneme bir kez olduğu için bu da bir kez.
    static var denemeSonuGosterildi: Bool {
        get { UserDefaults.standard.bool(forKey: "denemeSonuGosterildi") }
        set { UserDefaults.standard.set(newValue, forKey: "denemeSonuGosterildi") }
    }
    var rcHazir: Bool { Purchases.isConfigured }

    private var dinleyici: Task<Void, Never>?

    private init() {
        if !Self.rcAnahtar.isEmpty && !Purchases.isConfigured {
            Purchases.configure(withAPIKey: Self.rcAnahtar, appUserID: Kullanici.kimlik)
        }

        if Purchases.isConfigured {
            // Satın alma başka cihazda ya da uygulama kapalıyken tamamlanırsa buraya düşer.
            dinleyici = Task { [weak self] in
                for await bilgi in Purchases.shared.customerInfoStream {
                    self?.isle(bilgi)
                }
            }
        }
        Task { await yukle() }
        // Uygulama her öne geldiğinde Pro ve deneme durumu tazelenir (deneme uygulama kapalıyken bitebilir).
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.yukle() }
        }
    }

    private func isle(_ bilgi: CustomerInfo) {
        satinAlinmis = bilgi.entitlements.all[Self.yetki]?.isActive == true
        bilgiOkundu = true
        aktifUrun = satinAlinmis ? bilgi.entitlements.all[Self.yetki]?.productIdentifier : nil
        if satinAlinmis { CloudTranslator.proGerekliZamani = nil; CloudTranslator.enabled = true }
    }

    func yukle() async {
        var bilgiGeldi = false
        if Purchases.isConfigured {
            if paketler.isEmpty { paketlerYukleniyor = true }
            if let teklifler = try? await Purchases.shared.offerings() {
                paketler = (teklifler.current?.availablePackages ?? []).sorted { $0.storeProduct.price < $1.storeProduct.price }
            }
            paketlerYukleniyor = false
            if let bilgi = try? await Purchases.shared.customerInfo() { isle(bilgi); bilgiGeldi = true }
        }
        await sunucuDurumu()
        // Kilit açıkken Pro da deneme de yoksa yapay zekâ seçili kalmasın. Abonelik bilgisi hiç okunamadıysa
        // (ör. internet yok) dokunma: gerçek Pro kullanıcısının seçimi boşuna kapanmasın, sunucu zaten denetliyor.
        if bilgiGeldi && kilit && !aktif { CloudTranslator.proYokKapat() }
    }

    /// Sunucudan deneme süresini öğrenir.
    func sunucuDurumu() async {
        guard let d = await CloudTranslator.proDurumu() else { return }
        denemeKullanildi = d.denemeKullanildi
        denemeBitis = d.denemeBitis
        kilit = d.kilit
    }

    func satinAl(_ paket: Package) async {
        calisiyor = true; mesaj = ""; islenen = paket.identifier
        defer { calisiyor = false; islenen = nil }
        do {
            let sonuc = try await Purchases.shared.purchase(package: paket)
            if sonuc.userCancelled { Analiz.olay("satin_alma_vazgecti", ["urun": paket.storeProduct.productIdentifier]) }
            if !sonuc.userCancelled {
                isle(sonuc.customerInfo)
                Analiz.olay("satin_alma", ["urun": paket.storeProduct.productIdentifier, "para_birimi": paket.storeProduct.currencyCode ?? "",
                                           "tutar": NSDecimalNumber(decimal: paket.storeProduct.price).doubleValue])
                Self.metaOlay(.subscribe, deger: NSDecimalNumber(decimal: paket.storeProduct.price).doubleValue,
                              paraBirimi: paket.storeProduct.currencyCode)
            }
        } catch {
            mesaj = L("Satın alma tamamlanamadı.")
            Analiz.olay("satin_alma_hata", ["urun": paket.storeProduct.productIdentifier])
        }
    }

    func geriYukle() async {
        guard Purchases.isConfigured else { return }
        calisiyor = true; mesaj = ""; islenen = "geri"
        defer { calisiyor = false; islenen = nil }
        if let bilgi = try? await Purchases.shared.restorePurchases() { isle(bilgi) }
    }

    /// Reklamın "tıklayanı" değil "deneyeni ve alanı" bulması için Meta'ya olay (Selim, 2026-11-21: "olur").
    /// Yalnız olay adı, gerekirse tutar ve para birimi gider; kimlik, altyazı, ülke gönderilmez. Meta SDK kapalıysa hiçbir şey.
    /// Satın almada Meta'nın kendi "fb_mobile_purchase" olayıyla çakışmasın diye "Subscribe" adı kullanılır.
    static func metaOlay(_ ad: AppEvents.Name, deger: Double? = nil, paraBirimi: String? = nil) {
        guard AppDelegate.metaAcik else { return }
        if let deger {
            var p: [AppEvents.ParameterName: Any] = [:]
            if let paraBirimi { p[.currency] = paraBirimi }
            AppEvents.shared.logEvent(ad, valueToSum: deger, parameters: p)
        } else {
            AppEvents.shared.logEvent(ad)
        }
    }

    /// Paylaşım penceresi "tamamlandı" deyince çağrılır. Paylaşımın gerçekten yayımlandığını
    /// doğrulayamayız; sunucu kişi başı bir kez verir.
    func denemeAl() async {
        calisiyor = true; mesaj = ""; islenen = "deneme"
        defer { calisiyor = false; islenen = nil }
        guard let d = await CloudTranslator.denemeIste() else {
            mesaj = L("Deneme verilemedi. İnternet bağlantını kontrol et.")
            return
        }
        let onceDenemede = denemede
        denemeKullanildi = d.denemeKullanildi
        denemeBitis = d.denemeBitis
        if denemede { CloudTranslator.enabled = true }
        if denemede && !onceDenemede { Self.metaOlay(.startTrial); Analiz.olay("deneme_basladi") }
        mesaj = denemede ? (Self.ucretsizDeneme ? L("Denemen başladı: 2 saat boyunca yapay zekâ çevirisi açık.")
                                                : L("Pro denemen başladı: 1 saat yapay zekâ çevirisi senin."))
                         : L("Deneme hakkını kullandın.")
    }
}

/// Ana sayfadaki ince Pro kartı. Dokununca Pro ekranı açılır.
struct ProKart: View {
    @ObservedObject private var magaza = ProMagaza.shared
    let ac: () -> Void

    var body: some View {
        Button(action: ac) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.pro).shadow(color: Theme.pro.opacity(0.7), radius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Subsy Pro").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(L("Yapay zekâ ile daha gerçekçi çeviri"))
                        .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Text(magaza.aktif ? L("Aktif") : L("Keşfet"))
                    .font(.system(size: 13, weight: .bold)).foregroundColor(magaza.aktif ? Theme.good : .black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(magaza.aktif ? Color.white.opacity(0.10) : Theme.pro))
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
            .background(
                Capsule().fill(LinearGradient(colors: [Theme.proKoyu1, Theme.proKoyu2], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 6)
        }
        .buttonStyle(Basili())
    }
}

/// Pro ekranı: ne geldiği, mağazadan gelen fiyatlar, satın al ve geri yükle.
struct ProView: View {
    @ObservedObject private var magaza = ProMagaza.shared
    @Environment(\.dismiss) private var dismiss
    /// Altyazı ekranında deneme bitince açıldıysa üstte "denemen bitti" kartı çıkar, satın alınca ekran kendiliğinden kapanır.
    var denemeBitti = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Button(L("Kapat")) { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                }
                if denemeBitti && !magaza.satinAlinmis {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("2 saatlik denemen bitti"), systemImage: "hourglass")
                            .font(.system(size: 18, weight: .bold)).foregroundColor(Theme.pro)
                        Text(L("Yapay zekâ çevirisiyle devam etmek için bir paket seç. Seçmezsen telefon çevirisi ücretsiz sürer."))
                            .font(.system(size: 14)).foregroundColor(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Glass(radius: 18, parlak: true))
                }
                // Deneme bitince oyunun içinde açıldıysa tanıtım atlanır, fiyatlar hemen görünsün (ekran yatay, yer dar).
                if !denemeBitti || magaza.satinAlinmis {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold))
                            .foregroundColor(Theme.pro).shadow(color: Theme.pro.opacity(0.8), radius: 12)
                        Text("Subsy Pro").font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                        // Selim'in isteği: Pro'da çeviriyi yapay zekânın yaptığı ve daha gerçekçi olduğu öne çıksın.
                        Text(L("Pro'da çeviriyi yapay zekâ yapar: sahneyi anlar, replikler gerçek bir konuşma gibi okunur."))
                            .font(.system(size: 16, weight: .medium)).foregroundColor(Color.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Oran 2026-11-17 kıyasından: telefon ~45, yapay zekâ ~14 anlam hatası (DURUM.md). Ölçüm değişirse burası da değişir.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(L("%70")).font(.system(size: 44, weight: .heavy)).foregroundColor(Theme.pro)
                                .shadow(color: Theme.pro.opacity(0.6), radius: 10)
                            Text(L("daha az anlam hatası")).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(L("Gerçek oyunda yaptığımız testte, telefon çevirisine göre."))
                            .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Glass(radius: 22, parlak: true))

                    Text(L("Pro ile neler gelir").uppercased(with: ArayuzDili.yerel))
                        .font(.system(size: 12, weight: .bold)).kerning(1).foregroundColor(Theme.dim)

                    VStack(alignment: .leading, spacing: 16) {
                        madde("text.bubble.fill", L("Bağlamı gören çeviri"),
                              L("Önceki replikleri okur; kimin kime konuştuğunu ve özneyi doğru çevirir."))
                        madde("quote.bubble.fill", L("Argo ve deyimler"),
                              L("Sokak ağzını ve deyimleri kelime kelime değil, anlamıyla çevirir."))
                        madde("book.closed.fill", L("Oyuna özel sözlük"),
                              L("Adlar ve terimler oyun boyunca hep aynı çevrilir."))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Glass(radius: 22))

                }
                // Deneme kartı fiyatlardan bağımsız görünür: fiyatlar yüklenemese de deneme başlatılabilsin.
                if ProMagaza.ucretsizDeneme && !magaza.aktif && magaza.kilit && !magaza.denemeKullanildi { denemeKarti }

                if magaza.aktif {
                    VStack(spacing: 12) {
                        Label(L("Pro aktif. Teşekkürler!"), systemImage: "checkmark.seal.fill")
                            .font(.system(size: 17, weight: .bold)).foregroundColor(Theme.good)
                        if let urun = magaza.aktifUrun {
                            Text(ProMagaza.sureAdi(urun)).font(.system(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                        }
                        if magaza.satinAlinmis {
                            // Apple'ın kendi abonelik penceresi: paket değiştirme ve iptal oradan.
                            Button { yonetiyor = true } label: {
                                Text(L("Aboneliği yönet")).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16).background(Glass(radius: 18))
                    .manageSubscriptionsSheet(isPresented: $yonetiyor)
                } else if magaza.paketler.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        if magaza.paketlerYukleniyor && magaza.rcHazir {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text(L("Fiyatlar yükleniyor...")).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            }
                        } else {
                            Text(L("Fiyatlar yüklenemedi. İnternet bağlantını kontrol et.")).font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                            Button(L("Yeniden dene")) { Task { await magaza.yukle() } }
                                .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.accent)
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Glass(radius: 18, parlak: true))
                } else {
                    ForEach(magaza.paketler, id: \.identifier) { paket in
                        Button { Task { await magaza.satinAl(paket) } } label: {
                            HStack {
                                Text(ProMagaza.sureAdi(paket.storeProduct.productIdentifier))
                                    .font(.system(size: 18, weight: .bold))
                                Spacer()
                                if magaza.islenen == paket.identifier {
                                    ProgressView().tint(.white)   // Apple'ın penceresi açılana ve satın alma bitene kadar
                                } else {
                                    Text(paket.storeProduct.localizedPriceString).font(.system(size: 18, weight: .bold))   // fiyat mağazadan gelir
                                }
                            }
                            .foregroundColor(.white)
                            .opacity(magaza.calisiyor && magaza.islenen != paket.identifier ? 0.45 : 1)
                            .padding(.horizontal, 20).padding(.vertical, 16)
                            // Üstteki "Pro ile neler gelir" kartıyla aynı cam lacivert (Selim, 2026-11-17).
                            .background(Glass(radius: 18))
                        }
                        .buttonStyle(Basili()).disabled(magaza.calisiyor)
                    }
                    Text(L("Abonelik, dönem bitmeden en az 24 saat önce iptal edilmezse kendiliğinden yenilenir. Ücret Apple hesabından alınır; aboneliği App Store ayarlarından yönetebilir ya da iptal edebilirsin."))
                        .font(.system(size: 12)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }

                if magaza.denemede, let bitis = magaza.denemeBitis {
                    Label(L("Deneme süresi bitiyor:") + " " + bitis.formatted(date: .omitted, time: .shortened), systemImage: "clock.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.good)
                } else if ProMagaza.paylasOdulu && magaza.kilit && !magaza.satinAlinmis && !magaza.denemeKullanildi {
                    paylasKarti
                }

                if !magaza.mesaj.isEmpty {
                    Text(magaza.mesaj).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                Button { Task { await magaza.geriYukle() } } label: {
                    HStack(spacing: 8) {
                        if magaza.islenen == "geri" { ProgressView().tint(Theme.dim) }
                        Text(L("Satın alımları geri yükle"))
                    }
                    .font(.system(size: 14)).foregroundColor(Theme.dim).frame(maxWidth: .infinity)
                }
                .disabled(magaza.calisiyor)

                // Apple 3.1.2: abonelik ekranında yenileme bilgisi, gizlilik ve kullanım koşulları bağlantısı şart.
                VStack(spacing: 10) {
                    HStack(spacing: 18) {
                        Link(L("Gizlilik"), destination: Hakkinda.gizlilikAdresi)
                        Link(L("Kullanım Koşulları"), destination: Hakkinda.kosullarAdresi)
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.accent)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .background(Backdrop())
        .preferredColorScheme(.dark)
        // iPad'de sayfa küçük bir form penceresi olarak açılıyordu (Selim, 2026-11-21: "tablette pro popup küçülmüş").
        .presentationSizing(.page)
        .task { await magaza.yukle() }
        .onAppear { Analiz.olay("satis_ekrani_acildi", ["deneme_bitti": denemeBitti, "pro": magaza.aktif, "deneme_kullanildi": magaza.denemeKullanildi]) }
        .onChange(of: yonetiyor) { _, acik in if !acik { Task { await magaza.yukle() } } }   // pencere kapanınca durumu tazele
        .onChange(of: magaza.satinAlinmis) { _, alindi in if alindi && denemeBitti { dismiss() } }   // oyuna dön
        .onChange(of: sahne) { _, yeni in
            if yeni == .active && instagramaGitti { instagramaGitti = false; Task { await magaza.denemeAl() } }
        }
    }

    @State private var paylasiyor = false
    /// Instagram hikâye ekranı açıldı; uygulamaya dönünce 1 saat verilir (Instagram "paylaşıldı" bildirmez).
    @State private var instagramaGitti = false
    @Environment(\.scenePhase) private var sahne
    @State private var yonetiyor = false

    /// Paylaşana 1 saat Pro (Selim'in kararı, 2026-11-17). Sistem paylaşım penceresi açılır; Instagram
    /// kuruluysa listede çıkar. Paylaşılan şey oyun görüntüsü değil, bizim kartımız ve bağlantımız.
    /// Paylaşımsız 2 saatlik deneme: basınca sunucu süreyi başlatır, yapay zekâ çevirisi açılır.
    private var denemeKarti: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("2 saat ücretsiz dene"), systemImage: "gift.fill")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text(L("Yapay zekâ çevirisini 2 saat ücretsiz kullan. Kart gerekmez, bir kez geçerlidir."))
                .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            Button { Task { await magaza.denemeAl() } } label: {
                Group {
                    if magaza.islenen == "deneme" { ProgressView().tint(.black) }
                    else { Text(L("Denemeyi başlat")) }
                }
                .font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(Basili()).disabled(magaza.calisiyor)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Glass(radius: 18, parlak: true))
    }

    private var paylasKarti: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Paylaş, 1 saat Pro kazan"), systemImage: "gift.fill")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text(L("Subsy'yi Instagram'da paylaş, yapay zekâ çevirisini 1 saat ücretsiz dene."))
                .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            Button {
                if Paylasim.hikayeAcik {
                    Task { instagramaGitti = await Paylasim.hikayedePaylas() }
                } else { paylasiyor = true }
            } label: {
                Group {
                    if magaza.islenen == "deneme" { ProgressView().tint(.black) }
                    else if Paylasim.hikayeAcik { Label(L("Instagram hikâyende paylaş"), systemImage: "camera.fill") }
                    else { Label(L("Paylaş"), systemImage: "square.and.arrow.up") }
                }
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(Basili()).disabled(magaza.calisiyor)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Glass(radius: 18, parlak: true))
        .sheet(isPresented: $paylasiyor) {
            PaylasimPenceresi(ogeler: Paylasim.ogeler()) { tamamlandi, instagram in
                paylasiyor = false
                // Selim (2026-11-17): kopyalamak ya da başka yere göndermek yetmez, 1 saat yalnız Instagram'a.
                if tamamlandi && instagram { Task { await magaza.denemeAl() } }
                else if tamamlandi { magaza.mesaj = L("1 saatlik Pro yalnız Instagram'da paylaşınca verilir.") }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func madde(_ simge: String, _ baslik: String, _ aciklama: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: simge).font(.system(size: 20)).foregroundColor(Theme.pro).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(baslik).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Text(aciklama).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


/// Paylaşılan içerik: Subsy kartı (resim), kısa yazı ve ürün sayfası bağlantısı.
/// Asıl yol Instagram hikâyesi (Strava gibi çıkartma; Selim, 2026-11-17). Meta kimliği boşsa ya da
/// Instagram kurulu değilse sistemin paylaşım penceresi açılır.
enum Paylasim {
    static let adres = URL(string: "https://muginx.com/subsy/")!

    /// Meta (Facebook) uygulama kimliği. Ocak 2023'ten beri Instagram hikâyesine paylaşım bunu ister
    /// (developers.facebook.com, "Sharing to Stories"). Gizli değil. Boşken hikâye yolu kapalı.
    static let metaUygulamaKimligi = ""

    static var hikayeAcik: Bool {
        !metaUygulamaKimligi.isEmpty && UIApplication.shared.canOpenURL(URL(string: "instagram-stories://share")!)
    }

    /// Çıkartmayı panoya koyup Instagram'ı hikâye ekranında açar. Instagram açıldıysa true.
    /// Instagram gönderinin paylaşılıp paylaşılmadığını bildirmez [Meta'nın belgesi: geri bildirim yok].
    @MainActor
    static func hikayedePaylas() async -> Bool {
        let r = ImageRenderer(content: HikayeCikartmasi())
        r.scale = 1
        guard let png = r.uiImage?.pngData(),
              let url = URL(string: "instagram-stories://share?source_application=" + metaUygulamaKimligi) else { return false }
        UIPasteboard.general.setItems([[
            "com.instagram.sharedSticker.stickerImage": png,
            "com.instagram.sharedSticker.backgroundTopColor": "#0D0F33",
            "com.instagram.sharedSticker.backgroundBottomColor": "#2A0B45",
        ]], options: [.expirationDate: Date().addingTimeInterval(300)])
        return await UIApplication.shared.open(url)
    }

    @MainActor
    static func ogeler() -> [Any] {
        var liste: [Any] = [L("Konsol oyunlarını kendi dilinde oyna:") + " Subsy", adres]
        let kart = ImageRenderer(content: PaylasimKarti())
        kart.scale = 1
        if let resim = kart.uiImage { liste.insert(resim, at: 0) }
        return liste
    }
}

/// Instagram hikâyesi çıkartması (960x720; Meta 4:3 öneriyor). Kullanıcı hikâyede büyütüp gezdirebilir.
/// Metin Selim'in (2026-11-17): "oyun oynarken Subsy kullanıyorum", altında "12 dilde oyun çeviri uygulaması · App Store'da".
/// Oyun adı, görüntü ve başkasının markası yok.
struct HikayeCikartmasi: View {
    var body: some View {
        HStack(spacing: 40) {
            Image(uiImage: UIImage(named: "logo.png") ?? UIImage()).resizable().scaledToFit().frame(width: 290, height: 290)
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Oyun oynarken Subsy kullanıyorum")).font(.system(size: 62, weight: .heavy)).foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.6)
                Text(L("12 dilde oyun çeviri uygulaması")).font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Color(red: 0.91, green: 0.76, blue: 0.93)).fixedSize(horizontal: false, vertical: true)
                Text(L("App Store'da")).font(.system(size: 32, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10).background(Capsule().fill(Color.white.opacity(0.16)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(44)
        .frame(width: 960, height: 720)
        .background(RoundedRectangle(cornerRadius: 60, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.27), Color(red: 0.20, green: 0.07, blue: 0.33)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 60, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 3))
    }
}

/// 1080x1350 paylaşım kartı (Instagram gönderisi oranı). Oyun görüntüsü ve başkasının markası yok.
struct PaylasimKarti: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.20), Color(red: 0.13, green: 0.05, blue: 0.24)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 48) {
                Image(uiImage: UIImage(named: "logo.png") ?? UIImage()).resizable().scaledToFit().frame(width: 460, height: 460)
                Text(L("Her oyun senin dilinde")).font(.system(size: 72, weight: .bold)).foregroundColor(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 80)
                Text("muginx.com/subsy").font(.system(size: 40, weight: .semibold)).foregroundColor(Color.white.opacity(0.7))
            }
        }
        .frame(width: 1080, height: 1350)
    }
}

/// Sistemin paylaşım penceresi. `bitti(tamamlandi, instagram)`: tamamlandı yalnız kullanıcı bir yere
/// gönderdiğinde true; instagram, seçilen hedef Instagram'ın paylaşım eklentisiyse (kimliği "com.burbn.instagram...").
/// Gönderinin gerçekten yayımlandığı doğrulanamaz; iOS yalnız eklentinin "tamam" dediğini bildirir.
struct PaylasimPenceresi: UIViewControllerRepresentable {
    let ogeler: [Any]
    let bitti: (Bool, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
        vc.completionWithItemsHandler = { tur, tamamlandi, _, _ in
            bitti(tamamlandi, tur?.rawValue.lowercased().contains("instagram") ?? false)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
