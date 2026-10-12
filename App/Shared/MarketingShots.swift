#if DEBUG
import CNCDesign
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// App Store marketing screenshots: a headline on the brand background and
/// the real app screen in a device frame. Debug builds only:
/// `-renderMarketing <source dir>` reads `<source>/<device>/<locale>/<shot>.png`
/// and writes the same layout to Documents/marketing.
@MainActor
enum MarketingShots {
    enum Device: String, CaseIterable {
        case iphone, ipad, mac

        /// Output size in points, rendered at 2x: 1320×2868, 2064×2752, 2880×1800.
        var canvas: CGSize {
            switch self {
            case .iphone: CGSize(width: 660, height: 1434)
            case .ipad: CGSize(width: 1032, height: 1376)
            case .mac: CGSize(width: 1440, height: 900)
            }
        }
    }

    static func renderAll(source: URL) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let output = docs.appending(path: "marketing")
        for device in Device.allCases {
            for (locale, lines) in MarketingCopy.text {
                for (index, shot) in MarketingCopy.shots.enumerated() {
                    let input = source.appending(path: "\(device.rawValue)/\(locale)/\(shot).png")
                    guard let screen = loadImage(input) else { continue }
                    let view = MarketingShotView(device: device, headline: lines[index].0, sub: lines[index].1,
                                                 screen: screen, isRTL: locale.hasPrefix("ar"))
                    let renderer = ImageRenderer(content: view.frame(width: device.canvas.width, height: device.canvas.height))
                    renderer.scale = 2
                    renderer.isOpaque = true
                    guard let image = renderer.cgImage else { continue }
                    let folder = output.appending(path: "\(device.rawValue)/\(locale)")
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    CreativeRenderer.write(image, to: folder.appending(path: "\(shot).png"))
                }
            }
        }
        try? "done".write(to: output.appending(path: "DONE"), atomically: true, encoding: .utf8)
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct MarketingShotView: View {
    let device: MarketingShots.Device
    let headline: String
    let sub: String
    let screen: CGImage
    let isRTL: Bool

    private var size: CGSize { device.canvas }

    var body: some View {
        ZStack {
            background
            switch device {
            case .iphone, .ipad: portrait
            case .mac: landscape
            }
        }
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x24211C), Color(hex: 0x100F0D)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [TP.Palette.accent.opacity(0.45), .clear], center: UnitPoint(x: 0.85, y: 0.05),
                           startRadius: 0, endRadius: size.width * 0.9)
            RadialGradient(colors: [Color(hex: 0x2F9E6F).opacity(0.18), .clear], center: UnitPoint(x: 0.1, y: 0.95),
                           startRadius: 0, endRadius: size.width * 0.8)
        }
    }

    private var copy: some View {
        VStack(alignment: device == .mac ? .leading : .center, spacing: size.width * 0.025) {
            Text(headline)
                .font(.system(size: device == .mac ? 64 : size.width * 0.085, weight: .heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.system(size: device == .mac ? 26 : size.width * 0.038, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(device == .mac ? (isRTL ? .trailing : .leading) : .center)
    }

    private var portrait: some View {
        let phone = device == .iphone
        let frameWidth = size.width * (phone ? 0.80 : 0.82)
        let aspect = CGFloat(screen.height) / CGFloat(screen.width)
        return VStack(spacing: size.height * 0.035) {
            copy.padding(.horizontal, size.width * 0.07).padding(.top, size.height * 0.065)
            DeviceFrame(screen: screen, width: frameWidth, height: frameWidth * aspect,
                        corner: frameWidth * (phone ? 0.13 : 0.045), bezel: frameWidth * (phone ? 0.03 : 0.025))
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }

    private var landscape: some View {
        let windowWidth = size.width * 0.58
        let aspect = CGFloat(screen.height) / CGFloat(screen.width)
        return HStack(spacing: size.width * 0.04) {
            copy.frame(maxWidth: size.width * 0.3, alignment: .leading)
            DeviceFrame(screen: screen, width: windowWidth, height: windowWidth * aspect, corner: 18, bezel: 0)
        }
        .padding(.horizontal, size.width * 0.05)
    }
}

/// The app screen with rounded corners, a thin bezel and a soft glow.
struct DeviceFrame: View {
    let screen: CGImage
    let width: CGFloat
    let height: CGFloat
    let corner: CGFloat
    let bezel: CGFloat

    var body: some View {
        Image(decorative: screen, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: max(corner - bezel, 4)))
            .padding(bezel)
            .background(Color(hex: 0x0B0B0C), in: .rect(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.18), lineWidth: 1.5))
            .shadow(color: TP.Palette.accent.opacity(0.25), radius: 40, y: 10)
            .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
    }
}

/// Headlines for the six screenshots, per App Store locale.
enum MarketingCopy {
    static let shots = ["01_preview", "02_warnings", "03_preflight", "04_lathe", "05_feeds", "06_dark"]

    static let text: [String: [(String, String)]] = [
        "en-US": [("See every move before you cut", "3D and 2D toolpath preview with live simulation"),
                  ("Catch the crash before it happens", "Rapids into stock, low clearance and more, explained with fixes"),
                  ("A checklist built from your file", "Zero, stock, tools and safety, ticked off before Start"),
                  ("Lathes too", "G71 roughing and G76 threading, pass by pass"),
                  ("Feeds & speeds you can trust", "Calculated for your machine, never guessed"),
                  ("Made for the workshop", "Dark mode, big targets, works offline")],
        "tr": [("Kesmeden önce her hareketi gör", "Canlı simülasyonlu 3D ve 2D takım yolu önizlemesi"),
               ("Çarpmayı olmadan yakala", "Malzemeye hızlı dalış, düşük boşluk ve fazlası, çözümleriyle"),
               ("Dosyandan oluşan kontrol listesi", "Sıfır, stok, takım ve güvenlik; Başlat'tan önce tamam"),
               ("Tornalar da", "G71 kaba işleme ve G76 diş, paso paso"),
               ("Güvenilir ilerleme ve devir", "Makinene göre hesaplanır, asla tahmin edilmez"),
               ("Atölye için tasarlandı", "Koyu tema, büyük dokunma alanları, internetsiz çalışır")],
        "de-DE": [("Jede Bewegung sehen, bevor du fräst", "3D- und 2D-Werkzeugweg mit Live-Simulation"),
                  ("Den Crash erkennen, bevor er passiert", "Eilgänge ins Material, zu wenig Abstand und mehr – mit Lösung"),
                  ("Eine Checkliste aus deiner Datei", "Nullpunkt, Material, Werkzeug und Sicherheit vor dem Start"),
                  ("Auch für Drehmaschinen", "G71-Schruppen und G76-Gewinde, Schnitt für Schnitt"),
                  ("Vorschub und Drehzahl, denen du traust", "Für deine Maschine berechnet, nie geraten"),
                  ("Gemacht für die Werkstatt", "Dunkelmodus, große Bedienflächen, offline nutzbar")],
        "es-ES": [("Mira cada movimiento antes de cortar", "Vista de trayectoria 3D y 2D con simulación"),
                  ("Detecta el choque antes de que ocurra", "Rápidos contra el material, poca altura y más, con soluciones"),
                  ("Una lista creada a partir de tu archivo", "Cero, material, herramientas y seguridad antes de empezar"),
                  ("También para tornos", "Desbaste G71 y roscado G76, pasada a pasada"),
                  ("Avances y velocidades de confianza", "Calculados para tu máquina, nunca inventados"),
                  ("Hecha para el taller", "Modo oscuro, controles grandes, funciona sin conexión")],
        "it": [("Vedi ogni movimento prima di tagliare", "Anteprima del percorso 3D e 2D con simulazione"),
               ("Scopri la collisione prima che accada", "Rapidi nel grezzo, quota bassa e altro, con le soluzioni"),
               ("Una checklist creata dal tuo file", "Zero, grezzo, utensili e sicurezza prima di partire"),
               ("Anche per torni", "Sgrossatura G71 e filettatura G76, passata per passata"),
               ("Avanzamenti e velocità affidabili", "Calcolati per la tua macchina, mai inventati"),
               ("Fatta per l'officina", "Modalità scura, comandi grandi, funziona offline")],
        "ru": [("Видите каждое движение до резки", "3D и 2D просмотр траектории с симуляцией"),
               ("Поймайте аварию до того, как она случится", "Холостые ходы в материал, малый зазор и другое — с решениями"),
               ("Чек-лист по вашему файлу", "Ноль, заготовка, инструмент и безопасность перед запуском"),
               ("И для токарных станков", "Черновой цикл G71 и резьба G76 по проходам"),
               ("Режимы резания, которым можно верить", "Рассчитаны для вашего станка, а не угаданы"),
               ("Создано для мастерской", "Тёмная тема, крупные кнопки, работает офлайн")],
        "ja": [("削る前に、\nすべての動きを確認", "シミュレーション付きの3D・2Dツールパスプレビュー"),
               ("衝突を、\n起きる前に見つける", "材料への早送りや逃げ不足などを対処法とともに表示"),
               ("ファイルから作る\nチェックリスト", "原点・材料・工具・安全をスタート前に確認"),
               ("旋盤にも対応", "G71荒加工とG76ねじ切りをパスごとに表示"),
               ("信頼できる\n送りと回転数", "あなたの機械に合わせて計算、推測なし"),
               ("作業場のために", "ダークモード、大きなボタン、オフラインで動作")],
        "zh-Hans": [("切削前\n看清每一步", "带模拟的 3D 和 2D 刀路预览"),
                    ("在撞刀之前\n发现问题", "快速移动撞入材料、安全高度不足等，附修复方法"),
                    ("根据文件生成的\n检查清单", "零点、毛坯、刀具和安全，开工前逐项确认"),
                    ("也支持车床", "G71 粗车和 G76 螺纹，逐刀显示"),
                    ("值得信赖的\n进给与转速", "按你的机床计算，绝不靠猜"),
                    ("为车间而生", "深色模式、大按钮、离线可用")],
        "ar-SA": [("شاهد كل حركة قبل القطع", "معاينة مسار الأداة ثلاثية وثنائية الأبعاد مع المحاكاة"),
                  ("اكتشف الاصطدام قبل حدوثه", "حركات سريعة داخل الخامة وخلوص منخفض وغيرها، مع الحلول"),
                  ("قائمة فحص من ملفك", "الصفر والخامة والأدوات والسلامة قبل البدء"),
                  ("للمخارط أيضًا", "تخشين G71 وتسنين G76 مشوارًا بمشوار"),
                  ("تغذية وسرعات تثق بها", "محسوبة لماكينتك، لا تخمين"),
                  ("مصمم للورشة", "وضع داكن وأزرار كبيرة ويعمل دون اتصال")],
    ]
}
#endif
