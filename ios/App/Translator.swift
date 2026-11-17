import Foundation
import SwiftUI
import Translation

/// Apple'ın telefondaki çevirisi. İnternet ve ücret gerektirmez; dil paketi bir kez iner.
final class Translator {
    static let source = Locale.Language(identifier: "en")
    /// Hedef dil ayardan gelir (Diller.secili); değişince `reset()` çağrılır.
    static var target: Locale.Language { Locale.Language(identifier: Diller.secili.kod) }

    private var session: TranslationSession?

    /// Dil değişti: eski dile açılmış oturum bırakılır, sonraki çeviride yenisi açılır.
    func reset() { session = nil }

    enum State: String { case installed = "kurulu", supported = "indirilmeli", unsupported = "desteklenmiyor" }

    func state() async -> State {
        switch await LanguageAvailability().status(from: Self.source, to: Self.target) {
        case .installed: return .installed
        case .supported: return .supported
        default: return .unsupported
        }
    }

    /// Dil paketi kuruluysa oturumu açar. Arayüz gerektirmediği için arka planda da çağrılabilir.
    func prepare() async -> Bool {
        guard await state() == .installed else { session = nil; return false }
        if session == nil { session = TranslationSession(installedSource: Self.source, target: Self.target) }
        return true
    }

    func translate(_ text: String) async throws -> String {
        if session == nil { _ = await prepare() }
        guard let session else { throw NSError(domain: "Translator", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: "dil paketi kurulu değil"]) }
        return try await session.translate(text).targetText
    }
}

/// Dil paketini indirtmek için gereken tek SwiftUI parçası: sistemin indirme penceresini yalnız
/// `translationTask` açabiliyor.
struct LanguageDownloadView: View {
    let onDone: (String) -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { config = .init(source: Translator.source, target: Translator.target) }
            .translationTask(config) { session in
                do {
                    try await session.prepareTranslation()
                    onDone("dil paketi hazır")
                } catch {
                    onDone("dil paketi indirilemedi: \(error.localizedDescription)")
                }
            }
    }
}
