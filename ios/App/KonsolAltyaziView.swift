import SwiftUI
import StoreKit
import Translation

/// Tam ekran altyazı (kendi PS5 bağlantımızla). Oyun görüntüsü gösterilmez: oyun TV'de, telefon
/// yanda duran altyazı ekranı. En yeni replik altta, büyük ve beyaz; öncekiler üstünde soluk.
struct KonsolAltyaziView: View {
    @ObservedObject private var konsol = Konsol.shared
    @ObservedObject private var magaza = ProMagaza.shared
    @ObservedObject private var reklam = OdulluReklam.shared
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
    /// Eski repliklerin parlaklığı (0 - 1; 0 = eskiler hiç görünmez). Alttaki çubukla ayarlanır, hatırlanır (Selim, 2026-11-22: "eski replikleri
    /// soluklaştıracak bir çubuk, solukluğunu ayarlayabileyim"). Varsayılan önceki sabit değer: 0,45.
    @AppStorage("altyaziEskiParlaklik") private var eskiParlaklik = 0.45
    /// Altyazının çizildiği alanın yüksekliği (döndürülmüş hâlde): en yeni repliğin yazısı buna göre sınırlanır.
    @State private var alanYuksekligi: CGFloat = 400
    @State private var alanGenisligi: CGFloat = 800
    /// Çubuk yavaştı (Selim: "çok yavaş, telefonu yormayacak bir şey bul"): yerine tek düğme, basınca bir kademe soluklaşır.
    private static let kademeler: [Double] = [0.45, 0.25, 0.1, 0]
    private var parlaklik: Double { eskiParlaklik }
    private func sonrakiKademe() {
        let i = Self.kademeler.firstIndex(where: { abs($0 - eskiParlaklik) < 0.02 }) ?? 0
        eskiParlaklik = Self.kademeler[(i + 1) % Self.kademeler.count]
    }

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
    /// Apple'ın çevirisi seçili dili hiç desteklemiyor (ücretsiz yol yok); Pro ya da deneme yoksa uyarı kartı çıkar.
    @State private var dilDesteklenmiyor = false
    @State private var proAcik = false
    /// Deneme teklif kartı açık mı; bu oturumda gösterildi mi.
    @State private var teklif = false
    @State private var teklifGosterildi = false
    /// Günlük ücretsiz sürenin kalanı (dakika); sınır yoksa nil. 2 sn'de bir güncellenir (Selim, 2026-11-23: "sayaç").
    @State private var kalanSaniye: Int?

    var body: some View {
        GeometryReader { geo in
            // Mac'te (ve Vision Pro'da) pencere dönmez: içerik döndürülürse yazı yan durur. Orada pencere olduğu gibi kullanılır.
            let dondur = !Self.donmeyenCihaz
            let yukseklik = dondur ? geo.size.width : geo.size.height
            let genislik = dondur ? geo.size.height : geo.size.width
            icerik
                .onAppear { alanYuksekligi = yukseklik; alanGenisligi = genislik }
                .onChange(of: yukseklik) { _, y in alanYuksekligi = y }
                .onChange(of: genislik) { _, g in alanGenisligi = g }
                .frame(width: dondur ? geo.size.height : geo.size.width, height: dondur ? geo.size.width : geo.size.height)
                // Arapça gibi sağdan sola dillerde satır, çizgi ve ad sağa yaslanır.
                .environment(\.layoutDirection, Diller.secili.sagdanSola ? .rightToLeft : .leftToRight)
                .rotationEffect(.degrees(dondur ? (ters ? -90 : 90) : 0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color(red: 10 / 255, green: 16 / 255, blue: 40 / 255).ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // ekran kararmasın
            konsol.altyaziyiBaslat()
            ipucu = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-denemeBittiOnizleme") { satis = true }
            if ProcessInfo.processInfo.arguments.contains("-sureBittiOnizleme") { UcretsizSure.doldur(); ipucu = false; konsol.ucretsizBitti = true }
            if ProcessInfo.processInfo.arguments.contains("-teklifOnizleme") { DenemeTeklifi.satir = DenemeTeklifi.ilk; DenemeTeklifi.gosterim = 0; ipucu = false; sonReplik = .distantPast; Puan.sorulanSurum = Puan.surum }
            if ProcessInfo.processInfo.arguments.contains("-puanOnizleme") { Puan.satir = Puan.esik; Puan.sorulanSurum = nil }
            #endif
            Task { await magaza.yukle(); denemeSonunaBak() }   // deneme uygulama kapalıyken bitmiş olabilir
            // Telefonun dil paketi inmemişse sistemin indirme penceresini burada aç: kullanıcı (ve App Store
            // incelemecisi) "çeviri yapılamadı" görüp Ayarlar'ı aramak zorunda kalmasın.
            Task { @MainActor in
                let durum = await Pipeline.main?.translator.state()
                dilDesteklenmiyor = durum == .unsupported
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-teklifOnizleme") { dilDesteklenmiyor = false }   // simülatörde dil paketi yok
                #endif
                if durum == .supported {
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
                sureyeBak(); denemeSonunaBak(); puanaBak(); teklifeBak()
            }
        }
        .onChange(of: konsol.satirlar.last?.id) { _, yeni in
            // Örnek kipindeki uydurma replikler sayılmaz; aynı repliğin düzeltilmiş okuması yeni kimlik almaz.
            guard yeni != nil, !konsol.ornekKipi else { return }
            Puan.satir += 1
            if !magaza.aktif { DenemeTeklifi.satir += 1 }
            sonReplik = Date()
        }
        .onChange(of: konsol.proNotu) { _, _ in denemeSonunaBak() }
        .sheet(isPresented: $satis) {
            ProView(denemeBitti: true).environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $proAcik) {
            ProView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .onDisappear {
            UcretsizSure.simdiKaydet()
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
    /// Günlük ücretsiz süre: altyazı ekranı açık ve konsol bağlıyken 2 sn'de bir sayılır (saat gibi).
    private func sureyeBak() {
        guard !konsol.ornekKipi else { return }
        // Saat gibi işler (Selim, 2026-11-23: "saat gibi"): altyazı ekranı açık, uygulama önde ve konsol bağlıyken her 2 sn.
        // Önceden yalnız son 60 sn'de replik geldiyse sayıyordu; konuşmasız bölümlerde durduğu için anlaşılmıyordu.
        // "Önde mi" UIApplication'dan: SwiftUI scenePhase bu ekranda (UIKit kökünden açılan tam ekran) güvenilmez çıktı,
        // tablette sayaç hiç işlemedi (2026-11-23).
        if UcretsizSure.gecerli, konsol.durum == .bagli, UIApplication.shared.applicationState == .active {
            let once = UcretsizSure.bitti
            UcretsizSure.ekle(saniye: 2)
            if !once && UcretsizSure.bitti { Analiz.olay("ucretsiz_sure_bitti", ["dakika": UcretsizSure.gunlukDakika]) }
        }
        if UcretsizSure.gecerli { OdulluReklam.shared.hazirla() }   // video süre bitmeden hazır olsun
        let bitti = UcretsizSure.bitti
        if konsol.ucretsizBitti != bitti { withAnimation { konsol.ucretsizBitti = bitti } }   // deneme / Pro başlayınca kalkar
        let kalan: Int? = UcretsizSure.gecerli && !bitti
            ? max(0, Int(Double((UcretsizSure.gunlukDakika + UcretsizSure.ekDakika) * 60) - UcretsizSure.kullanilan))
            : nil
        if kalanSaniye != kalan { kalanSaniye = kalan }
    }

    /// Kalan ücretsiz süre rozeti: sağ üstte, çeviren rozetinin yanında. Son 5 dakikada turuncu.
    @ViewBuilder private var sayacRozeti: some View {
        if let sn = kalanSaniye, !konsol.ornekKipi {
            // Son 5 dakikada dakika:saniye geri sayım (Selim, 2026-11-23: "geri saymıyor, 3'te duruyor": dakikaya yuvarlanınca
            // bir dakika boyunca aynı kalıyordu). Daha uzunsa yukarı yuvarlanmış dakika.
            let az = sn <= 300
            let yazi = az ? String(format: L("Ücretsiz · %d:%02d"), sn / 60, sn % 60)
                          : String(format: L("Ücretsiz · %d dk"), (sn + 59) / 60)
            Label(yazi, systemImage: "hourglass")
                .font(.system(size: 12 * taban, weight: .semibold))
                .foregroundColor(az ? Color(red: 1.0, green: 0.62, blue: 0.2) : Color.white.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(az ? Color.orange.opacity(0.18) : Color.white.opacity(0.08)))
        }
    }

    /// Süre bitti kartı (Selim, 2026-11-23: önceki hâli "sevmedim"): ortalı başlık, tek satır açıklama, tam genişlikte asıl düğme
    /// (video), altında sade deneme düğmesi, en altta yazı bağlantısı olarak Pro. Yazılar arayüz dilinde; Arapça arayüzde sağdan sola.
    private var sureBittiKarti: some View {
        let denemeVar = ProMagaza.ucretsizDeneme && magaza.kilit && !magaza.denemeKullanildi
        return VStack(spacing: 12 * taban) {
            Image(systemName: "hourglass").font(.system(size: 26 * taban, weight: .semibold)).foregroundColor(Theme.pro)
            Text(L("Bugünkü ücretsiz süren bitti"))
                .font(.system(size: 18 * taban, weight: .bold)).foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(L("Ücretsiz çeviri yarın yeniden açılır. Şimdi devam etmek için:"))
                .font(.system(size: 13.5 * taban)).foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            // Asıl seçenek: ödüllü video. Oyuncu kendisi seçer, oyun kendiliğinden durmaz.
            Button {
                Analiz.olay("sure_bitti_video")
                reklam.goster {
                    UcretsizSure.ekDakika += OdulluReklam.dakika
                    withAnimation { konsol.ucretsizBitti = false }
                }
            } label: {
                HStack(spacing: 8) {
                    if reklam.hazir { Image(systemName: "play.fill") } else { ProgressView().tint(Theme.proKoyu1) }
                    Text(reklam.hazir ? L("Video izle, 30 dakika daha") : L("Video hazırlanıyor...")).lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.system(size: 16 * taban, weight: .bold)).foregroundColor(Theme.proKoyu1)
                .frame(maxWidth: .infinity).padding(.vertical, 12 * taban)
                .background(Capsule().fill(Theme.pro))
            }
            .buttonStyle(Basili()).disabled(!reklam.hazir)
            if denemeVar {
                Button {
                    Analiz.olay("sure_bitti_deneme")
                    Task { await magaza.denemeAl() }
                } label: {
                    HStack(spacing: 6) {
                        if magaza.islenen == "deneme" { ProgressView().tint(.white) }
                        Text(L("45 dakika ücretsiz dene")).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 15 * taban, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11 * taban)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1))
                }
                .buttonStyle(Basili()).disabled(magaza.calisiyor)
            }
            Button {
                Analiz.olay("sure_bitti_pro")
                proAcik = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(L("Subsy Pro'ya bak")).underline()
                }
                .font(.system(size: 16.5 * taban, weight: .bold)).foregroundColor(Theme.pro)
                .padding(.vertical, 6)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20 * taban).padding(.vertical, 20 * taban)
        .frame(maxWidth: 400 * taban)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Theme.proKoyu1, Theme.proKoyu2], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24)
        // Arayüz dilinin yönü (altyazı satırları altyazı diline göre dönüyor; kart arayüzün parçası).
        .environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
    }

    private var teklifUygun: Bool {
        !konsol.ucretsizBitti && ProMagaza.ucretsizDeneme && magaza.bilgiOkundu && magaza.kilit && !magaza.aktif && !magaza.denemeKullanildi
            && !konsol.ornekKipi && !dilDesteklenmiyor
    }

    private func teklifeBak() {
        if teklif && !teklifUygun { withAnimation { teklif = false } }   // deneme başladı ya da satın alındı
        guard !teklif, !teklifGosterildi, !satis, !proAcik, !ipucu, teklifUygun,
              DenemeTeklifi.gosterim < DenemeTeklifi.enCok, DenemeTeklifi.satir >= DenemeTeklifi.esik,
              Date().timeIntervalSince(sonReplik) >= 8 else { return }
        teklifGosterildi = true
        DenemeTeklifi.gosterim += 1
        Analiz.olay("deneme_teklifi", ["kacinci": DenemeTeklifi.gosterim, "telefon_replik": DenemeTeklifi.satir])
        withAnimation { teklif = true }
    }

    private var teklifKarti: some View {
        HStack(spacing: 12 * taban) {
            Image(systemName: "sparkles").font(.system(size: 18 * taban, weight: .semibold)).foregroundColor(Theme.pro)
            Text(L("Yapay zekâ çevirisini 45 dakika ücretsiz dene"))
                .font(.system(size: 14 * taban, weight: .semibold)).foregroundColor(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button {
                Analiz.olay("deneme_teklifi_dene", ["kacinci": DenemeTeklifi.gosterim])
                Task { await magaza.denemeAl() }
            } label: {
                HStack(spacing: 6) {
                    if magaza.islenen == "deneme" { ProgressView().tint(Theme.proKoyu1) }
                    Text(L("Dene")).lineLimit(1)
                }
                .font(.system(size: 14 * taban, weight: .bold)).foregroundColor(Theme.proKoyu1)
                .padding(.horizontal, 16).padding(.vertical, 8).background(Capsule().fill(Theme.pro))
            }
            .buttonStyle(Basili()).disabled(magaza.calisiyor)
            Button {
                Analiz.olay("deneme_teklifi_kapat", ["kacinci": DenemeTeklifi.gosterim])
                withAnimation { teklif = false }
            } label: {
                Image(systemName: "xmark").font(.system(size: 13 * taban, weight: .bold)).foregroundColor(Color.white.opacity(0.6))
                    .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(Basili())
        }
        .padding(.horizontal, 14 * taban).padding(.vertical, 10 * taban)
        .frame(maxWidth: 560 * taban)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Theme.proKoyu1, Theme.proKoyu2], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 58)   // en yeni replik üstte: kartlar altta
                .zIndex(10)   // altyazı satırlarının üstünde dursun
                .transition(.opacity)
            }
            if !konsol.ornekKipi && !ipucu && !konsol.ucretsizBitti && DilDestekKarti.gorunur(dilDesteklenmiyor: dilDesteklenmiyor) {
                DilDestekKarti(olcek: taban, yer: "altyazi") { proAcik = true }
                    .frame(maxWidth: 460 * taban)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 58)
                    .zIndex(9)
            }
            if konsol.ucretsizBitti && !konsol.ornekKipi {
                sureBittiKarti
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .zIndex(11).transition(.opacity)
            }
            if teklif {
                // Altta: en yeni replik üstte büyük durur, kart onu örtmesin (eski replikler soluk, üstü kapansa da olur).
                teklifKarti
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 58)
                    .zIndex(9).transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if konsol.paketEksik && paketIndirilebilir {
                // Telefonun çevirisi için dil paketi yok: indirmeyi burada öner.
                Button { paketAyari = .init(source: Translator.source, target: Translator.target) } label: {
                    Label(L("Dil paketini indir"), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 18 * taban, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Capsule().fill(Theme.accent))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).offset(y: 60)
            }
            if !konsol.ornekKipi && konsol.durum != .bagli {
                // Bağlantı durumu (Selim, 2026-11-23: "bu sırada çeviri ekranına bağlanıyor gibi bir şey koyabilir miyiz"):
                // arka planda kopup kendiliğinden yeniden bağlanırken kullanıcı ne olduğunu görsün.
                let baglaniyor = konsol.durum == .baglaniyor || konsol.uyandiriliyor
                HStack(spacing: 8) {
                    if baglaniyor { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "wifi.exclamationmark") }
                    Text(baglaniyor ? L("Konsola yeniden bağlanıyor...") : L("Bağlantı koptu. Konsol sekmesinden yeniden bağlan."))
                }
                .font(.system(size: 14 * taban, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(baglaniyor ? Theme.accent.opacity(0.85) : Color.orange.opacity(0.85)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 14)
                .zIndex(12)
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
                    // Üstten aşağı akar (Selim, 2026-11-22: "replik üstten aşağıya aksın"): en yeni replik en üstte büyük,
                    // eskiler altına iner ve soluklaşır. Aşağı kaydırınca eskiler okunur; yeni replik gelince en üste döner.
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(konsol.satirlar.reversed().enumerated()), id: \.element.id) { index, satir in
                            satirView(satir, enYeni: index == 0).id(satir.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 64).padding(.top, 20).padding(.bottom, 8)
                    .animation(.easeOut(duration: 0.18), value: konsol.satirlar.last?.id)
                }
                .defaultScrollAnchor(.top)
                // İki kez dokun / uzun bas yalnız altyazı alanında: alt çubuktaki A+ / A− / solukluk düğmelerine hızlı
                // iki kez basınca ekran kapanıyordu (Selim, 2026-11-23).
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { dismiss() }
                .onLongPressGesture { if !Self.donmeyenCihaz { ters.toggle() } }
                .padding(.bottom, 56)
                .onChange(of: konsol.satirlar) { _, yeni in
                    guard let son = yeni.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(son.id, anchor: .top) }
                }
            }

            HStack {
                // Alt köşe (Selim, 2026-11-23: "en alt köşeye", "telefon çevirisini de oraya taşı, Pro'yu orada görelim"):
                // o an çeviriyi kim yapıyor ve kalan ücretsiz süre.
                HStack(spacing: 8) { cevirmenRozeti; sayacRozeti }
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
                // Eski repliklerin solukluğu: her basış bir kademe (normal, soluk, çok soluk, gizli).
                Button(action: sonrakiKademe) {
                    // Hangi kademede olduğu görünsün (Selim: "kademeyi görebileceğim bir şey olmalı"): altta 3 çizgi,
                    // dolu olanlar eski repliklerin ne kadar görünür olduğu (3 normal, 2 soluk, 1 çok soluk, 0 gizli).
                    let kademe = Self.kademeler.firstIndex(where: { abs($0 - eskiParlaklik) < 0.02 }) ?? 0
                    VStack(spacing: 4) {
                        Image(systemName: eskiParlaklik == 0 ? "eye.slash" : "circle.lefthalf.filled")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Color.white.opacity(0.8))
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Capsule().fill(i < 3 - kademe ? Theme.accent : Color.white.opacity(0.18)).frame(width: 10, height: 4)
                            }
                        }
                    }
                        .frame(width: 48, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(Basili())
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

    /// En yeni replik ne kadar büyütülse de en çok 4 satırı ekrana sığsın (üst boşluk, ad satırı, alt çubuk düşülür).
    /// İlk hâli 3 satıra göre hesaplıyordu; tablette 4 satırlık cümle taştı (Selim, 2026-11-23).
    private var enBuyukPunto: CGFloat { max(24, (alanYuksekligi - 150) / (4 * 1.25)) }

    /// En yeni replik ekrana sığmıyorsa sığana kadar küçülür; kesilmez, "…" olmaz (Selim, 2026-11-23: "sığacak kadar küçülsün").
    /// Yazının yüksekliği UIKit ile ölçülür: yalnız en yeni satır için, her yeni replikte bir kez.
    private func sigdir(_ metin: String, adVar: Bool) -> CGFloat {
        var punto = min(46 * boy * taban, enBuyukPunto)
        let genislik = max(100, alanGenisligi - 128 - 16)   // yatay kenar boşlukları + renk çizgisi
        let sinir = alanYuksekligi - 110 - (adVar ? 26 * taban : 0)   // üst boşluk, alt çubuk, konuşan adı
        while punto > 14 {
            let font = UIFont.systemFont(ofSize: punto, weight: .semibold)
            let h = (metin as NSString).boundingRect(with: CGSize(width: genislik, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: font], context: nil).height
            if h <= sinir { break }
            punto *= 0.92
        }
        return punto
    }

    private func satirView(_ satir: Konsol.Satir, enYeni: Bool) -> some View {
        let renk = Self.renkler[satir.renk % Self.renkler.count]
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(renk.opacity(enYeni ? 1 : 0.9)).frame(width: 4 * taban)
            VStack(alignment: .leading, spacing: 3) {
                if let ad = satir.konusan {
                    Text(ad.uppercased(with: Locale(identifier: Diller.secili.kod)))
                        .font(.system(size: (enYeni ? 17 : 14) * max(0.8, boy * 0.85) * taban, weight: .heavy)).kerning(0.8)
                        .foregroundColor(renk)
                }
                // En yeni replik: yazı büyütülmüşken uzun cümle ekrana sığmayıp kesiliyordu (Çek kullanıcının tablet fotoğrafı,
                // 2026-11-22); punto alan yüksekliğine göre sınırlı (enBuyukPunto).
                Text(satir.metin)
                    .font(.system(size: enYeni ? sigdir(satir.metin, adVar: satir.konusan != nil) : 28 * boy * taban, weight: enYeni ? .semibold : .regular))
                    .foregroundColor(Color.white)
                    // Kesilmez: punto 4 satır sığacak kadar sınırlı; daha uzun cümle aşağı kaydırılarak okunur (Selim, 2026-11-23).
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(enYeni ? 1 : parlaklik)   // eski satır tek katman olarak soluklaşır: çubuk sürüklenirken ucuz
    }
}

/// Puan isteme sayacı (telefonda kalır, hiçbir yere gönderilmez).
/// Ücretsiz (telefonla) oynayana ara sıra deneme kartı (Selim, 2026-11-22: "ara sıra pop up gibi, ücretsiz çeviriyi dene").
/// İlk kez 50 telefon replikten sonra, sonra her 200'de; oturumda en çok 1, toplamda en çok 4 kez. Telefonda kalır.
enum DenemeTeklifi {
    static let ilk = 50, aralik = 200, enCok = 4
    static var satir: Int {
        get { UserDefaults.standard.integer(forKey: "teklifSatir") }
        set { UserDefaults.standard.set(newValue, forKey: "teklifSatir") }
    }
    static var gosterim: Int {
        get { UserDefaults.standard.integer(forKey: "teklifGosterim") }
        set { UserDefaults.standard.set(newValue, forKey: "teklifGosterim") }
    }
    static var esik: Int { ilk + gosterim * aralik }
}

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
