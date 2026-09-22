# サービスアカウントの秘密鍵（JSONキー）はSecrets Managerで保管する（requirements.md確定）。
# 値自体はTerraformでは注入しない（機密情報をコード/stateに残さないため）。
# google-setup.md の手順に従い、apply後に運用者が `aws secretsmanager put-secret-value` 等で登録する。
resource "aws_secretsmanager_secret" "gdrive_service_account" {
  name        = "${var.name_prefix}-gdrive-service-account-key"
  description = "Google Drive同期用サービスアカウントのJSONキー（apply後に手動登録）"
  tags        = var.tags
}

# 同期対象フォルダIDは非機密のためSSM Parameter Store（String）で管理する（requirements.md確定）。
# コード変更・再デプロイなしにフォルダを変更できるよう、値はTerraform変数の初期値のみ設定し、
# 運用中の変更は `aws ssm put-parameter` で行う想定。
resource "aws_ssm_parameter" "gdrive_folder_id" {
  name        = "/${var.name_prefix}/gdrive-sync/folder-id"
  description = "同期対象Google DriveフォルダID"
  type        = "String"
  value       = var.gdrive_folder_id_default
  tags        = var.tags

  lifecycle {
    ignore_changes = [value] # 運用中の変更をterraform applyで巻き戻さない
  }
}

# ドメイン全体委譲でなりすます対象ユーザー（Google Workspaceのメールアドレス。通常は
# 同期対象フォルダの所有者）。フォルダIDと同様に非機密だが運用中に変更されうるため、
# SSM Parameter Store（String）で管理する（google-setup.md 手順6と同様の運用）。
resource "aws_ssm_parameter" "gdrive_impersonate_user" {
  name        = "/${var.name_prefix}/gdrive-sync/impersonate-user"
  description = "ドメイン全体委譲でなりすます対象ユーザーのメールアドレス"
  type        = "String"
  value       = var.gdrive_impersonate_user_default
  tags        = var.tags

  lifecycle {
    ignore_changes = [value]
  }
}
