import SwiftUI

/// Okunacak kutunun ayarı (kendi PS5 bağlantımızla). Eski yoldan farkı: oyun **canlı** görünür,
/// kutu oyun akarken sürüklenir ve o an ne okunduğu altında yazar. Uygulamadan çıkmak gerekmez.
struct KonsolKutuView: View {
    @ObservedObject private var konsol = Konsol.shared
    @Environment(\.dismiss) private var dismiss
    @State private var box = Kutu.kayitli
    @State private var surukBasi: Kutu?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Altyazının yeri")).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button(L("Bitti")) { dismiss() }.font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.accent)
            }
            Text(L("Oyunda altyazı çıkan bir yere gel (en kolayı oyunun altyazı ayarları ekranı). Sarı kutuyu altyazının üstüne sürükle; kutu altyazıyı içine alsın ama menü ve göstergeleri dışarıda bıraksın."))
                .font(.system(size: 14)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let w = geo.size.width, h = w * 9 / 16
                ZStack(alignment: .topLeading) {
                    if let image = konsol.sonKare {
                        Image(uiImage: image).resizable().frame(width: w, height: h)
                    } else {
                        Rectangle().fill(Color.black).frame(width: w, height: h)
                        Text(L("PS5 görüntüsü bekleniyor...")).foregroundColor(Theme.dim)
                            .frame(width: w, height: h)
                    }
                    // Kutu: cy alttan ölçülür (okuma tarafıyla aynı), ekranda üstten çizilir.
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 2)
                        .background(Color.yellow.opacity(0.12))
                        .frame(width: w * box.w, height: h * box.h)
                        .offset(x: w * (box.cx - box.w / 2), y: h * (1 - box.cy - box.h / 2))
                }
                .frame(width: w, height: h)
                // Oyun görüntüsü ve kutu fiziksel koordinattadır: sağdan sola dillerde de aynalanmaz,
                // yoksa kutu ekranda yanlış yerde çizilir ve sürükleme ters çalışır.
                .environment(\.layoutDirection, .leftToRight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if surukBasi == nil { surukBasi = box }
                        guard let b = surukBasi else { return }
                        var yeni = b
                        yeni.cx = b.cx + Double(g.translation.width / w)
                        yeni.cy = b.cy - Double(g.translation.height / h)
                        kaydet(yeni)
                    }
                    .onEnded { _ in surukBasi = nil })
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            ayar(L("Boy"), value: Binding(get: { box.h }, set: { var b = box; b.h = $0; kaydet(b) }), range: 0.08...1)
            ayar(L("En"), value: Binding(get: { box.w }, set: { var b = box; b.w = $0; kaydet(b) }), range: 0.2...1)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("ŞU AN OKUNAN")).font(.system(size: 12, weight: .bold)).kerning(1).foregroundColor(Theme.dim)
                Text(konsol.sonOkunan.isEmpty ? L("(kutuda yazı yok)") : konsol.sonOkunan)
                    .font(.system(size: 16)).foregroundColor(konsol.sonOkunan.isEmpty ? Theme.dim : .white)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(5)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))

            Button(L("Varsayılana dön")) { kaydet(Kutu.varsayilan) }
                .font(.system(size: 14)).foregroundColor(Theme.dim)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Backdrop())
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            konsol.sonOkunan = ""
            konsol.kutuAyari = true
            if ProcessInfo.processInfo.arguments.contains("-kutuOnizleme") {
                konsol.sonKare = Onizleme.sahne()
                konsol.sonOkunan = Onizleme.kutuAltyazisi
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            konsol.kutuAyari = false
        }
    }

    private func kaydet(_ yeni: Kutu) {
        var b = yeni
        b.clamp()
        box = b
        Kutu.kayitli = b   // okuma her karede buradan okur: değişiklik anında geçerli
    }

    private func ayar(_ ad: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(ad).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }
}
