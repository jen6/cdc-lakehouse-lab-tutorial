FROM maven:3.9.11-eclipse-temurin-17 AS build

WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package

FROM flink:2.1.3-scala_2.12-java17

ARG FLINK_KAFKA_CONNECTOR_VERSION=5.0.0-2.1
ARG FLINK_VERSION=2.1.3
ARG ICEBERG_VERSION=1.11.0
ARG HADOOP_VERSION=3.3.6

RUN curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_KAFKA_CONNECTOR_VERSION}/flink-sql-connector-kafka-${FLINK_KAFKA_CONNECTOR_VERSION}.jar" \
      -o /opt/flink/lib/flink-sql-connector-kafka.jar \
    && curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/${FLINK_VERSION}/flink-metrics-prometheus-${FLINK_VERSION}.jar" \
      -o /opt/flink/lib/flink-metrics-prometheus.jar \
    && curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-2.1/${ICEBERG_VERSION}/iceberg-flink-runtime-2.1-${ICEBERG_VERSION}.jar" \
      -o /opt/flink/lib/iceberg-flink-runtime.jar \
    && curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar" \
      -o /opt/flink/lib/iceberg-aws-bundle.jar \
    && curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-api/${HADOOP_VERSION}/hadoop-client-api-${HADOOP_VERSION}.jar" \
      -o /opt/flink/lib/hadoop-client-api.jar \
    && curl -fsSL \
      "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-client-runtime/${HADOOP_VERSION}/hadoop-client-runtime-${HADOOP_VERSION}.jar" \
      -o /opt/flink/lib/hadoop-client-runtime.jar
RUN mkdir -p /opt/flink/plugins/s3-fs-hadoop \
    && cp /opt/flink/opt/flink-s3-fs-hadoop-*.jar /opt/flink/plugins/s3-fs-hadoop/

COPY --from=build /workspace/target/sql-runner.jar /opt/flink/usrlib/sql-runner.jar
