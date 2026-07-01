# Flink CDC Jobs

`k8s/apps/data/flink-orders-cdc` contains the Kubernetes deployment unit for the
first CDC-to-Iceberg job. The custom runtime image is built from
`flink/runtime` and injected into the rendered manifests by
`scripts/render-k8s-config.sh`.

Required runtime image contents:

- Apache Flink 2.1 runtime
- Flink Kafka connector
- Apache Iceberg Flink runtime bundle
- Iceberg AWS bundle
- A small SQL runner jar at `/opt/flink/usrlib/sql-runner.jar`
- SQL runner reads `/opt/flink/sql/cdc_to_iceberg.sql` from the mounted
  ConfigMap

The base manifest keeps a placeholder image value; rendered manifests replace
it with the ECR image built for this lab.
