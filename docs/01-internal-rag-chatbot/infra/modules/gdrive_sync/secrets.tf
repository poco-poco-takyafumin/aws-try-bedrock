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
