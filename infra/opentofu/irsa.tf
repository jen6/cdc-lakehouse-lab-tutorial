data "aws_iam_policy_document" "data_workloads_access" {
  statement {
    sid = "S3LakehouseAccess"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.lakehouse.arn,
      "${aws_s3_bucket.lakehouse.arn}/*"
    ]
  }

  statement {
    sid = "GlueIcebergCatalogAccess"
    actions = [
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:CreateDatabase",
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:DeletePartition",
      "glue:DeleteTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdateDatabase",
      "glue:UpdatePartition",
      "glue:UpdateTable"
    ]
    resources = ["*"]
  }

  statement {
    sid = "KafkaIamClientAccess"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:AlterTopic",
      "kafka-cluster:Connect",
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:DescribeGroup",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:ReadData",
      "kafka-cluster:WriteData"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadRdsSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.rds_source.arn]
  }
}

data "aws_iam_policy_document" "platform_workloads_access" {
  statement {
    sid = "CloudWatchMetricsReadAccess"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetInsightRuleReport",
      "cloudwatch:ListMetrics",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeTags",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:GetLogRecord",
      "logs:GetQueryResults",
      "logs:StartQuery",
      "logs:StopQuery",
      "tag:GetResources",
      "sts:GetCallerIdentity"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ml_workloads_access" {
  statement {
    sid = "S3LakehouseAccess"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = [
      aws_s3_bucket.lakehouse.arn,
      "${aws_s3_bucket.lakehouse.arn}/*"
    ]
  }

  statement {
    sid = "GlueIcebergCatalogReadWrite"
    actions = [
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:CreateDatabase",
      "glue:CreatePartition",
      "glue:CreateTable",
      "glue:DeletePartition",
      "glue:DeleteTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:GetTable",
      "glue:GetTables",
      "glue:UpdateDatabase",
      "glue:UpdatePartition",
      "glue:UpdateTable"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lakehouse_access" {
  source_policy_documents = [
    data.aws_iam_policy_document.data_workloads_access.json,
    data.aws_iam_policy_document.platform_workloads_access.json
  ]
}

resource "aws_iam_policy" "data_workloads_access" {
  name        = "${local.name}-data-workloads-access"
  description = "S3, Glue, Kafka, and source secret access for EKS data workloads"
  policy      = data.aws_iam_policy_document.data_workloads_access.json
}

resource "aws_iam_policy" "platform_workloads_access" {
  name        = "${local.name}-platform-workloads-access"
  description = "CloudWatch metrics read access for EKS platform workloads"
  policy      = data.aws_iam_policy_document.platform_workloads_access.json
}

resource "aws_iam_policy" "ml_workloads_access" {
  name        = "${local.name}-ml-workloads-access"
  description = "S3 and Glue access for EKS ML workloads"
  policy      = data.aws_iam_policy_document.ml_workloads_access.json
}

resource "aws_iam_policy" "lakehouse_access" {
  name        = "${local.name}-lakehouse-access"
  description = "S3, Glue, and source secret access for EKS data workloads"
  policy      = data.aws_iam_policy_document.lakehouse_access.json

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "data_workloads_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:data:kafka-connect",
        "system:serviceaccount:data:source-generator",
        "system:serviceaccount:data:flink",
        "system:serviceaccount:data:flink-orders-cdc",
        "system:serviceaccount:data:trino"
      ]
    }
  }
}

data "aws_iam_policy_document" "platform_workloads_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:platform:cloudwatch-exporter",
        "system:serviceaccount:platform:kube-prometheus-stack-grafana"
      ]
    }
  }
}

data "aws_iam_policy_document" "ml_workloads_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:ml:kubeflow-pipelines",
        "system:serviceaccount:kubeflow:argo",
        "system:serviceaccount:kubeflow:ml-pipeline",
        "system:serviceaccount:kubeflow:pipeline-runner"
      ]
    }
  }
}

data "aws_iam_policy_document" "lakehouse_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values = [
        "system:serviceaccount:data:kafka-connect",
        "system:serviceaccount:data:source-generator",
        "system:serviceaccount:data:flink",
        "system:serviceaccount:data:flink-orders-cdc",
        "system:serviceaccount:data:trino",
        "system:serviceaccount:platform:cloudwatch-exporter",
        "system:serviceaccount:platform:kube-prometheus-stack-grafana",
        "system:serviceaccount:ml:kubeflow-pipelines",
        "system:serviceaccount:kubeflow:argo",
        "system:serviceaccount:kubeflow:ml-pipeline",
        "system:serviceaccount:kubeflow:pipeline-runner"
      ]
    }
  }
}

resource "aws_iam_role" "data_workloads" {
  name               = "${local.name}-data-workloads"
  assume_role_policy = data.aws_iam_policy_document.data_workloads_irsa_assume_role.json
}

resource "aws_iam_role" "platform_workloads" {
  name               = "${local.name}-platform-workloads"
  assume_role_policy = data.aws_iam_policy_document.platform_workloads_irsa_assume_role.json
}

resource "aws_iam_role" "ml_workloads" {
  name               = "${local.name}-ml-workloads"
  assume_role_policy = data.aws_iam_policy_document.ml_workloads_irsa_assume_role.json
}

resource "aws_iam_role" "lakehouse_workloads" {
  name               = "${local.name}-lakehouse-workloads"
  assume_role_policy = data.aws_iam_policy_document.lakehouse_irsa_assume_role.json

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "data_workloads" {
  role       = aws_iam_role.data_workloads.name
  policy_arn = aws_iam_policy.data_workloads_access.arn
}

resource "aws_iam_role_policy_attachment" "platform_workloads" {
  role       = aws_iam_role.platform_workloads.name
  policy_arn = aws_iam_policy.platform_workloads_access.arn
}

resource "aws_iam_role_policy_attachment" "ml_workloads" {
  role       = aws_iam_role.ml_workloads.name
  policy_arn = aws_iam_policy.ml_workloads_access.arn
}

resource "aws_iam_role_policy_attachment" "lakehouse_workloads" {
  role       = aws_iam_role.lakehouse_workloads.name
  policy_arn = aws_iam_policy.lakehouse_access.arn
}
