# OpenTofu Infrastructure

This stack provisions the AWS stateful and platform foundation for the CDC
lakehouse lab:

- VPC across two AZs by default
- EKS managed cluster and node group
- RDS MySQL configured for Debezium CDC
- MSK provisioned Kafka
- S3 Iceberg warehouse bucket
- Glue databases for `bronze`, `silver`, and `gold`
- Secrets Manager source DB secret
- IRSA role for EKS data workloads

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

Update kubeconfig:

```bash
aws eks update-kubeconfig \
  --region "$(tofu output -raw aws_region 2>/dev/null || echo ap-northeast-2)" \
  --name "$(tofu output -raw eks_cluster_name)"
```

If the region command above is awkward in your shell, use the region from
`terraform.tfvars`.

## Cost Controls

- Keep `msk_broker_count = 2` and `msk_instance_type = "kafka.t3.small"` for the
  first MVP.
- Delete NAT Gateway and EKS/MSK when not testing.
- Keep durable data in S3 and RDS snapshots rather than in pods.

## Notes

RDS automated backups are enabled because MySQL binary logging requires backup
retention greater than zero. The DB parameter group sets row-based binlogs for
Debezium.
