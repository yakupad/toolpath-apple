#if DEBUG
import CNCDesign
import CNCKit
import CNCRender
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders App Store creative assets (product page header and search result
/// images) with the app's own toolpath renderer. Debug builds only:
/// launch with `-renderCreatives`; PNGs land in Documents/creatives.
@MainActor
enum CreativeRenderer {
    /// Point sizes rendered at 2x: header 21:9 (3840×1646), header 16:9
    /// (5244×2950) and search results 3:2 (3840×2560).
    static let formats: [(name: String, size: CGSize)] = [
        ("header", CGSize(width: 1920, height: 823)),
        ("header169", CGSize(width: 2622, height: 1475)),
        ("search", CGSize(width: 1920, height: 1280)),
    ]

    enum Visual { case mill, lathe }

    struct Page {
        let id: String
        let visual: Visual
        let copy: [String: (headline: String, sub: String)]
    }

    static func renderAll() {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = base.appending(path: "creatives")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for page in CreativeCopy.pages {
            for (locale, text) in page.copy {
                for format in formats {
                    let view = CreativeView(visual: page.visual, headline: text.headline, sub: text.sub,
                                            isRTL: locale.hasPrefix("ar"), size: format.size)
                    let renderer = ImageRenderer(content: view.frame(width: format.size.width, height: format.size.height))
                    renderer.scale = 2
                    renderer.isOpaque = true
                    guard let image = renderer.cgImage else { continue }
                    write(image, to: folder.appending(path: "\(page.id)_\(locale)_\(format.name).png"))
                }
            }
        }
        try? "done".write(to: folder.appending(path: "DONE"), atomically: true, encoding: .utf8)
    }

    /// Text-free 15 s videos (usable in every language): the toolpath draws
    /// on, the dangerous rapid turns red and the score drops from 100 to 75.
    static func renderVideos() async {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = base.appending(path: "creatives")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let videos: [(String, CGSize)] = [("video_header", CGSize(width: 1920, height: 823)),
                                          ("video_search", CGSize(width: 1440, height: 960))]
        for (name, size) in videos {
            let url = folder.appending(path: "\(name).mov")
            try? FileManager.default.removeItem(at: url)
            do { try await renderVideo(size: size, seconds: 15, fps: 30, to: url) }
            catch { try? "\(error)".write(to: folder.appending(path: "\(name).error.txt"), atomically: true, encoding: .utf8) }
        }
        try? "done".write(to: folder.appending(path: "VIDEOS_DONE"), atomically: true, encoding: .utf8)
    }

    static func renderVideo(size: CGSize, seconds: Double, fps: Int32, to url: URL) async throws {
        let pixelWidth = Int(size.width * 2), pixelHeight = Int(size.height * 2)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000, AVVideoExpectedSourceFrameRateKey: fps],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * Double(fps))
        for index in 0..<frames {
            let t = Double(index) / Double(fps)
            let renderer = ImageRenderer(content: CreativeVideoFrame(time: t, size: size).frame(width: size.width, height: size.height))
            renderer.scale = 2
            renderer.isOpaque = true
            guard let image = renderer.cgImage, let pool = adaptor.pixelBufferPool else { continue }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: pixelWidth, height: pixelHeight,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

/// One creative: the toolpath on one side, the message on the other.
struct CreativeView: View {
    let visual: CreativeRenderer.Visual
    let headline: String
    let sub: String
    let isRTL: Bool
    let size: CGSize

    private static let millDocument = GCodeParser().parse(SampleProgram.sign + "\nG0 X60 Y30 Z-1.5\nG0 Z5\n", fileName: "creative")
    private static let millFindings = GCodeAnalyzer().analyze(millDocument)
    private static let latheDocument = LatheParser().parse(SampleProgram.lathe, fileName: "creative")

    var body: some View {
        let wide = size.width / size.height > 1.6
        ZStack {
            LinearGradient(colors: [Color(hex: 0x23211C), Color(hex: 0x121110)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Group {
                if wide {
                    HStack(spacing: 0) {
                        canvas.frame(width: size.width * 0.56)
                        message.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, size.width * 0.06)
                    }
                } else {
                    VStack(spacing: 0) {
                        canvas.frame(height: size.height * 0.58)
                        message.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, size.width * 0.07)
                        Spacer(minLength: 0)
                    }
                }
            }
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        }
        .environment(\.colorScheme, .dark)
    }

    private var canvas: some View {
        ZStack(alignment: .bottomLeading) {
            switch visual {
            case .mill:
                ToolpathCanvas(geometry: ToolpathGeometry(document: Self.millDocument, findings: Self.millFindings),
                               camera: OrbitCamera(yaw: OrbitCamera.isometric.yaw, pitch: OrbitCamera.isometric.pitch, zoom: 1.05),
                               showGrid: true)
            case .lathe:
                ToolpathCanvas(geometry: ToolpathGeometry(document: Self.latheDocument, findings: []),
                               camera: OrbitCamera(yaw: OrbitCamera.isometric.yaw, pitch: OrbitCamera.isometric.pitch, zoom: 1.0))
            }
            badge.padding(size.height * 0.07)
        }
        .background(Color.clear)
        // Fade the canvas into the background on the side facing the text.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                             startPoint: size.width / size.height > 1.6 ? .leading : .top,
                             endPoint: size.width / size.height > 1.6 ? .trailing : .bottom))
    }

    private var badge: some View {
        let danger = visual == .mill
        return HStack(spacing: size.height * 0.02) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: size.height * 0.012)
                Circle().trim(from: 0, to: danger ? 0.75 : 1)
                    .stroke(danger ? TP.Palette.danger : TP.Palette.success, style: StrokeStyle(lineWidth: size.height * 0.012, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(danger ? "75" : "100")
                    .font(.system(size: size.height * 0.045, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: size.height * 0.12, height: size.height * 0.12)
        }
        .padding(size.height * 0.02)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: size.height * 0.04))
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: size.height * 0.035) {
            HStack(spacing: size.height * 0.02) {
                RoundedRectangle(cornerRadius: size.height * 0.012)
                    .fill(TP.Palette.accent)
                    .frame(width: size.height * 0.05, height: size.height * 0.05)
                    .overlay(Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: size.height * 0.028, weight: .bold)).foregroundStyle(.white))
                Text("Toolpath")
                    .font(.system(size: size.height * 0.04, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(headline)
                .font(.system(size: size.height * (size.width / size.height > 1.6 ? 0.085 : 0.07), weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.system(size: size.height * 0.036))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(isRTL ? .trailing : .leading)
    }
}

/// One frame of the header/search video at `time` seconds.
struct CreativeVideoFrame: View {
    let time: Double
    let size: CGSize

    private static let document = GCodeParser().parse(SampleProgram.sign + "\nG0 X60 Y30 Z-1.5\nG0 Z5\n", fileName: "creative")
    private static let geometry = ToolpathGeometry(document: document, findings: GCodeAnalyzer().analyze(document))

    var body: some View {
        // 0–9 s draw-on (eased), then hold; the danger rapid is the last move drawn.
        let raw = min(time / 9, 1)
        let progress = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        let flagged = time >= 9
        let scoreBlend = min(max((time - 9) / 0.8, 0), 1)
        let score = Int((100 - 25 * scoreBlend).rounded())
        let yaw = OrbitCamera.isometric.yaw + 0.45 * sin(time / 15 * .pi * 2) * 0.6
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x23211C), Color(hex: 0x121110)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ToolpathCanvas(geometry: Self.geometry,
                           camera: OrbitCamera(yaw: yaw, pitch: OrbitCamera.isometric.pitch, zoom: 1.0),
                           drawProgress: progress, showGrid: true)
                .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: size.width * 0.6))
            HStack(spacing: size.height * 0.03) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: size.height * 0.014)
                    Circle().trim(from: 0, to: 1 - 0.25 * scoreBlend)
                        .stroke(flagged ? TP.Palette.danger : TP.Palette.success, style: StrokeStyle(lineWidth: size.height * 0.014, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(score)")
                        .font(.system(size: size.height * 0.05, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(width: size.height * 0.14, height: size.height * 0.14)
                if flagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: size.height * 0.06))
                        .foregroundStyle(TP.Palette.danger)
                        .opacity(scoreBlend)
                }
            }
            .padding(size.height * 0.025)
            .background(.black.opacity(0.35), in: .rect(cornerRadius: size.height * 0.045))
            .padding(size.height * 0.07)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Creative copy per page and locale (App Store Connect locale codes).
enum CreativeCopy {
    static let main: [String: (headline: String, sub: String)] = [
        "en-US": ("Check your G-code before you cut", "3D preview, safety checks and feeds & speeds for CNC routers, mills and lathes."),
        "tr": ("Kesmeden önce G-code'unu kontrol et", "CNC router, freze ve tornalar için 3D önizleme, güvenlik kontrolleri, ilerleme ve devir."),
        "de-DE": ("Prüfe deinen G-Code, bevor du fräst", "3D-Vorschau, Sicherheitscheck, Vorschub und Drehzahl für CNC-Fräsen und Drehmaschinen."),
        "es-ES": ("Revisa tu G-code antes de cortar", "Vista 3D, revisiones de seguridad, avances y velocidades para fresadoras CNC y tornos."),
        "it": ("Controlla il G-code prima di tagliare", "Anteprima 3D, controlli di sicurezza, avanzamenti e velocità per frese CNC e torni."),
        "ru": ("Проверьте G-код до начала резки", "3D-просмотр, проверка безопасности и режимы резания для фрезеров и токарных станков с ЧПУ."),
        "ja": ("削る前にGコードをチェック", "CNCルーター・フライス・旋盤のための3Dプレビュー、安全チェック、送り・回転数。"),
        "zh-Hans": ("切削前先检查 G 代码", "为 CNC 雕刻机、铣床和车床提供 3D 预览、安全检查和进给转速。"),
        "ar-SA": ("افحص G-code قبل القطع", "معاينة ثلاثية الأبعاد وفحوص أمان وتغذية وسرعات لماكينات CNC والمخارط."),
    ]

    static let pages: [CreativeRenderer.Page] = [
        .init(id: "main", visual: .mill, copy: main),
        .init(id: "beginners", visual: .mill, copy: [
            "en-US": ("Your first cut, without a broken bit", "Made for 3018 and desktop CNC beginners: see every move, fix mistakes before they happen."),
            "tr": ("İlk kesimin, kırık uç olmadan", "3018 ve masaüstü CNC'ye yeni başlayanlar için: her hareketi gör, hatayı olmadan düzelt."),
        ]),
        .init(id: "machines", visual: .mill, copy: [
            "en-US": ("Tuned to your machine", "Shapeoko, Onefinity, LongMill, X-Carve: checks and feeds use your machine's limits."),
            "tr": ("Makinene göre ayarlı", "Shapeoko, Onefinity, LongMill, X-Carve: kontroller ve değerler makinenin sınırlarıyla."),
        ]),
        .init(id: "checker", visual: .mill, copy: [
            "en-US": ("See the toolpath. Catch the crash.", "Open .nc and .gcode files, preview in 3D and get every dangerous move explained."),
            "tr": ("Takım yolunu gör. Çarpmayı yakala.", ".nc ve .gcode dosyalarını aç, 3D önizle, her tehlikeli hareketin açıklamasını al."),
        ]),
        .init(id: "feeds", visual: .mill, copy: [
            "en-US": ("Feeds & speeds, calculated", "Conservative starting values for 21 materials, capped to your spindle. Never guessed."),
            "tr": ("İlerleme ve devir, hesaplanmış", "21 malzeme için iş milinize göre sınırlanmış temkinli başlangıç değerleri. Tahmin yok."),
        ]),
        .init(id: "business", visual: .mill, copy: [
            "en-US": ("Know what every job costs", "Machine time, material and fees: quote CNC work and track every job you run."),
            "tr": ("Her işin maliyetini bil", "Makine süresi, malzeme ve masraflar: CNC işini fiyatla, çalıştırdığın her işi kaydet."),
        ]),
        .init(id: "alarms", visual: .mill, copy: [
            "en-US": ("GRBL alarm? Solved in seconds", "Look up any ALARM or error code with clear steps, even offline at the machine."),
            "tr": ("GRBL alarmı mı? Saniyeler içinde çöz", "Her ALARM ve hata kodunu net adımlarla bul, makinenin başında internetsiz bile."),
        ]),
        .init(id: "lathe", visual: .lathe, copy: [
            "en-US": ("Check lathe programs before you turn", "G71 roughing, G76 threading and G96 shown pass by pass, with chuck and RPM-limit checks."),
            "tr": ("Tornalamadan önce programını kontrol et", "G71 kaba işleme, G76 diş ve G96 paso paso; ayna ve devir sınırı kontrolleriyle."),
        ]),
    ]
}
#endif
