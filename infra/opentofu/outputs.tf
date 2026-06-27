output "aws_region" {
  value = var.aws_region
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "lakehouse_bucket" {
  value = aws_s3_bucket.lakehouse.bucket
}

output "glue_databases" {
  value = [for db in aws_glue_catalog_database.lakehouse : db.name]
}

output "rds_endpoint" {
  value = aws_db_instance.source_mysql.address
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds_source.arn
}

output "rds_secret_name" {
  value = aws_secretsmanager_secret.rds_source.name
}

output "msk_mode" {
  value = var.msk_mode
}

output "msk_bootstrap_brokers" {
  value = var.msk_mode == "provisioned" ? aws_msk_cluster.cdc[0].bootstrap_brokers : data.aws_msk_bootstrap_brokers.serverless[0].bootstrap_brokers_sasl_iam
}

output "msk_bootstrap_brokers_tls" {
  value = var.msk_mode == "provisioned" ? aws_msk_cluster.cdc[0].bootstrap_brokers_tls : data.aws_msk_bootstrap_brokers.serverless[0].bootstrap_brokers_sasl_iam
}

output "msk_bootstrap_brokers_sasl_iam" {
  value = var.msk_mode == "provisioned" ? null : data.aws_msk_bootstrap_brokers.serverless[0].bootstrap_brokers_sasl_iam
}

output "data_workloads_role_arn" {
  value = aws_iam_role.data_workloads.arn
}

output "platform_workloads_role_arn" {
  value = aws_iam_role.platform_workloads.arn
}

output "ml_workloads_role_arn" {
  value = aws_iam_role.ml_workloads.arn
}

output "lakehouse_workloads_role_arn" {
  description = "Deprecated compatibility output retained during IRSA role migration. Use data_workloads_role_arn, platform_workloads_role_arn, or ml_workloads_role_arn for new manifests."
  value       = aws_iam_role.lakehouse_workloads.arn
}

output "source_generator_repository_url" {
  value = aws_ecr_repository.source_generator.repository_url
}

output "flink_runtime_repository_url" {
  value = aws_ecr_repository.flink_runtime.repository_url
}

output "argocd_repository_url" {
  value = var.repository_url
}
