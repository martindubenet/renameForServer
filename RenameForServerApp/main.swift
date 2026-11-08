// RenameForServer.app — native window for rename_for_server.py
//
// Shows the "Rename File for Server" window (file name nomenclature, optional
// AVIF copies switch, counts, Cancel / Execute), writes the choice as JSON to
// the --out file, then quits. Also posts the end-of-task notification (see
// "Notification mode"). Renaming and AVIF encoding stay in rename_for_server.py.
//
// Arguments (all "--key value"):
//   --files <n>    number of selected files
//   --images <n>   how many of them are images (0 hides the AVIF option)
//   --avif <1|0>   initial state of the switch
//   --out <path>   where to write {"cancelled":…, "avif":…}
//
// Build with build_app.sh (needs the Xcode Command Line Tools).

import AppKit
import SwiftUI
import UserNotifications

let WINDOW_TITLE = "Rename File for Server"

// MARK: - Arguments

struct Args {
    var files = 0
    var images = 0
    var avif = false
    var out: URL?
}

func parseArgs() -> Args {
    var args = Args()
    var items = CommandLine.arguments.dropFirst().makeIterator()
    while let key = items.next() {
        guard key.hasPrefix("--"), let value = items.next() else { continue }
        switch key {
        case "--files": args.files = Int(value) ?? 0
        case "--images": args.images = Int(value) ?? 0
        case "--avif": args.avif = (value == "1")
        case "--out": args.out = URL(fileURLWithPath: value)
        default: break
        }
    }
    return args
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var avif: Bool
    let files: Int
    let images: Int

    init(args: Args) {
        files = args.files
        images = args.images
        avif = args.avif && args.images > 0
    }

    /// AVIF copies only matter when the selection has images.
    var avifActive: Bool { avif && images > 0 }

    var result: [String: Any] { ["avif": avifActive] }
}

// MARK: - View

enum Field: Hashable {
    case submit, avif, cancel
}

/// Icon + title + caption line, with an accessory (count or switch) on the right.
struct OptionRow<Accessory: View>: View {
    let symbol: String
    var symbolWeight: Font.Weight = .regular
    let title: String
    let caption: String
    let accessory: Accessory

    init(symbol: String, symbolWeight: Font.Weight = .regular, title: String, caption: String,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.symbolWeight = symbolWeight
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: symbolWeight))
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

/// "Label ........ 99" line of the counts block.
struct CountRow: View {
    let label: String
    let value: Int
    var bold = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "\(value)")  // verbatim: no "1,234" grouping
                .fontWeight(bold ? .semibold : .regular)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var focus: Field?

    private var order: [Field] {
        model.images > 0 ? [.submit, .avif, .cancel] : [.submit, .cancel]
    }

    var body: some View {
        DialogLayout(width: 530) {
            VStack(alignment: .leading, spacing: 16) {
                OptionRow(symbol: "textformat.characters.dottedunderline",
                          title: "Change file name nomenclature",
                          caption: "Remove white spaces, use server compliant characters, etc…") {
                    if !model.avifActive {
                        Text(verbatim: "\(model.files) file(s)")
                            .foregroundStyle(.secondary)
                    }
                }
                if model.images > 0 {
                    OptionRow(symbol: "photo.badge.plus", symbolWeight: .ultraLight,
                              title: "Duplicate selected image(s) as .AVIF file format",
                              caption: "The original image file will NOT be renamed.") {
                        DialogSwitch(label: "Duplicate as AVIF", isOn: $model.avif)
                            .focused($focus, equals: .avif)
                    }
                }
                if model.avifActive {
                    Divider()
                    VStack(spacing: 4) {
                        // AVIF on: the original images keep their name, only the other files are renamed.
                        CountRow(label: "Renamed existing files", value: model.files - model.images)
                        CountRow(label: "New AVIF image files added", value: model.images)
                        CountRow(label: "Total", value: model.files, bold: true)
                    }
                }
            }
        } leading: {
            EmptyView()
        } trailing: {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .cancel)
            Button("Execute", action: onSubmit)
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .submit)
        }
        .modifier(TabOrder(order: order, focus: $focus))
    }
}

// MARK: - Shared dialog building blocks (same in the 3 apps, matches the Figma "_Modal")

/// Window chrome of the dialogs: close (= Cancel) and minimize enabled, zoom disabled.
@MainActor
func makeDialogWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
    let controller = NSHostingController(rootView: rootView)
    controller.sizingOptions = .preferredContentSize  // window follows the content height
    let window = NSWindow(contentViewController: controller)
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.title = title
    window.standardWindowButton(.zoomButton)?.isEnabled = false  // no full screen for a dialog
    window.isReleasedWhenClosed = false
    window.level = .floating  // stay above the Finder window it was launched from
    window.center()
    return window
}

/// Main content (40 pt side margins) above the footer actions (20 pt margins):
/// optional leading actions on the left, Cancel / primary action on the right.
struct DialogLayout<Content: View, Leading: View, Trailing: View>: View {
    let width: CGFloat
    let content: Content
    let leading: Leading
    let trailing: Trailing

    init(width: CGFloat,
         @ViewBuilder content: () -> Content,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.width = width
        self.content = content()
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            HStack(spacing: 8) {
                leading
                Spacer()
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)  // 20 + 12 = 32 pt between the switches and the buttons
            .padding(.bottom, 20)
        }
        .frame(width: width)
    }
}

/// "Label ............ value" line (label primary, value secondary, right aligned).
struct ValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Small switch with its label hidden visually but kept for VoiceOver.
struct DialogSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

/// Cycles the focus through `order` with Tab / Shift-Tab (default action button first).
struct TabOrder<Field: Hashable>: ViewModifier {
    let order: [Field]
    var focus: FocusState<Field?>.Binding

    func body(content: Content) -> some View {
        content
            // Shift-Tab can arrive as the "backtab" character (U+0019) instead of Tab + Shift.
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                guard !order.isEmpty else { return .ignored }
                let backward = press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}")
                let index = focus.wrappedValue.flatMap { order.firstIndex(of: $0) }
                    ?? (backward ? 0 : order.count - 1)
                focus.wrappedValue = order[(index + (backward ? order.count - 1 : 1)) % order.count]
                return .handled
            }
            .onAppear {
                // Start on the first field; deferred so the window is key before focus is set.
                DispatchQueue.main.async { focus.wrappedValue = order.first }
            }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let args = parseArgs()
    lazy var model = Model(args: args)
    var window: NSWindow!
    var finished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = ContentView(
            model: model,
            onCancel: { [unowned self] in self.finish(cancelled: true) },
            onSubmit: { [unowned self] in self.finish(cancelled: false) }
        )
        window = makeDialogWindow(title: WINDOW_TITLE, rootView: view)
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Write the result for the Python script (once), then quit.
    func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        var result: [String: Any] = ["cancelled": cancelled]
        if !cancelled { result.merge(model.result) { $1 } }
        if let out = args.out, let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: out)
        }
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(cancelled: true)  // red close button = Cancel
    }
}

// MARK: - Notification mode

/// "--notify-title T --notify-body B --out F": post one macOS notification under
/// this app's name (instead of Script Editor's), write {"posted": true|false} to F, quit.
struct NotifyRequest {
    let title: String
    let body: String
    let out: URL?

    static func fromArguments() -> NotifyRequest? {
        var title: String?
        var body = ""
        var out: URL?
        var items = CommandLine.arguments.dropFirst().makeIterator()
        while let key = items.next() {
            guard key.hasPrefix("--"), let value = items.next() else { continue }
            switch key {
            case "--notify-title": title = value
            case "--notify-body": body = value
            case "--out": out = URL(fileURLWithPath: value)
            default: break
            }
        }
        return title.map { NotifyRequest(title: $0, body: body, out: out) }
    }
}

/// Asks macOS to show the banner even though this app is frontmost at that moment
/// (by default, notifications of the active app only go to Notification Center).
final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

@MainActor
final class Notifier: NSObject, NSApplicationDelegate {
    let request: NotifyRequest
    let presenter = BannerPresenter()
    var finished = false

    init(request: NotifyRequest) {
        self.request = request
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            finish(posted: await post())
        }
        Task { @MainActor in
            // Give up if the first-time permission prompt is left unanswered.
            try? await Task.sleep(for: .seconds(60))
            finish(posted: false)
        }
    }

    private func post() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        do {
            // First run only: macOS asks whether this app may send notifications.
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                       content: content, trigger: nil))
            // Stay alive a moment so macOS can ask the delegate how to present it.
            try? await Task.sleep(for: .seconds(1.5))
            return true
        } catch {
            return false  // e.g. notifications refused for this (locally signed) app
        }
    }

    /// Write the result for the Python script (once), then quit; the notification stays.
    private func finish(posted: Bool) {
        guard !finished else { return }
        finished = true
        if let out = request.out, let data = try? JSONSerialization.data(withJSONObject: ["posted": posted]) {
            try? data.write(to: out)
        }
        NSApp.terminate(nil)
    }
}

/// Launched with no arguments (e.g. by a click on one of its notifications): nothing to do.
@MainActor
final class Quitter: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

// Top-level code runs on the main thread; tell the compiler so it can create the
// @MainActor delegates synchronously.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate  // kept alive by this scope while app.run() blocks
    if let request = NotifyRequest.fromArguments() {
        delegate = Notifier(request: request)
    } else if CommandLine.arguments.contains("--out") {
        delegate = AppDelegate()
    } else {
        delegate = Quitter()
    }
    app.delegate = delegate
    app.run()
}
