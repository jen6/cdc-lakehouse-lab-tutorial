resource "random_password" "rds_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "RDS MySQL access from EKS workloads"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "rds_from_eks_nodes" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  description              = "MySQL from EKS node workloads"
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  security_group_id = aws_security_group.rds.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_db_subnet_group" "source" {
  name       = "${local.name}-source"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_parameter_group" "mysql_cdc" {
  name        = "${local.name}-mysql-cdc"
  family      = "mysql8.4"
  description = "MySQL parameters required for Debezium CDC"

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  parameter {
    name  = "binlog_row_image"
    value = "FULL"
  }

  parameter {
    name  = "binlog_checksum"
    value = "NONE"
  }
}

resource "aws_db_instance" "source_mysql" {
  identifier = "${local.name}-source"

  engine         = "mysql"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  username = var.rds_master_username
  password = random_password.rds_master.result

  db_subnet_group_name   = aws_db_subnet_group.source.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql_cdc.name

  backup_retention_period = 3
  backup_window           = "17:00-18:00"
  maintenance_window      = "sun:18:00-sun:19:00"

  deletion_protection = false
  skip_final_snapshot = var.rds_skip_final_snapshot

  apply_immediately = true
}

resource "aws_secretsmanager_secret" "rds_source" {
  name        = "${local.name}/rds/source"
  description = "RDS source MySQL credentials for CDC lab workloads"
}

resource "aws_secretsmanager_secret_version" "rds_source" {
  secret_id = aws_secretsmanager_secret.rds_source.id
  secret_string = jsonencode({
    host     = aws_db_instance.source_mysql.address
    port     = aws_db_instance.source_mysql.port
    username = var.rds_master_username
    password = random_password.rds_master.result
    schemas  = local.commerce_schemas
  })
}
