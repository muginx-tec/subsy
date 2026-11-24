# Bu klasördeki kod bizim değil

Bu klasördeki `.h` ve `.m` dosyaları Pylux projesinden alındı (tek değişiklik aşağıda):
https://github.com/ForWard-Technologies-LLC/Pylux (sürüm ca87a49, 2026-08-13), `ios/Pylux/Bridge/`.
Pylux, Chiaki ve chiaki-ng üzerine kuruludur. Lisans: AGPL-3.0 (dosya başlarındaki SPDX satırı).

Bu dosyalar PS5'e bağlanan kütüphaneyi (libchiaki) Swift'e açar. Biz bu kodu yazmıyor ve
değiştirmiyoruz; yalnız çağırıyoruz. Güncellemek için Pylux'taki yeni hâli buraya kopyalanır.

Bu kod uygulamaya girdiği için **telefon uygulamasının tamamı AGPL-3.0 ile açık kaynaktır**
(karar: DURUM.md karar günlüğü, 2026-11-16). Sunucu (`sunucu/`) ayrı programdır, kapalıdır.

## Bizim değişikliklerimiz

- `ChiakiAudioOutputIOS.m`: ses kuyruğunun düzeyi sıfıra çekildi (iki satır, "Subsy eklemesi"
  yorumuyla işaretli). Neden: oyunun sesi TV'den gelir, telefon susmalı. Bağlantı koduna dokunulmadı.
- `ChiakiSessionBridge.m`: her oturuma "gösterilemez" geri çağrısı verildi ("Subsy eklemesi" yorumlarıyla
  işaretli). Neden: konsol Uzaktan Oynama'ya kapalı bir içerik gösterirken (ör. YouTube) kütüphane bu geri
  çağrıyı denetimsiz çağırıyor, verilmemişse uygulama çöküyordu (2026-11-18). Durum `SubsyGosterilemez`
  bildirimiyle uygulamaya iletilir.

## Değişiklik: VideoDecoder.m (2026-11-23)
Uygulama arka plana gidip dönünce iOS çözücü oturumunu geçersiz kılıyor (kVTInvalidSessionErr, -12903). Pylux'un çözücüsü
oturumu yeniden kurmuyordu; bağlantı "bağlı" görünüp kare gelmiyordu. Şimdi -12903'te oturum silinir, sonraki karede
`createSession` ile yeniden kurulur.
