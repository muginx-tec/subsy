import SwiftUI
import UIKit

/// Ana ekranın durumu. KokViewController doldurur, HomeView ve SettingsView gösterir.
final class HomeModel: ObservableObject {
    @Published var language = "denetleniyor" // kurulu / indirilmeli / desteklenmiyor
    @Published var showGuide = false
    @Published var cloud = CloudTranslator.enabled { didSet { CloudTranslator.enabled = cloud; onCloudChanged() } }
    @Published var cloudGame = CloudTranslator.game { didSet { CloudTranslator.game = cloudGame; onCloudChanged() } }
    @Published var cloudStatus = ""
    var onCloudChanged: () -> Void = {}
    var onDownloadLanguage: () -> Void = {}
    /// Arayüz İngilizce mi (Selim, 2026-11-17: "İngilizce dil de ekleyelim"). İngilizce altyazı dili
    /// değil (oyunun kendi dili), yalnız arayüz dili; altyazı dili olduğu gibi kalır.
    @Published var arayuzIngilizce = (ArayuzDili.secilen == "en")
    @Published var hedefDil = Diller.secili.kod {
        didSet {
            guard hedefDil != oldValue, let d = Diller.hepsi.first(where: { $0.kod == hedefDil }) else { return }
            Diller.secili = d
            // Tek dil ayarı: altyazı da arayüz de bu dile geçer. Arayüz İngilizceyse (kullanıcı bilerek
            // seçti) yalnız altyazı dili değişir.
            if !arayuzIngilizce { ArayuzDili.secilen = d.kod }
            language = "denetleniyor"
            onLanguageChanged()
        }
    }
    var onLanguageChanged: () -> Void = {}
    var dilAdi: String { Diller.hepsi.first(where: { $0.kod == hedefDil })?.ad ?? hedefDil }

    /// Sağ üst menüden seçim. "en": yalnız arayüz İngilizce olur. Başka dil: arayüz ve altyazı o dile geçer.
    func menudenSec(_ kod: String) {
        if kod == "en" {
            ArayuzDili.secilen = "en"
            arayuzIngilizce = true
            return
        }
        arayuzIngilizce = false
        ArayuzDili.secilen = kod
        hedefDil = kod
        objectWillChange.send()   // altyazı dili aynı kaldıysa da arayüz yeniden çizilsin
    }
}

enum Theme {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.27, green: 0.66, blue: 1.00) // mavi (Selim'in tasarımı, 2026-11-16); eskiden turuncuydu
    static let night = Color(red: 0.03, green: 0.06, blue: 0.13)   // zeminin en koyu laciverti
    // Pro'nun renkleri Selim'in gönderdiği örnekten (2026-11-16): koyu erik geçişi #2D1E2F → #4E2A4F, ince açık
    // kenar. Sarı, açık mor ve buz mavisi denendi, istemedi. Simge ve düğme aynı ailenin açık tonu.
    static let pro = Color(red: 0.91, green: 0.76, blue: 0.93)
    static let proKoyu1 = Color(red: 0x2D / 255, green: 0x1E / 255, blue: 0x2F / 255)
    static let proKoyu2 = Color(red: 0x4E / 255, green: 0x2A / 255, blue: 0x4F / 255)
    static let blue = Color(red: 0.25, green: 0.56, blue: 1.00)
    static let good = Color(red: 0.42, green: 0.86, blue: 0.56)
    static let dim = Color.white.opacity(0.55)
    // Konuşan renkleri: altyazı ekranıyla aynı (Selim'in seçimi: kırmızı, turuncu, sarı).
    static let speakerRed = Color(red: 1.00, green: 0.33, blue: 0.29)
    static let speakerOrange = Color(red: 1.00, green: 0.60, blue: 0.20)
    static let speakerYellow = Color(red: 1.00, green: 0.84, blue: 0.25)
}

/// Bütün ekranların zemini: lacivertten siyaha, üstte sıcak bir ışık. Altyazı ekranının lacivertiyle aynı aile.
struct Backdrop: View {
    var body: some View {
        // Selim'in arka plan görseli (tasarim/arkaplan.webp): koyu lacivert üstünde mavi ışık dalgaları.
        // Üstüne hafif bir karartı: yazılar ve cam yüzeyler dalgaların üstünde de okunur kalsın.
        GeometryReader { geo in
            Image(uiImage: UIImage(named: "arkaplan.jpg") ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(Theme.night.opacity(0.28))
        }
        .background(Theme.night)
        .ignoresSafeArea()
    }
}

/// Bütün düğmelerin basılma tepkisi: basılıyken hafifçe küçülür ve kararır, bırakınca yaylanarak döner;
/// basış anında telefon hafifçe tıklar. (Selim: "tuşlara bastığım hiç belli olmuyor".)
struct Basili: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, basili in
                if basili { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
    }
}

/// Cam yüzey: yarı saydam lacivert dolgu, ince açık kenar; "parlak" olan mavi kenar ve ışık alır.
struct Glass: View {
    var radius: CGFloat
    var parlak = false
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(parlak ? 0.14 : 0.09), Color.white.opacity(0.03)],
                                 startPoint: .top, endPoint: .bottom))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(red: 0.06, green: 0.12, blue: 0.24).opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LinearGradient(colors: [(parlak ? Theme.accent : Color.white).opacity(parlak ? 0.9 : 0.28), Color.white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: parlak ? 1.4 : 1))
            .shadow(color: parlak ? Theme.accent.opacity(0.35) : Color.black.opacity(0.3), radius: parlak ? 14 : 10, y: parlak ? 0 : 6)
    }
}

struct HomeView: View {
    @ObservedObject var model: HomeModel
    @State private var showSettings = false
    @State private var showKutu = ProcessInfo.processInfo.arguments.contains("-kutuOnizleme")
    @State private var showPro = ProcessInfo.processInfo.arguments.contains("-proEkrani")
    @ObservedObject private var konsol = Konsol.shared

    /// Alt çubuktaki sekme: 0 ana sayfa, 1 konsol, 2 ayarlar.
    @State private var sekme = (ProcessInfo.processInfo.arguments.contains("-konsolDeneme") || ProcessInfo.processInfo.arguments.contains("-altyaziOnizleme")) ? 1 : (ProcessInfo.processInfo.arguments.contains("-hakkinda") || ProcessInfo.processInfo.arguments.contains("-ayarlarSekmesi") ? 2 : 0)

    var body: some View {
        ZStack {
            Backdrop()
            switch sekme {
            case 1: BaglanView(gomulu: true)
            case 2: SettingsView(model: model, gomulu: true)
            default: anaSayfa
            }
        }
        .safeAreaInset(edge: .bottom) { sekmeCubugu }
        .environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        .fullScreenCover(isPresented: $model.showGuide) {
            GuideView { UserDefaults.standard.set(true, forKey: "guideSeen"); model.showGuide = false }
                .environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(isPresented: $showKutu) { KonsolKutuView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight) }
        .sheet(isPresented: $showPro) {
            ProView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .onAppear {
            // Ekran görüntüsü seçenekleriyle açılınca rehber üstlerine binmesin.
            let onizleme = ["-ayarlarSekmesi", "-kutuOnizleme", "-altyaziOnizleme", "-hakkinda", "-proEkrani"]
            if !UserDefaults.standard.bool(forKey: "guideSeen"), !ProcessInfo.processInfo.arguments.contains(where: onizleme.contains) { model.showGuide = true }
        }
    }

    // MARK: Ana ekran, Selim'in tasarımına göre (tasarim/ana_ekran_tasarim.webp, 2026-11-16)

    private var bagli: Bool { konsol.durum == .bagli }

    private var anaSayfa: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                sahne
                VStack(spacing: 22) {   // Pro kartı gelince 30'dan 22'ye: sayfa kaymasın
                    baglaDugmesi
                    ozellikler
                    ProKart { showPro = true }
                    kutucuklar
                }
                .padding(.horizontal, 20)
                .padding(.top, -34)   // sahnenin alttaki kararan kısmına biraz girsin, arada boşluk kalmasın
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)   // içerik ekrana sığıyorsa kaymaz (Selim: gereksiz kaydırma olmasın)
        .ignoresSafeArea(edges: .top)
    }

    /// Üstteki sahne: Selim'in yazısız görseli (tasarim/sahne_yazisiz.webp). Başlık ve açıklama kodla
    /// yazılır, böylece net görünür ve her dile çevrilebilir.
    private var sahne: some View {
        Image(uiImage: UIImage(named: "hero.jpg") ?? UIImage())   // klasördeki düz dosya: uzantısıyla çağrılır
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(788.0 / 540.0, contentMode: .fit)   // görselin altından biraz kırpılır: Pro kartına yer açar
            .clipped()
            // Kenarları arka plana eritilir: altta ve en üstte saydamlaşır, arkadaki dalgalar görünür.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                                         .init(color: .black, location: 0.70), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                // Yazının arkasındaki yumuşak karartı: sol üst köşeden dışa doğru erir.
                RadialGradient(colors: [Theme.night.opacity(0.78), Theme.night.opacity(0.45), Theme.night.opacity(0)],
                               center: .topLeading, startRadius: 10, endRadius: 250)
                    .frame(width: 270, height: 250).allowsHitTesting(false)
                    .flipsForRightToLeftLayoutDirection(true)   // Arapçada başlık sağda: karartı da sağ üst köşeden başlar
            }
            .overlay(alignment: .topLeading) { baslik.padding(.leading, 22).padding(.top, 30) }
            .overlay(alignment: .topTrailing) { dilDugmesi.padding(.trailing, 18).padding(.top, 26) }
            .padding(.top, 40)   // yalnız saat ve pil satırı kadar; üstte boşluk kalmasın (Selim)
    }

    /// Başlık: küçük ve sakin, sol üstte. Arkasında yumuşak bir karartı var ki görselin üstünde okunur
    /// kalsın ama TV'nin üstüne taşmasın (Selim: logo ve isim küçülsün, yazı aşağı insin, hafif gölge).
    private var baslik: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(uiImage: UIImage(named: "logo.png") ?? UIImage()).resizable().scaledToFit().frame(width: 40, height: 40)
                Text("Subsy").font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Oyunlardaki diyalogları anında kendi diline çevir."))
                    .font(.system(size: 13, weight: .medium)).foregroundColor(Color.white.opacity(0.82))
                    .lineSpacing(2).frame(width: 138, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Capsule().fill(Theme.accent).frame(width: 30, height: 2.5).shadow(color: Theme.accent.opacity(0.9), radius: 4)
            }
        }
        .shadow(color: Color.black.opacity(0.55), radius: 6, y: 1)
    }

    /// Sağ üstteki dil düğmesi (Selim'in isteği): dokununca dil listesi açılır. Seçilen dil hem
    /// uygulamanın yazılarını hem altyazının çevrileceği dili değiştirir.
    private var dilDugmesi: some View {
        Menu {
            // İngilizce listenin başında, öbürleriyle aynı listede (Selim: "listede farklı yerde duruyor").
            // Yalnız arayüz dili; altyazı Ayarlar'da seçili dile çevrilmeye devam eder.
            Button { model.menudenSec("en") } label: {
                if model.arayuzIngilizce { Label("English", systemImage: "checkmark") } else { Text("English") }
            }
            ForEach(Diller.hepsi) { d in
                Button { model.menudenSec(d.kod) } label: {
                    if !model.arayuzIngilizce && d.kod == model.hedefDil { Label(d.ad, systemImage: "checkmark") } else { Text(d.ad) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 14, weight: .semibold))
                Text(model.arayuzIngilizce ? "EN" : model.hedefDil.uppercased()).font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25)))
        }
    }

    private var dilUyarisi: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 22)).foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.dilAdi) dil paketi").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(model.language == "desteklenmiyor" ? L("Telefon bu dili çeviremiyor. Ayarlar'dan yapay zekâyı seç.")
                                                        : L("Telefonla çeviri için bir kez indirilmeli (ücretsiz)."))
                    .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if model.language == "indirilmeli" {
                Button(L("İndir"), action: model.onDownloadLanguage)
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
        }
        .padding(16)
        .background(Glass(radius: 20))
    }

    /// Büyük cam düğme: konsola bağla. Bağlıyken altyazıyı açar.
    private var baglaDugmesi: some View {
        Button { sekme = 1 } label: {
            HStack(spacing: 16) {
                // PlayStation logosu kaldırıldı (Selim, 2026-11-17): mağaza görüntülerinde marka riski.
                // Genel kumanda simgesi; alt sekmedeki "Konsol" ile aynı aile.
                Image(systemName: bagli ? "checkmark.circle.fill" : "gamecontroller.fill")
                    .font(.system(size: 30, weight: .semibold)).foregroundColor(bagli ? Theme.good : .white)
                    .frame(width: 44)
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bagli ? L("Konsol Bağlı") : L("Konsola Bağla")).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)   // uzun dillerde iki satıra taşıp sayfayı itmesin
                    Text(bagli ? L("Altyazıyı açmak için dokun.") : L("PS5 veya PS4'ünü bul ve çeviriyi başlat."))
                        .font(.system(size: 13.5)).foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.30, green: 0.66, blue: 1.00), Color(red: 0.14, green: 0.42, blue: 0.92)],
                                                 startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 10)
                    Image(systemName: "arrow.forward").font(.system(size: 18, weight: .bold)).foregroundColor(.white)   // sağdan sola dillerde kendiliğinden döner
                }
            }
            .padding(.leading, 22).padding(.trailing, 18).padding(.vertical, 20)
            .background(Glass(radius: 44, parlak: true))
        }
        .buttonStyle(Basili())
    }

    private var ozellikler: some View {
        HStack(alignment: .top, spacing: 0) {
            ozellik(simge: "square.stack.3d.up", ad: L("AI Context"), aciklama: L("Hikâyeyi ve bağlamı anlar."))
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 38).padding(.horizontal, 5)
            ozellik(simge: "bolt", ad: L("Düşük Gecikme"), aciklama: L("Telefonla çeviri saniyenin altında."))
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 38).padding(.horizontal, 5)
            ozellik(simge: "wifi.slash", ad: L("Çevrimdışı Çeviri"), aciklama: L("İnternetsiz de çalışır."))
        }
        .padding(.horizontal, 4)
    }

    private func ozellik(simge: String, ad: String, aciklama: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: simge).font(.system(size: 18, weight: .medium)).foregroundColor(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.7), radius: 6).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.system(size: 11.5, weight: .bold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(aciklama).font(.system(size: 10.5)).foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(3).minimumScaleFactor(0.75)   // uzun dillerde sayfayı aşağı itmesin
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kutucuklar: some View {
        HStack(spacing: 12) {
            kutucuk(simge: "tv", ad: L("Altyazının Yeri"), alt: L("Okunacak alan"), secili: true) {
                if bagli { showKutu = true } else { sekme = 1 }
            }
            kutucuk(simge: "gamecontroller", ad: L("Nasıl Kullanılır"), alt: L("Hızlı rehber")) { model.showGuide = true }
            kutucuk(simge: "slider.horizontal.3", ad: L("Ayarlar"), alt: L("Dil, model")) { sekme = 2 }
        }
    }

    private func kutucuk(simge: String, ad: String, alt: String, secili: Bool = false, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: simge).font(.system(size: 26, weight: .light)).foregroundColor(.white)
                Spacer(minLength: 0)
                Text(ad).font(.system(size: 14.5, weight: .bold)).foregroundColor(.white)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                Text(alt).font(.system(size: 11.5)).foregroundColor(Color.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(Glass(radius: 22, parlak: secili))
        }
        .buttonStyle(Basili())
    }

    /// Alttaki cam sekme çubuğu: Ana Sayfa, Konsol, Ayarlar.
    private var sekmeCubugu: some View {
        HStack(spacing: 0) {
            sekmeDugmesi(0, simge: "house", ad: L("Ana Sayfa"))
            sekmeDugmesi(1, simge: "gamecontroller", ad: L("Konsol"))
            sekmeDugmesi(2, simge: "gearshape", ad: L("Ayarlar"))
        }
        .padding(.vertical, 10)
        .background(Glass(radius: 40))
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))   // arkadaki yazı okunmasın
        .padding(.horizontal, 20).padding(.bottom, 4)
    }

    private func sekmeDugmesi(_ no: Int, simge: String, ad: String) -> some View {
        let secili = sekme == no
        return Button { sekme = no } label: {
            VStack(spacing: 5) {
                Image(systemName: simge).font(.system(size: 22, weight: .medium))
                Text(ad).font(.system(size: 12.5, weight: secili ? .semibold : .regular))
                Capsule().fill(secili ? Theme.accent : Color.clear).frame(width: 46, height: 3)
                    .shadow(color: Theme.accent.opacity(secili ? 0.9 : 0), radius: 5)
            }
            .foregroundColor(secili ? Theme.accent : Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(Basili())
    }
}
