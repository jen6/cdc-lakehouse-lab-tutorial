-- Template for the first Flink SQL implementation.
-- Replace bucket, region, and Kafka bootstrap values with OpenTofu outputs.

CREATE CATALOG glue_catalog WITH (
  'type' = 'iceberg',
  'catalog-impl' = 'org.apache.iceberg.aws.glue.GlueCatalog',
  'warehouse' = 's3://REPLACE_WITH_LAKEHOUSE_BUCKET/warehouse',
  'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO'
);

CREATE TABLE orders_cdc_kafka (
  `before` STRING,
  `after` STRING,
  `op` STRING,
  `ts_ms` BIGINT
) WITH (
  'connector' = 'kafka',
  'topic' = 'rds.commerce.orders',
  'properties.bootstrap.servers' = 'REPLACE_WITH_MSK_BOOTSTRAP_BROKERS',
  'properties.group.id' = 'flink-orders-cdc',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'json'
);

CREATE DATABASE IF NOT EXISTS glue_catalog.lab_bronze;

CREATE TABLE IF NOT EXISTS glue_catalog.lab_bronze.orders_cdc (
  before_json STRING,
  after_json STRING,
  op STRING,
  event_ts TIMESTAMP_LTZ(3)
) PARTITIONED BY (days(event_ts));

INSERT INTO glue_catalog.lab_bronze.orders_cdc
SELECT
  `before`,
  `after`,
  op,
  TO_TIMESTAMP_LTZ(ts_ms, 3)
FROM orders_cdc_kafka;
