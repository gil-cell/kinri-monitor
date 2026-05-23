import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = LoanStore.shared
    @ObservedObject private var alertManager = AlertManager.shared
    @State private var showDisclaimer = false

    var body: some View {
        List {
            // アラート設定
            Section {
                Toggle("金利アラート", isOn: $alertManager.alertEnabled)
                    .tint(.blue)
                    .onChange(of: alertManager.alertEnabled) {
                        if alertManager.alertEnabled {
                            alertManager.requestPermission()
                        }
                    }

                if alertManager.alertEnabled {
                    HStack {
                        Text("コールレート閾値")
                        Spacer()
                        TextField("", value: $alertManager.callRateThreshold, format: .number.precision(.fractionLength(1...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("％")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("貸出金利閾値")
                        Spacer()
                        TextField("", value: $alertManager.lendingRateThreshold, format: .number.precision(.fractionLength(1...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("％")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("アラート")
            } footer: {
                Text("アプリ起動時に最新金利をチェックし、閾値を超えた場合に通知します。")
                    .font(.caption2)
            }

            Section("アプリ情報") {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("データソース")
                    Spacer()
                    Text("日本銀行 時系列統計API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("更新頻度")
                    Spacer()
                    Text("毎営業日（8:50頃更新）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 将来の StoreKit2 サブスクはここに差し込む
            // Section("プレミアムプラン") { ... }

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
