#!/usr/bin/env python3
"""Compile and submit a Kubeflow Pipeline smoke test for the lakehouse.

The pipeline runs inside EKS, queries Iceberg tables through Trino, and writes a
small JSON artifact to the lakehouse S3 bucket using the pipeline-runner IRSA.
"""

import argparse
import json
import os
from pathlib import Path
from time import time

import kfp
from kfp import compiler, dsl


DEFAULT_HOST = "http://127.0.0.1:8888"
DEFAULT_BUCKET = os.environ.get("LAKEHOUSE_BUCKET", "REPLACE_WITH_LAKEHOUSE_BUCKET")
DEFAULT_REGION = "ap-northeast-2"
DEFAULT_TRINO_HOST = "trino.data.svc.cluster.local"
DEFAULT_TRINO_PORT = 8080
DEFAULT_EXPERIMENT = "lakehouse-smoke"


@dsl.container_component
def query_lakehouse_and_write_s3(
    bucket: str,
    region: str,
    trino_host: str,
    trino_port: int,
    artifact_prefix: str,
) -> dsl.ContainerSpec:
    script = r'''
set -euo pipefail
export LAKEHOUSE_BUCKET="$0"
export AWS_REGION="$1"
export TRINO_HOST="$2"
export TRINO_PORT="$3"
export ARTIFACT_PREFIX="$4"
export PYTHONPATH=/tmp/pydeps
python -m pip install --no-cache-dir --target /tmp/pydeps trino==0.338.0 boto3==1.43.37 >/tmp/pip-install.log
python - <<'PY'
import datetime as dt
import json
import os
import socket

import boto3
import trino

bucket = os.environ["LAKEHOUSE_BUCKET"]
region = os.environ["AWS_REGION"]
trino_host = os.environ["TRINO_HOST"]
trino_port = int(float(os.environ["TRINO_PORT"]))
artifact_prefix = os.environ["ARTIFACT_PREFIX"].strip("/")

conn = trino.dbapi.connect(
    host=trino_host,
    port=trino_port,
    user="kubeflow",
    catalog="iceberg",
    schema="lab_gold",
    http_scheme="http",
)
cur = conn.cursor()

queries = {
    "layer_counts": """
        SELECT 'bronze' AS layer, count(*) AS rows FROM iceberg.lab_bronze.orders_cdc_events
        UNION ALL
        SELECT 'silver' AS layer, count(*) AS rows FROM iceberg.lab_silver.orders_current
        UNION ALL
        SELECT 'gold' AS layer, count(*) AS rows FROM iceberg.lab_gold.order_revenue_by_status
    """,
    "revenue_by_status": """
        SELECT status, order_count, CAST(gross_amount AS VARCHAR) AS gross_amount
        FROM iceberg.lab_gold.order_revenue_by_status
        ORDER BY gross_amount DESC
    """,
    "recent_order_revenue": """
        SELECT
          count(*) AS order_rows,
          CAST(sum(total_amount) AS VARCHAR) AS gross_amount
        FROM iceberg.lab_silver.orders_current
          WHERE try(from_iso8601_timestamp(replace(updated_at, ' ', 'T'))) >= current_timestamp - INTERVAL '10' MINUTE
    """,
}

results = {}
for name, sql in queries.items():
    cur.execute(sql)
    columns = [desc[0] for desc in cur.description]
    rows = [dict(zip(columns, row)) for row in cur.fetchall()]
    results[name] = rows

payload = {
    "generated_at": dt.datetime.now(dt.UTC).isoformat(),
    "pod_hostname": socket.gethostname(),
    "trino": {"host": trino_host, "port": trino_port},
    "results": results,
}

key = f"{artifact_prefix}/lakehouse-smoke-{dt.datetime.now(dt.UTC).strftime('%Y%m%dT%H%M%SZ')}.json"
s3 = boto3.client("s3", region_name=region)
s3.put_object(
    Bucket=bucket,
    Key=key,
    Body=json.dumps(payload, indent=2, sort_keys=True).encode("utf-8"),
    ContentType="application/json",
)
print(json.dumps({"s3_uri": f"s3://{bucket}/{key}", "results": results}, sort_keys=True))
PY
'''
    return dsl.ContainerSpec(
        image="python:3.12-slim",
        command=["/bin/sh", "-c"],
        args=[
            script,
            bucket,
            region,
            trino_host,
            trino_port,
            artifact_prefix,
        ],
    )


@dsl.pipeline(name="lakehouse-smoke", description="Query Iceberg through Trino and write a smoke artifact to S3.")
def lakehouse_smoke_pipeline(
    bucket: str = DEFAULT_BUCKET,
    region: str = DEFAULT_REGION,
    trino_host: str = DEFAULT_TRINO_HOST,
    trino_port: int = DEFAULT_TRINO_PORT,
    artifact_prefix: str = "kubeflow/artifacts/lakehouse-smoke",
) -> None:
    task = query_lakehouse_and_write_s3(
        bucket=bucket,
        region=region,
        trino_host=trino_host,
        trino_port=trino_port,
        artifact_prefix=artifact_prefix,
    )
    task.set_caching_options(False)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST, help="Kubeflow Pipelines API host.")
    parser.add_argument("--experiment", default=DEFAULT_EXPERIMENT)
    parser.add_argument("--run-name", default=f"lakehouse-smoke-{int(time())}")
    parser.add_argument("--package", default="/tmp/lakehouse-smoke-pipeline.yaml")
    parser.add_argument("--bucket", default=DEFAULT_BUCKET)
    parser.add_argument("--region", default=DEFAULT_REGION)
    parser.add_argument("--trino-host", default=DEFAULT_TRINO_HOST)
    parser.add_argument("--trino-port", type=int, default=DEFAULT_TRINO_PORT)
    parser.add_argument("--artifact-prefix", default="kubeflow/artifacts/lakehouse-smoke")
    parser.add_argument("--service-account", default="pipeline-runner")
    parser.add_argument("--submit", action="store_true", help="Submit the compiled package to KFP.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    package_path = Path(args.package)
    compiler.Compiler().compile(lakehouse_smoke_pipeline, str(package_path))

    print(json.dumps({"compiled": str(package_path)}, sort_keys=True))
    if not args.submit:
        return

    client = kfp.Client(host=args.host)
    run = client.create_run_from_pipeline_package(
        pipeline_file=str(package_path),
        arguments={
            "bucket": args.bucket,
            "region": args.region,
            "trino_host": args.trino_host,
            "trino_port": args.trino_port,
            "artifact_prefix": args.artifact_prefix,
        },
        experiment_name=args.experiment,
        run_name=args.run_name,
        service_account=args.service_account,
    )
    print(
        json.dumps(
            {
                "run_id": getattr(run, "run_id", None),
                "run_name": args.run_name,
                "experiment": args.experiment,
                "service_account": args.service_account,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
