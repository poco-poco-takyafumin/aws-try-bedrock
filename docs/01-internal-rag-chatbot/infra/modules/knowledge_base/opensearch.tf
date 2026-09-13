# 土台: aws-samples/sample-bedrock-knowledge-base-terraform の modules/opensearch.tf を移植。
# network policyの AllowFromPublic = true は上流のデフォルトを踏襲（VPC化はしていない）。
# アクセス制御はdata policyでprincipal（KB実行ロール＋管理者）を限定することで担保している。
# この点は requirements.md / 実装計画の「構成リスク」として明記済み。人間レビュー時に許容可否を判断すること。

resource "aws_opensearchserverless_access_policy" "resource_kb" {
  name = var.kb_oss_collection_name
  type = "data"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${var.kb_oss_collection_name}/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:UpdateIndex",
            "aoss:WriteDocument"
          ]
        },
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.kb_oss_collection_name}"]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DescribeCollectionItems",
            "aoss:UpdateCollectionItems"
          ]
        }
      ],
      Principal = [
        aws_iam_role.kb_execution.arn,
        var.admin_principal_arn
      ]
    }
  ])
}

resource "aws_opensearchserverless_security_policy" "resource_kb_encryption" {
  name = var.kb_oss_collection_name
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${var.kb_oss_collection_name}"]
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "resource_kb_network" {
  name = var.kb_oss_collection_name
  type = "network"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.kb_oss_collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${var.kb_oss_collection_name}"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "resource_kb" {
  name = var.kb_oss_collection_name
  type = "VECTORSEARCH"
  tags = var.tags
  depends_on = [
    aws_opensearchserverless_access_policy.resource_kb,
    aws_opensearchserverless_security_policy.resource_kb_encryption,
    aws_opensearchserverless_security_policy.resource_kb_network
  ]
}

# ============================================================================
# ★既知の制約（コードレビューで指摘）★
# このprovider "opensearch"ブロックは非ルートモジュール内に置かれており、かつ
# urlが同じapply内で作成されるコレクションのcollection_endpoint（apply後にしか
# 確定しない値）に依存している。これはTerraformの推奨パターンではなく、
# 初回applyでは「provider configuration value depends on resource attributes
# that cannot be determined until apply」相当のエラーになる場合がある。
# その場合は以下のように2段階でapplyすること（土台リポジトリ由来の既知の制約で、
# 今回のフェーズでは構造自体は変更せず運用手順で回避する）:
#   terraform apply -target=module.knowledge_base.aws_opensearchserverless_collection.resource_kb
#   terraform apply
# 2回目以降のapply（コレクションが既にstateに存在する状態）ではこの問題は発生しない。
# ============================================================================
provider "opensearch" {
  url         = aws_opensearchserverless_collection.resource_kb.collection_endpoint
  healthcheck = false
}

resource "opensearch_index" "resource_kb" {
  name                           = "bedrock-knowledge-base-default-index"
  number_of_shards               = "2"
  number_of_replicas             = "0"
  index_knn                      = true
  index_knn_algo_param_ef_search = "512"
  mappings                       = <<-EOF
    {
      "properties": {
        "bedrock-knowledge-base-default-vector": {
          "type": "knn_vector",
          "dimension": ${var.vector_dimension},
          "method": {
            "name": "hnsw",
            "engine": "faiss",
            "parameters": {
              "m": 16,
              "ef_construction": 512
            },
            "space_type": "l2"
          }
        },
        "AMAZON_BEDROCK_METADATA": {
          "type": "text",
          "index": "false"
        },
        "AMAZON_BEDROCK_TEXT_CHUNK": {
          "type": "text",
          "index": "true"
        }
      }
    }
  EOF
  force_destroy                  = true
  depends_on                     = [aws_opensearchserverless_collection.resource_kb]
}

resource "time_sleep" "kb_execution_oss" {
  create_duration = "20s"
  depends_on      = [aws_iam_role_policy.kb_execution_oss]
}
