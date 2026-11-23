import SwiftUI

/// Podgląd UI bez paska menu: SELFCONTROL_SNAPSHOT=/katalog ./SelfControlApp
@MainActor
enum Snapshot {
    static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["SELFCONTROL_SNAPSHOT"] else { return }
        for tab in Tab.allCases {
            let view = RootView(initialTab: tab).environmentObject(model)
                .background(Color(nsColor: .windowBackgroundColor))
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tab.rawValue).png"))
            }
        }
        exit(0)
    }
}
