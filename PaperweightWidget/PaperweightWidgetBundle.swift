import WidgetKit
import SwiftUI

@main
struct PaperweightWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaperweightWidget()
    }
}

/// Read-only by design. There's no `AppIntent` button anywhere in here: arming
/// from a widget would bypass the apps-selected and unlock-method gates, and
/// disarming would bypass the NFC tap — which is the whole product.
struct PaperweightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PaperweightWidget", provider: PaperweightProvider()) { entry in
            PaperweightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Paperweight")
        .description("How long the quiet lasts.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
