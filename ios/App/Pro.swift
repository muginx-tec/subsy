import RevenueCat
import StoreKit
import SwiftUI
import UIKit

/// Telefonun bize tanıttığı kalıcı kimlik: RevenueCat'te app_user_id, sunucuda X-Kullanici. Rastgele
/// bir UUID; kişisel bilgi taşımaz. Anahtar Zinciri'nde durur, uygulama silinip kurulsa da aynı kalır
/// (paylaşana 1 saat deneme kişi başı bir kez verilsin diye).
enum Kullanici {
    static let kimlik: String = {
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
    /// Sunucuda Pro kilidi açık mı. Kapalıyken herkes yapay zekâ çevirisi alır, deneme anlamsızdır.
    /// `-kilitGoster` ile açılırsa (yalnız görünüş denemesi) açık sayılır.
    @Published var kilit = ProcessInfo.processInfo.arguments.contains("-kilitGoster")
    @Published var mesaj = ""
    @Published var calisiyor = false
    /// Şu an hangi işin beklendiği: paket kimliği, "geri" (geri yükleme) ya da "deneme". Düğmede dönen gösterge için.
    @Published var islenen: String?

    var denemede: Bool { (denemeBitis ?? .distantPast) > Date() }
    var aktif: Bool { satinAlinmis || denemede }
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
    }

    private func isle(_ bilgi: CustomerInfo) {
        satinAlinmis = bilgi.entitlements.all[Self.yetki]?.isActive == true
        aktifUrun = satinAlinmis ? bilgi.entitlements.all[Self.yetki]?.productIdentifier : nil
        if satinAlinmis { CloudTranslator.proGerekliZamani = nil; CloudTranslator.enabled = true }
    }

    func yukle() async {
        if Purchases.isConfigured {
            if let teklifler = try? await Purchases.shared.offerings() {
                paketler = (teklifler.current?.availablePackages ?? []).sorted { $0.storeProduct.price < $1.storeProduct.price }
            }
            if let bilgi = try? await Purchases.shared.customerInfo() { isle(bilgi) }
        }
        await sunucuDurumu()
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
            if !sonuc.userCancelled { isle(sonuc.customerInfo) }
        } catch {
            mesaj = L("Satın alma tamamlanamadı.")
        }
    }

    func geriYukle() async {
        guard Purchases.isConfigured else { return }
        calisiyor = true; mesaj = ""; islenen = "geri"
        defer { calisiyor = false; islenen = nil }
        if let bilgi = try? await Purchases.shared.restorePurchases() { isle(bilgi) }
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
        denemeKullanildi = d.denemeKullanildi
        denemeBitis = d.denemeBitis
        if denemede { CloudTranslator.enabled = true }
        mesaj = denemede ? L("Pro denemen başladı: 1 saat yapay zekâ çevirisi senin.") : L("Deneme hakkını kullandın.")
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Button(L("Kapat")) { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold))
                        .foregroundColor(Theme.pro).shadow(color: Theme.pro.opacity(0.8), radius: 12)
                    Text("Subsy Pro").font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    // Selim'in isteği: Pro'da çeviriyi yapay zekânın yaptığı ve daha gerçekçi olduğu öne çıksın.
                    Text(L("Pro'da çeviriyi yapay zekâ yapar: sahneyi anlar, replikler gerçek bir konuşma gibi okunur."))
                        .font(.system(size: 16, weight: .medium)).foregroundColor(Color.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Yakında")).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        Text(L("Pro henüz satışta değil. Yapay zekâ çevirisi şimdilik herkese açık."))
                            .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
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
                } else if magaza.kilit && !magaza.satinAlinmis && !magaza.denemeKullanildi {
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
        .task { await magaza.yukle() }
        .onChange(of: yonetiyor) { _, acik in if !acik { Task { await magaza.yukle() } } }   // pencere kapanınca durumu tazele
    }

    @State private var paylasiyor = false
    @State private var yonetiyor = false

    /// Paylaşana 1 saat Pro (Selim'in kararı, 2026-11-17). Sistem paylaşım penceresi açılır; Instagram
    /// kuruluysa listede çıkar. Paylaşılan şey oyun görüntüsü değil, bizim kartımız ve bağlantımız.
    private var paylasKarti: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Paylaş, 1 saat Pro kazan"), systemImage: "gift.fill")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text(L("Subsy'yi Instagram'da ya da istediğin yerde paylaş, yapay zekâ çevirisini 1 saat ücretsiz dene."))
                .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            Button { paylasiyor = true } label: {
                Group {
                    if magaza.islenen == "deneme" { ProgressView().tint(.black) }
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
            PaylasimPenceresi(ogeler: Paylasim.ogeler()) { tamamlandi in
                paylasiyor = false
                if tamamlandi { Task { await magaza.denemeAl() } }
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
enum Paylasim {
    static let adres = URL(string: "https://muginx.com/subsy/")!

    @MainActor
    static func ogeler() -> [Any] {
        var liste: [Any] = [L("Konsol oyunlarını kendi dilinde oyna:") + " Subsy", adres]
        let kart = ImageRenderer(content: PaylasimKarti())
        kart.scale = 1
        if let resim = kart.uiImage { liste.insert(resim, at: 0) }
        return liste
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

/// Sistemin paylaşım penceresi. `bitti(true)` yalnız kullanıcı bir yere gönderdiğinde gelir.
struct PaylasimPenceresi: UIViewControllerRepresentable {
    let ogeler: [Any]
    let bitti: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, tamamlandi, _, _ in bitti(tamamlandi) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
