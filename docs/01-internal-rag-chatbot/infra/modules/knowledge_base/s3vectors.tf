# Knowledge Baseのベクトルストア（S3 Vectors）。
# 以前は土台リポジトリ（aws-samples/sample-bedrock-knowledge-base-terraform）に倣って
# OpenSearch Serverlessを使っていたが、最低OCU分が常時課金されPoC規模に対して
# コストが過大だったため、ストレージ量・クエリ量に応じた従量課金のS3 Vectorsに置き換えた（Issue #10）。
# 暗号化は以前のOpenSearch Serverless（AWS所有キー）と同等の既定SSE-S3とする。

resource "aws_s3vectors_vector_bucket" "resource_kb" {
  vector_bucket_name = var.kb_vector_bucket_name
  # ベクトルはデータソースS3バケットから再取り込みで復元できる派生データのため、
  # 中身が残っていてもdestroyできるようにする。
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3vectors_index" "resource_kb" {
  index_name         = "bedrock-knowledge-base-default-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.resource_kb.vector_bucket_name
  data_type          = "float32"
  dimension          = var.vector_dimension
  distance_metric    = "cosine"

  # Bedrock KBはチャンク本文とメタデータをベクトルのメタデータとして書き込む。
  # フィルタ可能メタデータには1ベクトルあたりのサイズ上限があるため、
  # フィルタに使わないこの2キーは非フィルタ対象として宣言する（AWSドキュメントの推奨設定）。
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }

  tags = var.tags
}
