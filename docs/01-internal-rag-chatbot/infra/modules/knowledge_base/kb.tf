terraform {
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "= 2.2.0"
    }
  }
}

# 土台: aws-samples/sample-bedrock-knowledge-base-terraform の modules/kb.tf を移植・改修。
# 変更点:
#  - S3バケットはルートモジュール(s3.tf)で作成したバケットを var.kb_s3_bucket_name で参照する
#  - kb_name / kb_oss_collection_name は必須変数化（coalesceによる既定名を廃止し、命名を呼び出し側で一元管理）
#  - kb_role_arn をoutputに追加（S3バケットポリシーで参照するため）

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

locals {
  account_id        = data.aws_caller_identity.this.account_id
  partition         = data.aws_partition.this.partition
  region            = data.aws_region.this.name
  bedrock_model_arn = "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.kb_model_id}"
}

data "aws_bedrock_foundation_model" "kb" {
  model_id = local.bedrock_model_arn
}

# Knowledge Base実行ロール（Bedrockサービスが引き受ける）
resource "aws_iam_role" "kb_execution" {
  name = "AmazonBedrockExecutionRoleForKnowledgeBase_${var.kb_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "kb_execution_model" {
  name = "AmazonBedrockFoundationModelPolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.kb_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = local.bedrock_model_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "kb_execution_s3" {
  name = "AmazonBedrockS3PolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.kb_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ListBucketStatement"
        Action   = "s3:ListBucket"
        Effect   = "Allow"
        Resource = data.aws_s3_bucket.resource_kb.arn
        Condition = {
          StringEquals = { "aws:ResourceAccount" = local.account_id }
        }
      },
      {
        Sid      = "S3GetObjectStatement"
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${data.aws_s3_bucket.resource_kb.arn}/*"
        Condition = {
          StringEquals = { "aws:ResourceAccount" = local.account_id }
        }
      },
      {
        # レビュー指摘対応: データソースバケットはSSE-KMSで暗号化されているため、
        # s3:GetObjectだけでなくKMS復号権限も必要。
        Sid      = "KmsDecryptStatement"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Effect   = "Allow"
        Resource = var.kb_kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "kb_execution_oss" {
  name = "AmazonBedrockOSSPolicyForKnowledgeBase_${var.kb_name}"
  role = aws_iam_role.kb_execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "aoss:APIAccessAll"
        Effect   = "Allow"
        Resource = aws_opensearchserverless_collection.resource_kb.arn
      }
    ]
  })
}

data "aws_s3_bucket" "resource_kb" {
  bucket = var.kb_s3_bucket_name
}

resource "aws_bedrockagent_knowledge_base" "resource_kb" {
  name     = var.kb_name
  role_arn = aws_iam_role.kb_execution.arn
  knowledge_base_configuration {
    vector_knowledge_base_configuration {
      embedding_model_arn = local.bedrock_model_arn
    }
    type = "VECTOR"
  }
  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.resource_kb.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
  tags = var.tags
  depends_on = [
    aws_iam_role_policy.kb_execution_model,
    aws_iam_role_policy.kb_execution_s3,
    opensearch_index.resource_kb,
    time_sleep.kb_execution_oss
  ]
}

resource "aws_bedrockagent_data_source" "resource_kb" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.resource_kb.id
  name              = "${var.kb_name}DataSource"
  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = data.aws_s3_bucket.resource_kb.arn
    }
  }

  dynamic "vector_ingestion_configuration" {
    for_each = var.chunking_strategy != "DEFAULT" ? [1] : []
    content {
      chunking_configuration {
        chunking_strategy = var.chunking_strategy

        dynamic "fixed_size_chunking_configuration" {
          for_each = var.chunking_strategy == "FIXED_SIZE" ? [1] : []
          content {
            max_tokens         = var.fixed_size_max_tokens
            overlap_percentage = var.fixed_size_overlap_percentage
          }
        }

        dynamic "hierarchical_chunking_configuration" {
          for_each = var.chunking_strategy == "HIERARCHICAL" ? [1] : []
          content {
            overlap_tokens = var.hierarchical_overlap_tokens
            level_configuration {
              max_tokens = var.hierarchical_parent_max_tokens
            }
            level_configuration {
              max_tokens = var.hierarchical_child_max_tokens
            }
          }
        }

        dynamic "semantic_chunking_configuration" {
          for_each = var.chunking_strategy == "SEMANTIC" ? [1] : []
          content {
            max_token                       = var.semantic_max_tokens
            buffer_size                     = var.semantic_buffer_size
            breakpoint_percentile_threshold = var.semantic_breakpoint_percentile_threshold
          }
        }
      }
    }
  }
}
