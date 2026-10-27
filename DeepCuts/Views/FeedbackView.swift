import PhotosUI
import SwiftUI
import UIKit

/// "Suggest a change": goes to the tester-feedback endpoint. From TestFlight it starts a build
/// session on Jack's Mac; from the App Store it goes to Jack.
struct FeedbackView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let context: String
    var title = Distribution.isTestFlight ? "Suggest a change" : "Send feedback"
    var pitch: String? = Distribution.isTestFlight
        ? "Add a genre, fix a wrong answer, change how something works. Jack's build assistant picks it up right away and sends a new TestFlight build, usually within the hour."
        : nil
    var placeholder = Distribution.isTestFlight
        ? "For example: Add a crate for '50s rock and roll, Elvis, Chuck Berry, Buddy Holly."
        : "What should we fix or add?"
    /// The question and answer being reported, shown above the text box.
    var reported: (prompt: String, answer: String)?

    @State private var text = ""
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if sent { confirmation } else { form }
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                if !sent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            name = app.progress.data.testerName
            focused = true
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Theme.display(30)).foregroundStyle(Theme.ink)
                    if let pitch {
                        Text(pitch)
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)

                if let reported { ReportedQuestion(prompt: reported.prompt, answer: reported.answer) }

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(Theme.inkSoft.opacity(0.7))
                            .padding(.horizontal, 17).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("feedback-text")
                }
                .font(.body)
                .card()

                TextField("Your name (optional)", text: $name)
                    .textContentType(.name)
                    .padding(14)
                    .card()

                let attached = screenshot
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photo, matching: .screenshots) {
                        AttachLabel(image: attached)
                    }
                    .buttonStyle(.plain)
                    if screenshot != nil {
                        Button("Remove") { photo = nil; screenshot = nil }.font(.subheadline)
                    }
                }
                .padding(14)
                .card()
                .foregroundStyle(Theme.accent)
                .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        // Pinned so it rides above the keyboard.
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await send() }
            } label: {
                if sending { ProgressView().tint(.white) } else { Text("Send to Jack") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: canSend ? Theme.accent : Theme.rule, text: canSend ? .white : Theme.inkSoft))
            .disabled(!canSend || sending)
            .accessibilityIdentifier("feedback-send")
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
            .background(Theme.paper)
        }
    }

    private var canSend: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }

    private var confirmation: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 56, weight: .light)).foregroundStyle(Theme.accent)
            Text("Sent").font(Theme.display(34)).foregroundStyle(Theme.ink)
            Text(Distribution.isTestFlight
                 ? "Jack's build assistant is on it. Follow along under You, then Suggestions."
                 : "Thanks. Jack reads every one.")
                .font(.body).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.ink, text: Theme.paper))
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 16)
                .accessibilityIdentifier("feedback-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feedback-sent")
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        screenshot = image
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        app.progress.setTesterName(name.trimmingCharacters(in: .whitespacesAndNewlines))
        let info = Bundle.main.infoDictionary
        let device = UIDevice.current
        let draft = FeedbackDraft(
            installID: app.progress.data.installID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            context: [
                "version": info?["CFBundleShortVersionString"] as? String ?? "",
                "build": info?["CFBundleVersion"] as? String ?? "",
                "screen": context,
                "device": device.model,
                "os": "\(device.systemName) \(device.systemVersion)",
                "crates": app.progress.focus.joined(separator: ","),
                "text_size": UIApplication.shared.preferredContentSizeCategory.rawValue,
                "channel": Distribution.channel,
            ],
            screenshot: screenshot.flatMap(Self.encode))
        do {
            let id = try await app.feedback.send(draft)
            app.progress.rememberFeedback(id)
            withAnimation(.snappy) { sent = true }
            await app.refreshFeedback()
        } catch {
            self.error = "Couldn't send: \(error.localizedDescription) Try again in a minute."
        }
    }

    /// Downscaled JPEG, base64, small enough for the endpoint's 1.5 MB cap.
    private static func encode(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.7
        while quality > 0.2 {
            if let data = resized.jpegData(compressionQuality: quality), data.count < 1_000_000 { return data.base64EncodedString() }
            quality -= 0.15
        }
        return nil
    }
}

private struct ReportedQuestion: View {
    let prompt: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reporting").font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1)
                .foregroundStyle(Theme.inkSoft)
            Text(prompt).font(.body).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Answer:").foregroundStyle(Theme.inkSoft)
                Text(answer).fontWeight(.semibold).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback-reported")
    }
}

private struct AttachLabel: View {
    let image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 44, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Screenshot attached").foregroundStyle(Theme.ink)
            } else {
                Image(systemName: "photo.badge.plus").font(.title3)
                Text("Attach a screenshot (optional)")
            }
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .contentShape(Rectangle())
    }
}
