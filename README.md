# 借入金利モニター

中小企業の経営者・経理担当者向けの借入金利モニターアプリです。

日本銀行の公的統計APIから金利関連データを取得し、自社の借入金利が市場平均と比べてどうかを判断するための材料を提供します。

## アーキテクチャ

```
[iOS SwiftUI App]  --HTTPS-->  [Cloudflare Worker API]  --fetch-->  [日銀 時系列統計API]
   端末内に借入条件保存            キャッシュ(KV) + 金利計算ロジック
```

## ディレクトリ構成

```
/
├── worker/          # Cloudflare Worker (TypeScript)
│   ├── src/         # ソースコード
│   ├── test/        # テスト
│   ├── wrangler.toml
│   └── package.json
├── ios/             # iOS App (SwiftUI)
│   └── KinriMonitor/
└── .github/
    └── workflows/   # CI/CD
```

## 免責事項

このアプリは投資助言・金融アドバイスではなく、公的データに基づく判断材料の提供を目的としています。金利に関する重要な判断は、専門家にご相談ください。
