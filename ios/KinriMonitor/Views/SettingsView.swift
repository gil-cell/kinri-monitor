import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = LoanStore.shared
    @ObservedObject private var alertManager = AlertManager.shared
    @State private var showDisclaimer = false
    @State private var showAlertDetail = false

    var body: some View {
        List {
            // アラート設定
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.warning)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("金利アラート")
                            .font(.system(size: 14, weight: .bold))
                        let count = alertManager.rules.filter(\.isEnabled).count
                        Text(count > 0 ? "\(count)件の指標を監視中" : "未設定")
                            .font(.system(size: 11))
                            .foregroundStyle(count > 0 ? Theme.accent : Theme.textMuted)
                    }

                    Spacer()

                    Button {
                        showAlertDetail = true
                    } label: {
                        Text("設定")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("アラート")
            } footer: {
                Text("バックグラウンドで金利データの更新を検知し、閾値を超えた際にプッシュ通知します。")
                    .font(.caption2)
            }

            Section("アプリ情報") {
                HStack {
                    Text("バージョン"); Spacer()
                    Text("1.0.0").foregroundStyle(.secondary)
                }
                HStack {
                    Text("データソース"); Spacer()
                    Text("日本銀行 時系列統計API").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("更新頻度"); Spacer()
                    Text("毎営業日（8:50頃更新）").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("データ管理") {
                Button("借入条件をリセット", role: .destructive) {
                    store.reset()
                }
            }

            Section {
                Button("免責事項を表示") {
                    showDisclaimer = true
                }
            }

            Section {
                Text(disclaimerText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showAlertDetail) {
            AlertSettingsView()
        }
        .sheet(isPresented: $showDisclaimer) {
            NavigationStack {
                ScrollView {
                    Text(fullDisclaimerText)
                        .font(.caption)
                        .padding()
                }
                .navigationTitle("免責事項")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { showDisclaimer = false }
                    }
                }
            }
        }
    }

    private var disclaimerText: String {
        "このアプリは投資助言・金融アドバイスではなく、公的データに基づく判断材料の提供を目的としています。"
    }

    private var fullDisclaimerText: String {
        """
        【免責事項】

        本アプリ「借入金利モニター」は、日本銀行が公開する時系列統計データを利用し、中小企業の経営者・経理担当者が借入金利の市場動向を把握するための参考情報を提供するアプリケーションです。

        1. 本アプリは投資助言、金融アドバイス、または金融商品の推奨を行うものではありません。

        2. 表示されるデータは日本銀行の公的統計APIから取得したものですが、データの正確性、完全性、最新性を保証するものではありません。

        3. 金利の乖離診断やシミュレーション結果は、あくまで参考値であり、実際の借入条件や返済額を保証するものではありません。

        4. 借入条件の見直しや借り換え等の重要な財務判断を行う際は、必ず金融機関の担当者や税理士、公認会計士等の専門家にご相談ください。

        5. 本アプリの利用により生じた損害について、開発者は一切の責任を負いません。

        6. ユーザーが入力した借入条件等の情報は、端末内にのみ保存され、サーバーには送信されません。

        データソース：日本銀行 時系列統計データ検索サイト
        https://www.stat-search.boj.or.jp/
        """
    }
}

// MARK: - アラート詳細設定画面

struct AlertSettingsView: View {
    @ObservedObject private var alertManager = AlertManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 全体説明
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(Theme.accent)
                            Text("バックグラウンド監視")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text("日銀データの更新タイミング（毎営業日8:50頃）に合わせて自動チェックし、設定した閾値に達した場合に通知します。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                // 各指標のアラート設定
                ForEach($alertManager.rules) { $rule in
                    Section {
                        // ON/OFF トグル
                        Toggle(isOn: $rule.isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.label)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(rule.seriesKey)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        .tint(Theme.accent)
                        .onChange(of: rule.isEnabled) {
                            alertManager.requestPermission()
                            alertManager.saveRulesPublic()
                        }

                        if rule.isEnabled {
                            // 方向（上昇/下降）
                            Picker("条件", selection: $rule.direction) {
                                ForEach(AlertRule.Direction.allCases, id: \.self) { dir in
                                    Text(dir.rawValue).tag(dir)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: rule.direction) {
                                alertManager.saveRulesPublic()
                            }

                            // 閾値
                            HStack {
                                Text("閾値")
                                Spacer()
                                TextField("", value: $rule.threshold, format: .number.precision(.fractionLength(1...3)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .onChange(of: rule.threshold) {
                                        alertManager.saveRulesPublic()
                                    }
                                Text("％")
                                    .foregroundStyle(.secondary)
                            }

                            // 説明
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.info)
                                Text(descriptionFor(rule))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
            }
            .navigationTitle("アラート設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func descriptionFor(_ rule: AlertRule) -> String {
        let dir = rule.direction == .above ? "に達した場合" : "まで下がった場合"
        return "\(rule.label)が\(String(format: "%.2f", rule.threshold))%\(dir)に通知します"
    }
}

// saveRulesPublic を AlertManager に追加するための extension
extension AlertManager {
    func saveRulesPublic() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "alert_rules_v2")
        }
        // サーバーにも同期
        PushManager.shared.syncAlertRules()
    }
}
