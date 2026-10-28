import SwiftUI
import WidgetKit

private let pipGreen = Color(red: 0.52, green: 1.0, blue: 0.24)
private let dimGreen = Color(red: 0.25, green: 0.56, blue: 0.14)

struct PipBoyEntry: TimelineEntry {
    let date: Date
}

struct PipBoyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PipBoyEntry {
        PipBoyEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PipBoyEntry) -> Void) {
        completion(PipBoyEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PipBoyEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        let entries = (0..<60).compactMap { minute -> PipBoyEntry? in
            guard let date = calendar.date(byAdding: .minute, value: minute, to: start) else {
                return nil
            }
            return PipBoyEntry(date: date)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PipBoyComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PipBoyEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryCircular:
                circularView
            case .accessoryCorner:
                cornerView
            default:
                rectangularView
            }
        }
        .containerBackground(.black, for: .widget)
        .foregroundStyle(pipGreen)
        .widgetAccentable()
    }

    private var inlineView: some View {
        Label {
            Text("PIP-BOY · RAD 003")
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
        } icon: {
            Image(systemName: "figure.walk")
        }
    }

    private var circularView: some View {
        ZStack {
            Circle()
                .stroke(dimGreen, lineWidth: 2)
            Circle()
                .trim(from: 0.06, to: 0.82)
                .stroke(pipGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 18, weight: .medium))
                Text("87")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pip-Boy health 87 percent")
    }

    private var cornerView: some View {
        VStack(spacing: 0) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .bold))
            Text("AP")
                .font(.system(size: 9, weight: .black, design: .monospaced))
        }
        .widgetLabel {
            Text("ACTION 76")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pip-Boy action points 76")
    }

    private var rectangularView: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(dimGreen, lineWidth: 1)
                Image(systemName: "figure.walk")
                    .font(.system(size: 26, weight: .medium))
            }
            .frame(width: 39)

            VStack(alignment: .leading, spacing: 1) {
                Text("PIP-BOY 3000")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .lineLimit(1)
                Text(entry.date, style: .time)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Label("87", systemImage: "heart.fill")
                    Label("003", systemImage: "dot.radiowaves.left.and.right")
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(dimGreen)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pip-Boy status, health 87, radiation 3")
    }
}

struct PipBoyComplication: Widget {
    static let kind = "dev.develodom.WatchFaceLab.PipBoyComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PipBoyTimelineProvider()) { entry in
            PipBoyComplicationView(entry: entry)
        }
        .configurationDisplayName("Pip-Boy Monitor")
        .description("Vault health, action points, radiation, and time.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
        ])
    }
}

@main
struct PipBoyComplicationBundle: WidgetBundle {
    var body: some Widget {
        PipBoyComplication()
    }
}
