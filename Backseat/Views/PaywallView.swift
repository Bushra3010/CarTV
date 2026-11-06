import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    var reason: String?

    @State private var selected: String = "app.backseat.pro.yearly"
    @State private var busy = false
    @State private var message: String?
    @State private var manage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    benefits
                    if purchases.isPro {
                        proActive
                    } else {
                        plans
                        Button(action: buy) {
                            Group {
                                if busy { ProgressView().tint(.black) } else { Text(ctaTitle).font(.headline) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(product(selected) == nil ? Color.secondary : Color.black)
                        .disabled(busy || product(selected) == nil)
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    footer
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
            }
            .manageSubscriptionsSheet(isPresented: $manage)
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.rear.and.tire.marks")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 88, height: 88)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("Backseat Pro").font(.largeTitle.bold())
            Text(reason ?? "Unlock the full passenger experience.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("car.fill", "Car mode", "Landscape layout with huge controls and one-tap channel switching")
            benefit("list.bullet.rectangle.portrait", "Unlimited playlists", "The free version holds \(Entitlements.freePlaylistLimit). Pro removes the limit")
            benefit("waveform", "Every visualizer style", "Wave and Rings styles for radio and audio streams")
            benefit("heart", "Support an independent app", "No ads, no tracking, no account")
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var plans: some View {
        if purchases.products.isEmpty {
            VStack(spacing: 10) {
                if purchases.isLoading { ProgressView() }
                Text(purchases.loadError ?? "Loading plans…").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !purchases.isLoading { Button("Try again") { Task { await purchases.loadProducts() } } }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 10) {
                ForEach(purchases.products, id: \.id) { p in planRow(p) }
            }
        }
    }

    private func planRow(_ p: Product) -> some View {
        let isSelected = selected == p.id
        return Button { selected = p.id } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : .secondary).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planTitle(p)).font(.headline)
                        if p.id.hasSuffix("yearly") {
                            Text("BEST VALUE").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
                        }
                    }
                    Text(planDetail(p)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(p.displayPrice).font(.headline)
            }
            .padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var proActive: some View {
        VStack(spacing: 10) {
            Label("Pro is active. Thank you!", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
            Button("Manage subscription") { manage = true }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Restore purchases") { restore() }.font(.subheadline)
            Text("Subscriptions renew automatically until cancelled. Cancel at least 24 hours before the end of the period in Settings › Apple Account › Subscriptions. Lifetime is a one-time purchase.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func product(_ id: String) -> Product? { purchases.products.first { $0.id == id } }

    private func planTitle(_ p: Product) -> String {
        if p.id.hasSuffix("weekly") { return "Weekly" }
        if p.id.hasSuffix("yearly") { return "Yearly" }
        return "Lifetime"
    }

    private func planDetail(_ p: Product) -> String {
        if p.type == .nonConsumable { return "Pay once, keep Pro forever" }
        if let intro = p.subscription?.introductoryOffer, intro.paymentMode == .freeTrial {
            return "\(intro.period.value)-day free trial, then \(p.displayPrice) a \(p.id.hasSuffix("yearly") ? "year" : "week")"
        }
        return p.id.hasSuffix("yearly") ? "Billed once a year" : "Billed every week"
    }

    private var ctaTitle: String {
        guard let p = product(selected) else { return "Continue" }
        if let intro = p.subscription?.introductoryOffer, intro.paymentMode == .freeTrial { return "Start free trial" }
        return p.type == .nonConsumable ? "Buy Lifetime" : "Subscribe"
    }

    private func buy() {
        guard let p = product(selected) else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                if try await purchases.purchase(p) { dismiss() }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                try await purchases.restore()
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
