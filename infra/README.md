# アカウント共通Terraform

`docs/0X-xxx/infra` のどのユースケースにも属さない、AWSアカウント×リージョン単位の
シングルトンリソースをここで一元管理する（`docs/00-architecture-overview.md` 0章参照）。
各ユースケースのTerraformより**先に**applyすること。

## 対象リソース

| リソース | ファイル | 理由 |
|---|---|---|
| CloudWatch Billing Alarm + SNS通知 | `billing_alarm.tf` | アカウント全体の請求額に対するアラームで、ユースケース単位ではない |
| `aws_ce_cost_allocation_tag`（CostCenterタグ） | `cost_allocation_tag.tf` | タグキー単位でアカウントに1つしか存在できない |

Admin/Developer/Auditor IAMロールはここには**含まれていない**（[#2](https://github.com/poco-poco-takyafumin/aws-try-bedrock/issues/2)で別途設計中。当面は各ユースケースのTerraformにユースケース名を含めた個別ロールとして残置）。

## ★人間レビュー必須（CLAUDE.mdより）

`terraform apply` 前に必ず `terraform plan` の差分を人間がレビューすること:

| ファイル | 該当理由 |
|---|---|
| `billing_alarm.tf` | コスト管理設定（アカウント全体のCloudWatch請求アラーム） |
| `cost_allocation_tag.tf` | コスト管理設定（Cost allocation tagの有効化） |

## デプロイ手順

```bash
cd infra

# AWS Billingコンソールで「請求アラートを受け取る」を事前に有効化しておく
# （Terraformでは自動化できない一回限りの手動設定）

terraform init
terraform fmt -recursive
terraform validate

# 変数を設定（terraform.tfvars等）
#   budget_alert_email = "you@example.com"

terraform plan -out=tfplan
# ↑ この差分を必ず人間がレビューする

terraform apply tfplan
```

各ユースケースのTerraformは、ここで作成したリソースには依存していない
（billing alarm・cost allocation tagはどのユースケース側からも参照されない自己完結型リソースのため）。
