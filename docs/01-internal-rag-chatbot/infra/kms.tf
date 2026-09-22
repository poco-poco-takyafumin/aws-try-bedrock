# KBデータ用バケットの暗号化キー。
# ログ用バケットのKMSキー（modules/logging）とは分離し、鍵レベルでもデータ系とログ系の権限を分ける。
resource "aws_kms_key" "kb_data" {
  description             = "${local.name_prefix} Knowledge BaseデータソースS3バケット用KMSキー"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "kb_data" {
  name          = "alias/${local.name_prefix}-kb-data"
  target_key_id = aws_kms_key.kb_data.key_id
}
