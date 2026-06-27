variable "aws_region" {
  description = "AWS region for the lab."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Short project name used for resource names."
  type        = string
  default     = "cdc-lakehouse-tutorial"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "sandbox"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to use. The lab uses at least 2 AZs for EKS, RDS subnet groups, and Kafka."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2."
  }
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_types" {
  description = "Instance types for the default EKS managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "eks_node_min_size" {
  type    = number
  default = 3
}

variable "eks_node_desired_size" {
  type    = number
  default = 3
}

variable "eks_node_max_size" {
  type    = number
  default = 4
}

variable "msk_mode" {
  description = "Kafka deployment mode. Use provisioned for broker-level practice or serverless for lower operational burden."
  type        = string
  default     = "provisioned"

  validation {
    condition     = contains(["provisioned", "serverless"], var.msk_mode)
    error_message = "msk_mode must be either provisioned or serverless."
  }
}

variable "msk_broker_count" {
  description = "Total broker count. Use 2 for cheapest MSK MVP, 3+ for production-like RF=3 tests."
  type        = number
  default     = 2

  validation {
    condition     = var.msk_mode != "provisioned" || var.msk_broker_count >= 2
    error_message = "MSK provisioned clusters should use at least 2 brokers in this lab."
  }
}

variable "msk_instance_type" {
  description = "MSK broker instance type."
  type        = string
  default     = "kafka.t3.small"
}

variable "msk_ebs_volume_size" {
  description = "EBS volume size per MSK broker in GiB."
  type        = number
  default     = 100
}

variable "rds_instance_class" {
  description = "RDS MySQL instance class."
  type        = string
  default     = "db.t4g.medium"
}

variable "rds_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
  default     = 100
}

variable "rds_engine_version" {
  description = "RDS MySQL engine version family."
  type        = string
  default     = "8.0"
}

variable "rds_master_username" {
  description = "RDS master username."
  type        = string
  default     = "admin"
}

variable "rds_skip_final_snapshot" {
  description = "Set false when you want Terraform destroy to retain a final snapshot."
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet egress. Disable for lower cost if you provide VPC endpoints/egress another way."
  type        = bool
  default     = true
}

variable "repository_url" {
  description = "Git repository URL used by Argo CD root app. Replace after pushing this repo."
  type        = string
  default     = "git@github.com:YOUR_GITHUB_OWNER/YOUR_REPO.git"
}
