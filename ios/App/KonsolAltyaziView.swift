import SwiftUI
import StoreKit
import Translation

/// Tam ekran altyazı (kendi PS5 bağlantımızla). Oyun görüntüsü gösterilmez: oyun TV'de, telefon
/// yanda duran altyazı ekranı. En yeni replik altta, büyük ve beyaz; öncekiler üstünde soluk.
struct KonsolAltyaziView: View {
    @ObservedObject private var konsol = Konsol.shared
    @ObservedObject private var magaza = ProMagaza.shared
    /// Deneme bitince satış ekranı burada, oyunun içinde açılır (Selim, 2026-11-21). Bir kez.
    @State private var satis = false
    @Environment(\.requestReview) private var puanIste
    /// Son yeni replik ne zaman geldi: puan penceresi konuşmanın ortasında değil, sessizlikte açılsın.
    @State private var sonReplik = Date()
    @Environment(\.scenePhase) private var sahne
    @Environment(\.dismiss) private var dismiss

    private static let renkler: [Color] = [
        Color(red: 1.00, green: 0.33, blue: 0.29),   // kırmızı
        Color(red: 1.00, green: 0.60, blue: 0.20),   // turuncu
        Color(red: 1.00, green: 0.84, blue: 0.25),   // sarı
    ]

    /// Altyazı açılır açılmaz yataydır (Selim'in isteği). Uygulama dik kaldığı için ekranı döndürmek yerine içeriği
    /// 90 derece çeviriyoruz; uzun basınca öbür yana döner. Gerçek yatay dönüş 2026-11-21'de denendi, döndürme kilidi
    /// açık iPad'de bozuk göründü, geri alındı (Selim: "döndürme işini iptal edelim").
    @AppStorage("altyaziTers") private var ters = false
    /// Yazı boyu çarpanı (0,6 - 2,4). Alttaki A− / A+ ile ayarlanır, hatırlanır. İki parmakla büyütme yok (Selim istemedi).
    @AppStorage("altyaziBoy") private var boy = 1.0

    /// iPhone/iPad uygulaması Mac'te ya da Vision Pro'da çalışıyor (ekran fiziksel olarak döndürülemez).
    static let donmeyenCihaz: Bool = {
        if ProcessInfo.processInfo.isiOSAppOnMac { return true }
        #if os(visionOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .vision
        #endif
    }()

    private func boyAyarla(_ yeni: Double) { boy = min(max(yeni, 0.6), 2.4) }

    /// Tablette ekran büyük: yazı baştan daha büyük başlar (Selim: "tablette de çıkacağız").
    private var taban: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 1.7 : 1.0 }

    /// Altyazı ekranı her açıldığında gösterilen ipucu (Selim, 2026-11-20): oyunun altyazı ayarlarında yazı zemini ve
    /// konuşan adı açıkken okuma ve çeviri belirgin iyileşiyor. Yalnız "Tamam"a basınca kapanır (Selim: "tamama basılınca kapansın"); kendiliğinden kapanmaz.
    @State private var ipucu = true
    @State private var paketAyari: TranslationSession.Configuration?
    /// Dil paketi bu cihaza indirilebiliyor mu (desteklenmeyen dilde "indir" düğmesi anlamsız).
    @State private var paketIndirilebilir = false

    var body: some View {
        GeometryReader { geo in
            // Mac'te (ve Vision Pro'da) pencere dönmez: içerik döndürülürse yazı yan durur. Orada pencere olduğu gibi kullanılır.
            let dondur = !Self.donmeyenCihaz
            icerik
                .frame(width: dondur ? geo.size.height : geo.size.width, height: dondur ? geo.size.width : geo.size.height)
                // Arapça gibi sağdan sola dillerde satır, çizgi ve ad sağa yaslanır.
                .environment(\.layoutDirection, Diller.secili.sagdanSola ? .rightToLeft : .leftToRight)
                .rotationEffect(.degrees(dondur ? (ters ? -90 : 90) : 0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color(red: 10 / 255, green: 16 / 255, blue: 40 / 255).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { dismiss() }
        .onLongPressGesture { if !Self.donmeyenCihaz { ters.toggle() } }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // ekran kararmasın
            konsol.altyaziyiBaslat()
            ipucu = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-denemeBittiOnizleme") { satis = true }
            if ProcessInfo.processInfo.arguments.contains("-puanOnizleme") { Puan.satir = Puan.esik; Puan.sorulanSurum = nil }
            #endif
            Task { await magaza.yukle(); denemeSonunaBak() }   // deneme uygulama kapalıyken bitmiş olabilir
            // Telefonun dil paketi inmemişse sistemin indirme penceresini burada aç: kullanıcı (ve App Store
            // incelemecisi) "çeviri yapılamadı" görüp Ayarlar'ı aramak zorunda kalmasın.
            Task { @MainActor in
                if await Pipeline.main?.translator.state() == .supported {
                    paketIndirilebilir = true
                    paketAyari = .init(source: Translator.source, target: Translator.target)
                }
            }
        }
        .translationTask(paketAyari) { oturum in
            try? await oturum.prepareTranslation()
            Pipeline.main?.translator.reset()   // yeni inen paketle oturum yeniden açılsın
        }
        // Zamanlayıcı görünümün ömrüne bağlı: `.onReceive(Timer.publish...)` her yeniden çizimde baştan kuruluyordu,
        // oyunda ekran sürekli yenilendiği için hiç tetiklenmedi (puan penceresi tablette açılmadı, 2026-11-21).
        .onChange(of: sahne) { _, yeni in if yeni == .background { konsol.altyaziOzetiGonder() } }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                denemeSonunaBak(); puanaBak()
            }
        }
        .onChange(of: konsol.satirlar.last?.id) { _, yeni in
            // Örnek kipindeki uydurma replikler sayılmaz; aynı repliğin düzeltilmiş okuması yeni kimlik almaz.
            guard yeni != nil, !konsol.ornekKipi else { return }
            Puan.satir += 1
            sonReplik = Date()
        }
        .onChange(of: konsol.proNotu) { _, _ in denemeSonunaBak() }
        .sheet(isPresented: $satis) {
            ProView(denemeBitti: true).environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            konsol.altyaziyiDurdur()
        }
    }

    /// Deneme süresi bittiyse ve satın alma yoksa satış ekranını bir kez aç. Örnek kipinde açılmaz.
    private func denemeSonunaBak() {
        guard !satis, !konsol.ornekKipi, magaza.denemeBitti, !ProMagaza.denemeSonuGosterildi else { return }
        ProMagaza.denemeSonuGosterildi = true
        satis = true
    }

    /// Puan isteme (Selim, 2026-11-21: "çeviri sırasında ekrana çıkaralım, bir çeviri sayısını aşınca"). Apple'ın kendi
    /// puan penceresi açılır (yıldız + isteğe bağlı yorum, App Store'a gider); Apple 5.6.1 kendi puan formumuzu yasaklıyor.
    /// Toplam 110 çevrilmiş replikten sonra (Selim, 2026-11-21: "300 çokmuş", "hatta 110"), konuşmada 8 saniyelik bir sessizlik olunca, her sürümde bir kez.
    /// Apple pencereyi yılda en çok 3 kez gösterir ve göstermeyebilir; TestFlight'ta hiç göstermez.
    private func puanaBak() {
        guard !satis, Puan.satir >= Puan.esik, Puan.sorulanSurum != Puan.surum,
              Date().timeIntervalSince(sonReplik) >= 8 else { return }
        Puan.sorulanSurum = Puan.surum
        Analiz.olay("puan_istendi", ["toplam_replik": Puan.satir])
        puanIste()
    }

    private var cevirmenRozeti: some View {
        let ai = konsol.cevirmen == "bulut"
        return Label(ai ? L("Yapay zekâ · Pro") : L("Telefon çevirisi"), systemImage: ai ? "sparkles" : "iphone")
            .font(.system(size: 12 * taban, weight: .semibold))
            .foregroundColor(ai ? Theme.pro : Color.white.opacity(0.55))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var icerik: some View {
        ZStack(alignment: .bottom) {
            Color(red: 10 / 255, green: 16 / 255, blue: 40 / 255).ignoresSafeArea()

            if konsol.ornekKipi {
                // Örnek kipinde olduğu açıkça yazsın: replikler uydurma, çeviri gerçek.
                Text(L("Örnek: uydurma replikler, çeviri gerçek"))
                    .font(.system(size: 12 * taban, weight: .semibold)).foregroundColor(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white.opacity(0.08)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 14)
            }
            if ipucu && !konsol.ornekKipi {
                VStack(alignment: .leading, spacing: 6 * taban) {
                    Label(L("Küçük bir ipucu"), systemImage: "lightbulb.fill")
                        .font(.system(size: 14 * taban, weight: .bold)).foregroundColor(Theme.accent)
                    Text(L("Oyunun altyazı ayarlarından yazı arka planını ve konuşan adlarını açarsan çeviriler çok daha isabetli olur."))
                        .font(.system(size: 13 * taban)).foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Anladım")) { withAnimation { ipucu = false } }
                        .font(.system(size: 13 * taban, weight: .semibold)).foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(14 * taban)
                .frame(maxWidth: 420 * taban, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.13, green: 0.16, blue: 0.28)))   // opak: arkadaki altyazı yazıya karışmasın
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.16), lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 14)
                .zIndex(10)   // altyazı satırlarının üstünde dursun
                .transition(.opacity)
            }
            // Sağ üst: o an çeviriyi kim yapıyor (Selim, 2026-11-17: "o an kim çeviri yapıyor görünsün").
            cevirmenRozeti
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 14).padding(.trailing, 64)
            if konsol.paketEksik && paketIndirilebilir {
                // Telefonun çevirisi için dil paketi yok: indirmeyi burada öner.
                Button { paketAyari = .init(source: Translator.source, target: Translator.target) } label: {
                    Label(L("Dil paketini indir"), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 18 * taban, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Capsule().fill(Theme.accent))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).offset(y: 60)
            }
            if konsol.satirlar.isEmpty {
                Text(konsol.ornekKipi ? L("Çevriliyor...") : (konsol.gosterilemez ? L("Konsolda açık olan içerik Uzaktan Oynama'da gösterilemiyor. Bir oyun aç, altyazı kendiliğinden gelir.") : (konsol.durum == .bagli ? L("Altyazı bekleniyor...") : L("PS5 bağlı değil"))))
                    .multilineTextAlignment(.center).padding(.horizontal, 80)
                    .font(.system(size: 22, weight: .medium)).foregroundColor(Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Konuşma kaydırılabilir: yukarı kaydırınca eski replikler okunur; yeni replik gelince en alta döner.
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(konsol.satirlar.enumerated()), id: \.element.id) { index, satir in
                            satirView(satir, enYeni: index == konsol.satirlar.count - 1).id(satir.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 64).padding(.top, 20).padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .padding(.bottom, 56)
                .onChange(of: konsol.satirlar) { _, yeni in
                    guard let son = yeni.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(son.id, anchor: .bottom) }
                }
            }

            HStack {
                if konsol.proNotu {
                    // Kilit açıkken Pro olmayan kullanıcı yapay zekâyı seçtiyse sessiz kalma: nedenini söyle.
                    Label(L("Yapay zekâ çevirisi Pro'da · şimdilik telefonla çevriliyor"), systemImage: "sparkles")
                        .font(.system(size: 12 * taban, weight: .semibold)).foregroundColor(Theme.pro)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                } else {
                    Text(konsol.sonSure).font(.system(size: 11, design: .monospaced)).foregroundColor(Color.white.opacity(0.28))
                }
                Spacer()
                Text(L("iki kez dokun: kapat · uzun bas: çevir")).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.28))
                boyDugmesi("A−", 15) { boyAyarla(boy - 0.1) }
                boyDugmesi("A+", 19) { boyAyarla(boy + 0.1) }
            }
            .padding(.horizontal, 64).padding(.bottom, 8)
        }
    }

    private func boyDugmesi(_ yazi: String, _ punto: CGFloat, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Text(yazi).font(.system(size: punto, weight: .bold)).foregroundColor(Color.white.opacity(0.75))
                .frame(width: 48, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(Basili())
    }

    private func satirView(_ satir: Konsol.Satir, enYeni: Bool) -> some View {
        let renk = Self.renkler[satir.renk % Self.renkler.count]
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(renk.opacity(enYeni ? 1 : 0.5)).frame(width: 4 * taban)
            VStack(alignment: .leading, spacing: 3) {
                if let ad = satir.konusan {
                    Text(ad.uppercased(with: Locale(identifier: Diller.secili.kod)))
                        .font(.system(size: (enYeni ? 17 : 14) * max(0.8, boy * 0.85) * taban, weight: .heavy)).kerning(0.8)
                        .foregroundColor(renk.opacity(enYeni ? 1 : 0.6))
                }
                Text(satir.metin)
                    .font(.system(size: (enYeni ? 46 : 28) * boy * taban, weight: enYeni ? .semibold : .regular))
                    .foregroundColor(Color.white.opacity(enYeni ? 1 : 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Puan isteme sayacı (telefonda kalır, hiçbir yere gönderilmez).
enum Puan {
    static let esik = 110
    static let surum = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    static var satir: Int {
        get { UserDefaults.standard.integer(forKey: "puanSatir") }
        set { UserDefaults.standard.set(newValue, forKey: "puanSatir") }
    }
    static var sorulanSurum: String? {
        get { UserDefaults.standard.string(forKey: "puanSorulanSurum") }
        set { UserDefaults.standard.set(newValue, forKey: "puanSorulanSurum") }
    }
}
