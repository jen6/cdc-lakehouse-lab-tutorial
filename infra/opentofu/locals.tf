data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "opentofu"
  }

  commerce_schemas = ["commerce", "payment", "logistics"]
}
