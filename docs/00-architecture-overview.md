# Bedrock導入 全体設計方針（共通・抽象レベル）

このドキュメントは全ユースケースに共通する方針のみを記載する。ユースケース固有の要件・Guardrailsの中身・採用リポジトリは各 `docs/0X-xxx/requirements.md` に記載する。

## 0. アカウント方針（確定）

- **複数ユースケース（01, 02, 03...）は単一AWSアカウントで運用する**（アカウント分離はしない）
  - 理由: 個人/家庭規模のPoCであり、複数アカウント（AWS Organizations等）のセットアップ・継続的な運用コストに見合わない
- この決定に伴う実装上の含意:
  - **アカウント×リージョン単位のシングルトンリソース**（Model invocation logging設定、CloudWatch Billing Alarm、Cost allocation tagのアクティブ化等）は、ユースケースごとに重複作成せず、**共有Terraformとして1箇所で管理する**。どのユースケースのTerraformにも属さない、アカウント共通の基盤として切り出すこと（未着手・下記7章の未決事項）
  - Admin/Developer/Auditorロール（2章）も本来アカウント共通の型であり、将来的に共有moduleへ統合する。ユースケース01の実装では暫定的にユースケース名を含めた命名で個別作成しているが、これは正式な設計ではなく移行対象
  - 上記の共有化が完了するまでの間、各ユースケースの `requirements.md` / Terraformには「このリソースはアカウント全体のシングルトンである」旨を明記し、他ユースケースでの重複適用を防ぐこと

## 1. リージョン方針

- 東京リージョン（ap-northeast-1）を基本とする
- 多くのClaudeモデルは東京でIn-Region推論に非対応のため、推論プロファイル（`jp.anthropic.*` または `global.*`）経由での呼び出しが前提になる
- データ主権要件があるユースケースでは `jp.anthropic.*`（JP Geo推論プロファイル、東京・大阪限定）を明示的に使う。ない場合は `global.*` も選択肢
- どちらを使うかはユースケースごとに `requirements.md` で判断する

## 2. IAMロールモデル（共通の型）

役割を分離する。具体的なポリシー内容・ロール名はユースケースごとに定義するが、以下の型は共通とする。

| ロール種別 | 役割 | 付与対象 |
|---|---|---|
| Admin | Model access申請、Guardrails管理、ログ/Budgets設定変更 | 少数の管理者のみ（日常運用では使わない） |
| Developer | 検証目的のモデル呼び出し | 開発者（Guardrails必須の条件付き） |
| AppRuntime | 特定モデル・特定Guardrailのみ呼び出し | アプリケーション実行ロール（ユースケース単位で個別発行） |
| Auditor | ログ閲覧のみ | セキュリティ・監査担当 |

- 長期アクセスキーは発行しない（IAM Identity Center経由のSSO一時認証情報 / アプリはIAMロール）
- AppRuntimeロールは **1ユースケース=1ロール** とし、コスト配分・監査ログの追跡単位を一致させる

## 3. ログ・監査（必須要件）

以下は全ユースケース共通で必須とする。ユースケースごとの差分（保持期間・PIIマスキングの厳しさ等）は各 `requirements.md` に記載する。

- CloudTrail専用証跡を作成し、ログバケットは実行環境と権限分離する
- Model invocation logging を有効化し、CloudWatch LogsとS3の両方に出力する（デフォルトでは無効なので明示的に設定する）
- ログへの読み取り権限はAuditorロールのみに付与する

## 4. コスト管理（必須要件）

- AWS Budgetsでサービス別（Bedrock）予算としきい値アラートを設定する
- 複数ユースケースが存在する前提のため、Application Inference Profileでユースケース単位にコストタグを分離する
- Cost allocation tagsを有効化し、Cost Explorerでユースケース別に集計できるようにする

## 5. Guardrails（必須要件・ただし中身はユースケースごとに設計）

**Guardrails自体は全ユースケースで必須とするが、設定内容（Content filters強度、Denied topics、PII filters、Contextual grounding）は使う人・扱うデータ・想定リスクに応じてユースケースごとに個別設計する。** 1つの設定を使い回さない。

各ユースケースの `requirements.md` で以下を必ず決める:
- Content filtersの強度（カテゴリ別）
- Denied topics（業務外話題の制限が必要か）
- PII filters（検出時にブロックかマスクか、どのエンティティを対象にするか）
- Contextual grounding check（RAG構成の場合は必須で検討）
- IAM側での強制方法（`bedrock:GuardrailIdentifier` 条件キーでのDeny、またはアカウントレベル強制）

## 6. 参考リポジトリ（土台候補）

実装時の出発点として検討する。採用可否・カスタマイズ方針は各ユースケースの `requirements.md` に記載する。

- `aws-ia/terraform-aws-bedrock` — Bedrock公式Terraformモジュール（Guardrails/IAM/Knowledge Base対応）。共通土台の第一候補
- `aws-samples/sample-bedrock-knowledge-base-terraform` — S3/OpenSearch Serverless/Knowledge BaseのRAG構成
- `aws-samples/terraform-rag-template-using-amazon-bedrock` — アプリ組み込み寄りのRAGテンプレート
- `aws-samples/sample-bedrock-guardrails-security-lake` — GuardrailsイベントのCloudWatch/Security Lake集約（CDK）
- `aws-samples/detect-guardrails-not-used-on-amazon-bedrock-inference-calls` — Guardrails未使用呼び出しの検知

## 7. 未決事項（全体）

- IaCツールの最終統一（Terraformを基本方針とするが、Guardrails監視系はCDKサンプルが多く混在しうる）
- ~~複数ユースケースを単一AWSアカウントで運用するか、アカウント分離するか~~ → **単一アカウント運用に決定**（0章参照）
- **共有アカウントリソースの切り出し**: ユースケース01の実装時点では、アカウント全体のシングルトンリソース
  （`aws_bedrock_model_invocation_logging_configuration`、CloudWatch Billing Alarm、
  `aws_ce_cost_allocation_tag`）とAdmin/Developer/Auditorロールが、暫定的にユースケース01の
  Terraform（`docs/01-internal-rag-chatbot/infra`）内に「他ユースケースで重複適用しないよう注意」という
  コメント付きで同居している。これらを独立した共有Terraform（例: `docs/00-architecture-overview/infra`
  等）に切り出し、各ユースケースから参照する形にリファクタリングする作業が未着手
