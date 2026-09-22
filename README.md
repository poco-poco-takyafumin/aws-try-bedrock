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
| 01. 社内RAGチャットボット | 完了 | **Phase A完了**（Knowledge Base/Guardrails/IAM/ログ基盤、2026-09-21 apply済み）。**Phase B着手中**（詳細は下記TODO） |
| 02. SaaSバックエンド機能 | 未着手 | 未着手 |
| 03. 開発者ツール | 未着手 | 未着手 |

### 01. 社内RAGチャットボット — Phase B TODO

Phase A（インフラ骨格）はapply済み。Phase Bでは、プレースホルダーのまま残っている2つのLambda
（`modules/gdrive_sync`, `modules/backend`）に実際のロジックを実装し、実際に使えるチャットボットにする。

- [x] Phase A: インフラ骨格一式（Knowledge Base / OpenSearch Serverless / Guardrails / IAM / ログ基盤）を`terraform apply`（2026-09-21）
- [x] B-1. Google Drive同期Lambda実装（`modules/gdrive_sync/src/handler.py`）— サービスアカウント認証（ドメイン全体委譲・`drive.readonly`）→ 対象フォルダのファイル一覧取得 → S3バケットへ同期（`terraform apply`・実機での動作確認はB-2で実施）
- [ ] B-2. Knowledge Base取り込み動作確認（S3同期後のingestion job実行・文書が検索できることを確認）
- [ ] B-3. チャットバックエンドLambda実装（`modules/backend/src/handler.py`）— `bedrock:RetrieveAndGenerate` + Guardrail呼び出し + citation付与
- [ ] B-4. API Gateway認証方式の決定・実装（**未決事項・要ユーザー確認**。Phase Aは暫定でAWS_IAM認証。Slack/ChatUI/CLI/プログラムそれぞれに適した方式を設計する）
- [ ] B-5. E2E動作確認（実際に文書を同期し、チャットで質問して出典付きの回答が返ることを確認）

進め方の詳細は [`docs/01-internal-rag-chatbot/requirements.md`](./docs/01-internal-rag-chatbot/requirements.md)（未決事項含む）と
[`docs/01-internal-rag-chatbot/infra/README.md`](./docs/01-internal-rag-chatbot/infra/README.md) を参照。

## 横断issue

アカウント共通基盤に関わる、特定ユースケースに閉じないissue。

| issue | 内容 | 状態 |
|---|---|---|
| [#2](https://github.com/poco-poco-takyafumin/aws-try-bedrock/issues/2) | Admin/Developer/Auditorロールのアカウント共通化を設計する | 未着手 |
