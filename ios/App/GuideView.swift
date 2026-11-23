import SwiftUI

/// Başlangıç rehberi. İlk açılışta kendiliğinden gelir, ana ekrandan yeniden açılabilir.
/// Adımlar kendi konsol bağlantımıza göre (2026-11-16): giriş, eşleştirme, bağlanma, altyazı.
struct GuideView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Step {
        let icon: String, title: String, text: String, note: String?
        var link: (title: String, subtitle: String, url: String)? = nil
    }

    // Yazılar dile bağlı değil: "Türkçeye çevirir" yerine "senin diline çevirir" (Selim, 2026-11-16).
    private let steps: [Step] = [
        Step(icon: "captions.bubble.fill", title: L("Her oyun senin dilinde"),
             text: L("Dilinde olmayan oyunu TV'de, kendi kumandanla, her zamanki gibi oynarsın. Telefon yanında durur ve oyunun altyazısını senin diline çevirip gösterir."),
             note: L("Kamera yok, kablo yok.")),
        Step(icon: "text.bubble", title: L("Oyunda altyazıyı aç"),
             text: L("Oyunun ayarlarından İngilizce altyazıyı aç. Uygulama ekrandaki o altyazıyı okuyup çevirir; altyazı kapalıysa çevirecek bir şey bulamaz."),
             note: nil),
        Step(icon: "person.crop.circle", title: L("PSN ile giriş yap"),
             text: L("Uygulama konsola senin ana PSN hesabınla bağlanır. “Konsol” sekmesinde o hesapla bir kez giriş yaparsın."),
             note: L("Giriş Sony'nin kendi sayfasında yapılır. Parolan bu uygulamaya gelmez, hiçbir yere gönderilmez.")),
        Step(icon: "wifi", title: L("Aynı ağda ol"),
             text: L("Konsol ve telefon aynı Wi-Fi ağına bağlı olmalı. Konsol açık olsun. Uygulama konsolu ağda kendisi bulur; ilk açılışta çıkan “yerel ağdaki cihazları bul” iznine izin ver."),
             note: L("PS5 ve PS4 desteklenir. Konsol kabloyla, telefon Wi-Fi ile aynı modeme bağlıysa da olur.")),
        Step(icon: "link", title: L("Konsolu bir kez eşleştir"),
             text: L("PS5'te Ayarlar › Sistem › Uzaktan Oynama › Cihaz Bağla ekranını aç, çıkan 8 haneli kodu uygulamaya yaz."),
             note: L("Bunu yalnız ilk seferde yaparsın. PS4'te yol: Ayarlar › Uzaktan Oynama Bağlantı Ayarları › Cihaz Ekle.")),
        Step(icon: "dot.radiowaves.left.and.right", title: L("Bağlan ve altyazıyı aç"),
             text: L("“Konsola Bağla”ya bas. Bağlanınca “Altyazıyı aç”a dokun: altyazı tam ekran gelir. Telefonu yatay koy, yanında dursun."),
             note: L("Yazı boyunu alttaki A− / A+ ile ayarlarsın. Yukarı kaydırınca eski replikleri okursun.")),
        // Hesap düzeni Selim'in kararı (2026-11-16): uygulama ana hesabı kullanır, kumanda ikinci bir kullanıcıyla oynar.
        Step(icon: "person.2.fill", title: L("Kumanda için ikinci kullanıcı"),
             text: L("Uygulama ana hesabını kullandığı için kumandan o hesapla çalışmaz. Konsolda ikinci bir kullanıcı oluştur. Bağlandıktan sonra kumandada PS tuşuna bas, o kullanıcıyı seç ve oyunu onunla oyna. Oyun açıksa kapat ve o kullanıcıyla yeniden aç: kumanda oyunu yalnız onu açan kullanıcıyla oynatır."),
             note: L("İkinci kullanıcıyı bir kez oluşturursun. Oyun TV'de sürer; kayıtların ve kupaların o kullanıcıda birikir.")),
        Step(icon: "rectangle.dashed", title: L("Altyazının yerini ayarla"),
             text: L("Her oyun altyazıyı başka yere koyar. Çeviri gelmiyorsa ya da menü yazıları karışıyorsa “Altyazının Yeri”ni aç ve sarı kutuyu oyundaki altyazının üstüne sürükle."),
             note: L("En kolayı oyunun altyazı ayarları ekranında yapmak: çoğu oyun orada örnek bir altyazı gösterir.")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L("Geç"), action: onDone).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.dim)
            }
            .padding(.horizontal, 22).padding(.top, 14)

            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { i in
                    stepView(steps[i], number: i + 1).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Theme.accent : Color.white.opacity(0.18))
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .padding(.bottom, 22)
            .animation(.easeOut(duration: 0.2), value: page)

            Button {
                if page < steps.count - 1 { withAnimation { page += 1 } } else { onDone() }
            } label: {
                Text(page < steps.count - 1 ? L("Devam") : L("Başlayalım"))
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
            }
            .padding(.horizontal, 22).padding(.bottom, 20)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func stepView(_ step: Step, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card).frame(width: 96, height: 96)
                Image(systemName: step.icon).font(.system(size: 42, weight: .medium)).foregroundColor(Theme.accent)
            }
            Text("\(number) / \(steps.count)").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.accent).kerning(1.2)
            Text(step.title).font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.text).font(.system(size: 18)).foregroundColor(Color.white.opacity(0.82)).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if let link = step.link, let url = URL(string: link.url) {
                Link(destination: url) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.app.fill").font(.system(size: 26)).foregroundColor(Theme.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            Text(link.subtitle).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.dim)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.blue.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.blue.opacity(0.45)))
                }
            }
            if let note = step.note {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundColor(Theme.dim)
                    Text(note).font(.system(size: 15)).foregroundColor(Theme.dim).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
    }
}
