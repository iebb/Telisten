import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct LoginView: View {
    @Bindable var model: AppModel
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var email = ""
    @State private var emailCode = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case phone
        case code
        case email
        case emailCode
        case password
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brand
                    hero
                    if model.hasCredentials {
                        authorizationFlow
                    } else {
                        missingConfiguration
                    }
                    Spacer(minLength: 56)
                }
                .frame(maxWidth: 460, minHeight: geometry.size.height, alignment: .topLeading)
                .padding(.horizontal, 30)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.telistenBackground)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            ApplicationIconView(size: 26, cornerRadius: 6)
            Text("MUSIC PLAYER")
                .font(.caption.weight(.bold))
                .tracking(2.2)
            Spacer()
            if model.isAddingAccount {
                Spacer()
                Button("Cancel") {
                    Task { await model.cancelAddingAccount() }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.telistenAccent)
                .disabled(model.isLoading || model.isCancellingAccount)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your music,\neverywhere.")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .minimumScaleFactor(0.8)
            Text("A private player for every track already living in your Telegram account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.top, 72)
        .padding(.bottom, 46)
    }

    private var missingConfiguration: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Connect Telegram", detail: "Local Telegram configuration is missing.")
            Text("Add TELEGRAM_API_ID and TELEGRAM_API_HASH to the gitignored .env file, run Scripts/generate-local-config.sh, then relaunch the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var authorizationFlow: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch model.phase {
            case .signedOut:
                if model.qrCodeLoginState == .idle {
                    sectionTitle("Sign in", detail: "Enter your number in international format.")
                    underlinedField("PHONE NUMBER", focused: focusedField == .phone) {
                        TextField("+81 90 1234 5678", text: $phone)
                            .font(.title3.weight(.medium))
                            .focused($focusedField, equals: .phone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            #endif
                    }
                    primaryButton("Send code", symbol: "arrow.right", disabled: phone.isEmpty) {
                        await model.requestCode(phone: phone)
                    }
                    Button {
                        focusedField = nil
                        Task { await model.startQRCodeLogin() }
                    } label: {
                        Label("Sign in with QR code", systemImage: "qrcode")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.telistenAccent)
                    .disabled(model.isLoading)
                } else {
                    qrCodeAuthorization
                }

            case let .code(_, hint, isEmail):
                sectionTitle(isEmail ? "Check your email" : "Enter your code", detail: hint)
                underlinedField("LOGIN CODE", focused: focusedField == .code) {
                    TextField("Code", text: $code)
                        .font(.title3.weight(.medium))
                        .focused($focusedField, equals: .code)
                        #if os(iOS)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        #endif
                }
                primaryButton("Continue", symbol: "arrow.right", disabled: code.isEmpty) {
                    await model.submitCode(code)
                }
                restartButton

            case .emailAddress:
                sectionTitle("Secure your login", detail: "Telegram requires an email address it can verify before continuing.")
                underlinedField("EMAIL ADDRESS", focused: focusedField == .email) {
                    TextField("name@example.com", text: $email)
                        .font(.title3.weight(.medium))
                        .focused($focusedField, equals: .email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                primaryButton("Send email code", symbol: "arrow.right", disabled: email.isEmpty) {
                    await model.submitLoginEmail(email)
                }
                restartButton

            case let .emailVerification(email, hint):
                sectionTitle("Verify your email", detail: hint)
                underlinedField("VERIFICATION CODE", focused: focusedField == .emailCode) {
                    TextField("Code", text: $emailCode)
                        .font(.title3.weight(.medium))
                        .focused($focusedField, equals: .emailCode)
                        #if os(iOS)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        #endif
                }
                primaryButton("Verify \(email)", symbol: "arrow.right", disabled: emailCode.isEmpty) {
                    await model.submitEmailVerification(emailCode)
                }
                restartButton

            case let .password(hint):
                sectionTitle("Two-step verification", detail: hint.isEmpty ? "Enter your Telegram password." : "Hint: \(hint)")
                underlinedField("PASSWORD", focused: focusedField == .password) {
                    SecureField("Password", text: $password)
                        .font(.title3.weight(.medium))
                        .focused($focusedField, equals: .password)
                        .textContentType(.password)
                }
                primaryButton("Unlock", symbol: "arrow.right", disabled: password.isEmpty) {
                    await model.submitPassword(password)
                }
                restartButton

            default:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to Telegram…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var qrCodeAuthorization: some View {
        switch model.qrCodeLoginState {
        case .idle:
            EmptyView()

        case .loading:
            sectionTitle("Link this device", detail: "Creating a fresh Telegram session…")
            HStack(spacing: 12) {
                ProgressView()
                Text("Requesting secure QR code")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            qrPhoneFallback

        case let .waiting(url, expiresAt, status):
            sectionTitle(
                "Link this device",
                detail: "On a signed-in device, open Telegram Settings → Devices → Link Desktop Device, then scan this code."
            )
            HStack {
                Spacer(minLength: 0)
                TelegramLoginQRCodeView(url: url)
                    .frame(width: 218, height: 218)
                    .accessibilityLabel("Telegram login QR code")
                Spacer(minLength: 0)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(expiresAt.timeIntervalSince(context.date).rounded(.up)))
                HStack(spacing: 7) {
                    Image(systemName: status == nil ? "lock.shield" : "wifi.exclamationmark")
                    Text(status ?? (seconds > 0 ? "Refreshes in \(seconds)s" : "Refreshing…"))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 20) {
                Button("Refresh code") {
                    Task { await model.refreshQRCodeLogin() }
                }
                ShareLink(item: url) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.telistenAccent)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            qrPhoneFallback

        case let .failed(message):
            sectionTitle("QR sign-in paused", detail: message)
            primaryButton("Try again", symbol: "arrow.clockwise", disabled: false) {
                await model.refreshQRCodeLogin()
            }
            qrPhoneFallback
        }
    }

    private var qrPhoneFallback: some View {
        Button("Use phone number instead") {
            Task {
                await model.usePhoneNumberLogin()
                focusedField = .phone
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func underlinedField<Content: View>(
        _ label: String,
        focused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(focused ? Color.telistenAccent : .secondary)
                .tracking(1.2)
            content()
                .textFieldStyle(.plain)
                .padding(.vertical, 3)
            Rectangle()
                .fill(focused ? Color.telistenAccent : Color.secondary.opacity(0.35))
                .frame(height: focused ? 2 : 1)
                .animation(.easeOut(duration: 0.16), value: focused)
        }
    }

    private var restartButton: some View {
        Button("Use another phone number") {
            code = ""
            password = ""
            email = ""
            emailCode = ""
            focusedField = .phone
            Task { await model.restartLogin() }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .disabled(model.isLoading)
    }

    private func primaryButton(
        _ title: String,
        symbol: String,
        disabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if model.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                    Spacer()
                    Image(systemName: symbol)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(disabled || model.isLoading)
    }

}

struct ApplicationIconView: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        applicationIcon
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var applicationIcon: Image {
        #if os(iOS)
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconName = (primaryIcon?["CFBundleIconFiles"] as? [String])?.last ?? "Appicon60x60"
        if let image = UIImage(named: iconName) {
            return Image(uiImage: image)
        }
        return Image("Appicon")
        #elseif os(macOS)
        return Image(nsImage: NSApplication.shared.applicationIconImage)
        #endif
    }
}
