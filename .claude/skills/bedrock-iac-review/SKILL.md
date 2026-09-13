---
name: bedrock-iac-review
description: このリポジトリのAmazon Bedrock Terraform実装（docs/0X-*/infra）向けのドメイン固有レビューチェックリスト。IAMの最小権限・Guardrail強制パターン、KMS鍵の権限付与、CloudWatch/CloudTrailログとPIIマスキングの網羅性、コスト配分タグ、Terraformの再発しやすい落とし穴（不安定なARN、providerのアンチパターン、モジュール間デフォルト値の乖離）を扱う。Bedrock Knowledge Base・Guardrails・IAMロール・CloudTrail/CloudWatchログ・KMSキー・コスト配分に関わるTerraformを書く/レビューする際、特に`terraform apply`前や/code-reviewと合わせて使う（CLAUDE.mdによりIAM・Guardrails・ログ出力先・コスト管理のdiffは人間レビュー必須のため）。
---

# Bedrock IaCレビュー

このチェックリストは、本リポジトリ最初のBedrock Terraform実装（`docs/01-internal-rag-chatbot/infra`）に対して`/code-review`を2回実行した際に見つかった指摘を汎用化したもの。同じ間違いをユースケース02/03で再発見しなくて済むようにする。`/code-review`の汎用的なレビューを置き換えるものではなく、**汎用レビューアーが知りようのないプロジェクト固有のパターンを補うためのもの**。

## 使い方

1. `docs/0X-*/infra/**/*.tf` に触れる差分をレビューする際（または`terraform apply`前）、以下の各項目を実際に変更されたファイルに対して1つずつ確認する。スタイルを流し読みするだけで済ませない。
2. 各候補は必ずソースコードを読んで裏取りしてから報告する（Resource/Condition/変数の実際の配線を確認する）。「このクラスのバグは存在する」という記憶だけで指摘しない。
3. `/code-review`と同じ形式で報告する: 確認できたものを`ReportFindings`ツールで`file`・`line`・`summary`・`failure_scenario`・`verdict`とともに報告する。

## IAM: Guardrail強制と最小権限

- **`InvokeModel`だけでなく、Bedrockの呼び出し経路すべてがGuardrailで縛られているか。** アプリが`RetrieveAndGenerate`・`Converse`・`InvokeModelWithResponseStream`等も呼べるなら、それぞれのAllow文に同じ`bedrock:GuardrailIdentifier`（＋`bedrock:GuardrailVersion`）のConditionが必要。`InvokeModel`だけにGuardrail要件を付けても他の経路はカバーされない。
- **`StringNotEquals`の保険的なDenyには、必ず`Null`チェックのDenyを対にする。** IAMの仕様上、条件キーがリクエストに一切存在しない場合`StringNotEquals`は**false**（＝Deny不発火）と評価される。「Guardrail未指定」を拒否したいなら、`Condition = { Null = { "bedrock:GuardrailIdentifier" = "true" } }`という2つ目のDeny文が別途必要。
- **IAM側とアプリコード側で、ID vs ARNが一致しているか。** IAMのConditionがGuardrail/モデルのARNと比較しているなら、Lambdaの環境変数（やSDK呼び出し）も裸のIDではなくARNを渡す必要がある。すべてのConditionキーについて両側を突き合わせて確認する。
- **同じGuardrailを共有するロール全体でバージョン固定の厳しさが揃っているか**（AppRuntime、Developer等）。一方のロールが`GuardrailIdentifier`のみ、もう一方が`GuardrailVersion`もチェック、という差があると、緩い方からDRAFT版や別バージョンを通せてしまう。
- **コスト/ルーティング用のラッパーの横に、生のリソースを許可していないか。** Application Inference Profile（等のラッパー）がコストタグ付けやリージョンルーティングを強制するために存在するなら、基盤モデルARNへの直接`bedrock:InvokeModel`も許可してしまうと、そのラッパーを丸ごと迂回できてしまう。
- **ワイルドカードの管理者権限は、設定変更系アクションかつ対象リソースを絞れているか。** 「Admin」ロールに`Resource = "*"`で`logs:*` / `cloudtrail:*` / `s3:*`を与えると、docs/00がAuditor専用としているログ内容の読み取り系アクション（`GetLogEvents`、`FilterLogEvents`、`StartQuery`、`LookupEvents`、`GetObject`）や、本来1バケットに限定すべきバケットポリシー系アクションまで無自覚に含んでしまう。
- **STSセッションのARNを永続的なPrincipalとして使っていないか。** `data.aws_caller_identity.this.arn`は*その時のapply実行者*のassumed-roleセッションを指し、SSO再ログインやCI実行のたびに変わる。安定したIAMロールARNを使う（モジュールを直接参照すると循環依存になる場合は、ロールの決定的な命名規則から文字列を組み立てる）。

## KMS・暗号化

- **KMSの権限付与は必ず両側を確認する。** SSE-KMSバケットやKMS暗号化されたCloudWatch Logsロググループを読み書きするロールには、`s3:GetObject`/`logs:*`に加えて、そのキーへの`kms:Decrypt`/`kms:GenerateDataKey*`が必要。`s3:GetObject`だけでは復号時に403になる。
- **CloudWatch Logsの鍵ポリシーにはリージョン別サービスプリンシパルが必要**: `logs.<region>.amazonaws.com`であり、素の`logs.amazonaws.com`では不可。これがないとロググループは顧客管理キーで暗号化できない。
- **新しい読み取りロール（Auditor等）にはKMS復号権限を明示的に付与する。** バケットポリシーでの読み取り許可は、KMS復号権限を意味しない。別枠の、忘れやすい許可。

## ログ・PII

- **すべてのログ出力先に同等の保護があるか、なければリスクとして明記する。** CloudWatch LogsとS3の両方へのログ出力が要件で、CloudWatch側にしかマスキング機構がない（例: CloudWatch Logs data protectionにS3側の同等機能はない）場合、コードコメントとユースケースの`requirements.md`の未決事項にその旨を明記する。片方が保護されているからといって両方保護されていると錯覚させない。
- **マスキングポリシーへの`depends_on`を、名前の一致任せにしない。** データ保護/マスキングポリシーがログ設定より先に適用されている必要がある場合は明示的な`depends_on`を追加する。ロググループ名の文字列を共有しているだけでは適用順序は保証されない。
- **正規表現によるPII検出は誤検知率を確認する。** 桁数だけの単純なパターン（例: 銀行口座番号のための`\b\d{7}\b`）は郵便番号や伝票番号にもマッチする。裸のパターンより、直前のラベル/キーワードを要求する形を優先し、その旨をdescriptionに明記する。
- **同一の識別子リストを複数のステートメントに重複記述しない。** 「audit」と「redact」（監査対象と保護対象のペア等）で同じPIIデータ識別子ARNのリストを使うなら、`local`に一本化して両方から参照する。重複記述していると片方だけ編集して乖離することに気づけない。

## コスト管理

- **「Xを有効化しなければならない」という要件には、実際のリソースを対応させる。** docs/00やユースケースの要件で「コスト配分タグを有効化する」等と書かれているなら、そのためのTerraformリソース（例: `aws_ce_cost_allocation_tag`）を追加する。手順書だけの手動対応だと、やり忘れても`plan`/`apply`は何も教えてくれない。
- **モジュール横断の数値デフォルトはルートで一元管理する。** ログ保持日数や予算しきい値等は、各モジュール独自のデフォルト値に暗黙に頼らせず、ルート変数として明示的にすべてのモジュールへ渡す。一部のモジュールだけ違うデフォルト値にサイレントにフォールバックさせない。

## Terraformの一般的な作法

- **設定用変数が、実際にそれを消費するリソースまで配線されているか追跡する。** `vector_dimension`のような変数がOpenSearchのインデックスマッピングにしか使われておらず、肝心のBedrock Knowledge Baseリソース側は埋め込みモデルの既定値を暗黙に使っている、というケースは、変数を変更した時に初めて実行時の不整合として表面化する。必要な箇所すべてに配線されているか確認する。
- **同一apply内で作成されるリソースに設定値が依存するproviderブロックはアンチパターンとして扱う。** `provider "x" {}`ブロックが、同じモジュール/applyで作成されるリソースの属性（例: OpenSearch Serverlessコレクションのエンドポイント）を参照しているのはTerraformの既知の制約。土台リポジトリからの移植で構造を変える価値がない場合は、初回デプロイ時の2段階`apply -target=...`による回避手順を明記する。
- **認証なしの新規公開エンドポイントを作らない。** このプロジェクトで新設するAPI GatewayルートやALBリスナー等には、最初から明示的な認証方式（`AWS_IAM`、JWT、Lambda authorizer等）を設定する。「Phase Aの暫定」を理由に無認証のチャット/RAGエンドポイントを出荷しない。
- **アカウント/リージョン単位のシングルトンリソースは目立つように明記する。** `aws_bedrock_model_invocation_logging_configuration`やアカウント全体の請求アラーム等は、ユースケース単位ではなくAWSアカウント×リージョン単位で1つしか存在できない。モジュール内とユースケースのREADMEの両方に明記し、2つ目以降のユースケースのTerraformが最初の設定を無自覚に上書きしないようにする。
