# Claude Code 指示書

このリポジトリで作業する際は、作業開始前に必ず以下を守ること。

## 読む順番

1. `docs/00-architecture-overview.md` — 全ユースケース共通の設計方針（必読）
2. 今回対象のユースケースディレクトリ（`docs/0X-xxx/requirements.md`）— そのユースケース固有の要件・Guardrailsプロファイル・採用リポジトリ

**他のユースケースディレクトリの内容は読み込まない・参照しない。** ユースケースごとに要件やGuardrails方針が異なるため、混同すると誤った前提で実装してしまう。

## 作業スコープの原則

- 1セッション = 1ユースケース = 1ブランチ。複数ユースケースを同時に触らない
- `docs/00-architecture-overview.md` の内容（IAMロールモデル、リージョン方針、ログ/コスト管理の必須要件）は全ユースケース共通の前提として変更しない。変更が必要と判断した場合は、実装を進めず先にユーザーに確認する
- 対象ユースケースの `requirements.md` に `## 未決事項` が残っている場合、その項目に関わる実装判断をする前に必ずユーザーに確認する（勝手に決めて実装を進めない）

## 変更前に必ず人間レビューを挟む対象

以下は自動適用（`terraform apply` / `cdk deploy` 等）せず、diffを提示してユーザーの確認を得ること。

- IAMポリシー・ロールの新規作成/変更（特に `bedrock:InvokeModel` 系アクションの許可範囲）
- Guardrailsの設定内容（Content filters、Denied topics、PII filters、Contextual grounding）
- ログ出力先（S3バケットポリシー、KMSキー、CloudWatch Logsのアクセス権限）
- コスト管理設定（Budgets のしきい値、Application Inference Profileのタグ付け）

## 実装方針

- IaCツールは Terraform に統一する（`aws-ia/terraform-aws-bedrock` を共通モジュールの土台とする）
- 各ユースケースの実装は `docs/0X-xxx/requirements.md` に記載された採用リポジトリ・参考実装をベースに、`docs/00-architecture-overview.md` の共通方針（IAMロール分離、ログ必須化、Guardrails必須化）に合わせて改修する
- 迷ったら実装を進めず、ユーザーに質問する
