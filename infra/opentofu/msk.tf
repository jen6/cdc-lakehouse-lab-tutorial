resource "aws_security_group" "msk" {
  name        = "${local.name}-msk"
  description = "MSK access from EKS workloads"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "msk_from_eks_plaintext" {
  type                     = "ingress"
  security_group_id        = aws_security_group.msk.id
  source_security_group_id = module.eks.node_security_group_id
  from_port                = 9092
  to_port                  = 9092
  protocol                 = "tcp"
  description              = "Kafka plaintext from EKS node workloads"
}

resource "aws_security_group_rule" "msk_from_eks_tls" {
  type                     = "ingress"
  security_group_id        = aws_security_group.msk.id
  source_security_group_id = module.eks.node_security_group_id
  from_port                = 9094
  to_port                  = 9094
  protocol                 = "tcp"
  description              = "Kafka TLS from EKS node workloads"
}

resource "aws_security_group_rule" "msk_from_eks_iam" {
  type                     = "ingress"
  security_group_id        = aws_security_group.msk.id
  source_security_group_id = module.eks.node_security_group_id
  from_port                = 9098
  to_port                  = 9098
  protocol                 = "tcp"
  description              = "Kafka IAM from EKS node workloads"
}

resource "aws_security_group_rule" "msk_egress" {
  type              = "egress"
  security_group_id = aws_security_group.msk.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_msk_configuration" "cdc" {
  count = var.msk_mode == "provisioned" ? 1 : 0

  name           = "${local.name}-cdc"
  kafka_versions = ["3.9.x"]

  server_properties = <<-PROPERTIES
auto.create.topics.enable=true
default.replication.factor=2
min.insync.replicas=1
num.partitions=6
offsets.topic.replication.factor=2
transaction.state.log.replication.factor=2
transaction.state.log.min.isr=1
  PROPERTIES
}

resource "aws_msk_cluster" "cdc" {
  count = var.msk_mode == "provisioned" ? 1 : 0

  cluster_name           = local.name
  kafka_version          = "3.9.x"
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.cdc[0].arn
    revision = aws_msk_configuration.cdc[0].latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }
}

resource "aws_msk_serverless_cluster" "cdc" {
  count = var.msk_mode == "serverless" ? 1 : 0

  cluster_name = local.name

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.msk.id]
  }
}

data "aws_msk_bootstrap_brokers" "serverless" {
  count       = var.msk_mode == "serverless" ? 1 : 0
  cluster_arn = aws_msk_serverless_cluster.cdc[0].arn
}
