terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# plan だけを作るので、AWS には接続しない
provider "aws" {
  region                      = "ap-northeast-1"
  access_key                  = "dummy"
  secret_key                  = "dummy"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

locals {
  account = "123456789012"
  arn     = "arn:aws:iam::${local.account}:role"
}

# 開発者が普段使うロール
resource "aws_iam_role" "developer" {
  name = "developer"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = "arn:aws:iam::${local.account}:root" } }]
  })
}

resource "aws_iam_role_policy" "developer" {
  name = "assume-deploy-and-readonly"
  role = aws_iam_role.developer.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = ["${local.arn}/deploy", "${local.arn}/readonly"] }]
  })
}

resource "aws_iam_role" "readonly" {
  name = "readonly"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = "${local.arn}/developer" } }]
  })
}

# CI とデプロイ用のロール。引き受けられるのは、環境ごとのロール (app-*) だけ
resource "aws_iam_role" "deploy" {
  name = "deploy"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = "${local.arn}/developer" } }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "assume-env-roles"
  role = aws_iam_role.deploy.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = "${local.arn}/app-*" }]
  })
}

# 管理者ロール。障害対応の自動化のために、deploy からの引き受けを許している
resource "aws_iam_role" "admin" {
  name = "admin"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = "${local.arn}/deploy" } }]
  })
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
