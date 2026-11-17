# Subsy

Subsy reads the English subtitles of a PS5/PS4 game from your own console over your local network and
shows them translated, full screen, on your iPhone or iPad. The game stays on the TV, the controller
stays in your hands. Available on the App Store as "Subsy: Game Translator".

Subsy, kendi konsolundaki oyunun İngilizce altyazısını yerel ağ üzerinden okur ve telefonda ya da
tablette, senin dilinde, tam ekran gösterir. Oyun TV'de, kumanda elinde kalır.

## License

The iOS app is free software under the **GNU Affero General Public License v3.0 only, with the OpenSSL
exception** (see `LICENSE` and `LICENSES/`), because it links code from these projects:

- [Pylux](https://github.com/ForWard-Technologies-LLC/Pylux) (iOS bridge files in `ios/App/Baglanti/`, see `KAYNAK.md` there)
- [chiaki-ng](https://github.com/streetpea/chiaki-ng) and Chiaki (the console connection library, libchiaki)

The translation server used for the optional AI translation is a separate program and is not part of
this repository.

Subsy is an independent app. It is not affiliated with, endorsed by, or sponsored by Sony Interactive
Entertainment. PlayStation, PS5 and PS4 are trademarks of their respective owners.

## Building

1. Clone Pylux next to this repository's `ios/` folder: `dis/Pylux` (tested at commit `ca87a49`).
2. Build libchiaki for the simulator and/or device from `dis/Pylux`:
   ```
   cmake -S . -B build-iphoneos -G Ninja -DCMAKE_TOOLCHAIN_FILE=ios.toolchain.cmake -DPLATFORM=OS64 \
     -DDEPLOYMENT_TARGET=15.0 -DMBEDTLS_FATAL_WARNINGS=OFF -DUSE_NGHTTP2=OFF -DCMAKE_BUILD_TYPE=Release \
     -DUSE_LIBIDN2=OFF -DCURL_USE_LIBPSL=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
   cmake --build build-iphoneos --target chiaki-lib
   ```
   (`PLATFORM=SIMULATORARM64` and `build-iphonesimulator` for the simulator), then combine all produced
   `.a` files into `libchiaki_complete.a` with `libtool -static` inside each build folder.
3. Copy `ios/Config/Gizli.xcconfig.ornek` to `ios/Config/Gizli.xcconfig` (the translation server secret is
   not published; without it the app uses on-device translation only).
4. Open `ios/Subsy.xcodeproj` and build the `Subsy` scheme.

UI strings are generated: edit `ceviri/anahtarlar.json` (Turkish source) and `ceviri/<lang>.json`, then run
`python3 ceviri/olustur.py`.

Support: support@muginx.com
