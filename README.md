# Amazon Bedrock 導入プロジェクト

東京リージョンを前提としたAmazon Bedrock環境構築プロジェクト。ユースケースごとに要件詰め→実装を別セッション・別ブランチで進める。

## ドキュメント構成

- [`CLAUDE.md`](./CLAUDE.md) — Claude Codeで作業する際に必ず読ませる指示書
- [`docs/00-architecture-overview.md`](./docs/00-architecture-overview.md) — 全ユースケース共通の設計方針（抽象レベル）
- [`infra/`](./infra/README.md) — アカウント共通Terraform（請求アラーム・Cost allocation tag等、どのユースケースにも属さないシングルトンリソース）
- `docs/01-internal-rag-chatbot/` — ユースケース1: 社内RAGチャットボット
- `docs/02-saas-backend/` — ユースケース2: 自社SaaSバックエンド機能
- `docs/03-dev-tool/` — ユースケース3: 開発者ツール（Claude Code経由）

各ユースケースディレクトリには `requirements.md`（要件・設計）を置く。実装が進んだら同ディレクトリに `architecture.md` や `infra/` を追加していく。

## 進め方

1. `docs/00-architecture-overview.md` を読み、全体方針を把握する
2. 着手するユースケースの `requirements.md` を開き、未決事項（`## 未決事項` セクション）を埋める
3. 要件が固まったら、そのユースケース専用のセッション・ブランチで実装に入る
4. 実装は既存OSSリポジトリ（`docs/00-architecture-overview.md` の「参考リポジトリ」参照）を土台に、Claude Codeで自社の設計方針に合わせて改修する
5. IAMポリシー・Guardrails設定・ログ基盤への変更は、適用前に必ず人間がレビューする（`CLAUDE.md` のルール参照）

## ステータス

| ユースケース | 要件詰め | 実装 |
|---|---|---|
| 01. 社内RAGチャットボット | 未着手 | 未着手 |
| 02. SaaSバックエンド機能 | 未着手 | 未着手 |
| 03. 開発者ツール | 未着手 | 未着手 |
