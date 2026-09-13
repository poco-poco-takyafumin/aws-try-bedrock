terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.48"
    }
  }

  # PoC段階ではローカルstateを使用。運用が安定したらS3+DynamoDBのリモートbackendへ移行を検討する。
  # backend "s3" { ... }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# AWS/Billing の EstimatedCharges メトリクスは us-east-1 にのみ存在するため、
# アカウント全体の請求アラーム（billing_alarm.tf）はこのエイリアスを使う。
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
