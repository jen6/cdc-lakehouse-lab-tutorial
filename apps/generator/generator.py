import argparse
import os
import random
import time
from decimal import Decimal

import mysql.connector
from faker import Faker
from prometheus_client import Counter, Gauge, Histogram, start_http_server


fake = Faker()


EVENTS_TOTAL = Counter(
    "source_generator_events_total",
    "Number of source database mutations emitted by the generator.",
    ["action"],
)
ERRORS_TOTAL = Counter(
    "source_generator_errors_total",
    "Number of generator loop errors.",
    ["action", "exception"],
)
ACTION_DURATION_SECONDS = Histogram(
    "source_generator_action_duration_seconds",
    "Time spent applying one source database mutation.",
    ["action"],
)
TARGET_RATE = Gauge(
    "source_generator_target_rate_per_second",
    "Configured target mutation rate per second.",
)


def connect(database=None):
    return mysql.connector.connect(
        host=os.environ["MYSQL_HOST"],
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ["MYSQL_USER"],
        password=os.environ["MYSQL_PASSWORD"],
        database=database,
        autocommit=False,
    )


def bootstrap():
    conn = connect()
    cur = conn.cursor()

    try:
        cur.execute("CALL mysql.rds_set_configuration('binlog retention hours', 24)")
    except mysql.connector.Error:
        # This stored procedure exists on RDS MySQL, not on local MySQL.
        conn.rollback()

    for schema in ["commerce", "payment", "logistics"]:
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {schema}")

    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS commerce.inventory (
          sku VARCHAR(64) PRIMARY KEY,
          product_name VARCHAR(255) NOT NULL,
          quantity INT NOT NULL,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS commerce.orders (
          order_id BIGINT PRIMARY KEY AUTO_INCREMENT,
          customer_id BIGINT NOT NULL,
          status VARCHAR(32) NOT NULL,
          total_amount DECIMAL(12,2) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS commerce.order_items (
          order_item_id BIGINT PRIMARY KEY AUTO_INCREMENT,
          order_id BIGINT NOT NULL,
          sku VARCHAR(64) NOT NULL,
          quantity INT NOT NULL,
          unit_price DECIMAL(12,2) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS payment.payments (
          payment_id BIGINT PRIMARY KEY AUTO_INCREMENT,
          order_id BIGINT NOT NULL,
          status VARCHAR(32) NOT NULL,
          amount DECIMAL(12,2) NOT NULL,
          approved_at TIMESTAMP NULL,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS logistics.shipments (
          shipment_id BIGINT PRIMARY KEY AUTO_INCREMENT,
          order_id BIGINT NOT NULL,
          status VARCHAR(32) NOT NULL,
          carrier VARCHAR(64) NOT NULL,
          shipped_at TIMESTAMP NULL,
          delivered_at TIMESTAMP NULL,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )

    for idx in range(1, 501):
        sku = f"SKU-{idx:05d}"
        cur.execute(
            """
            INSERT INTO commerce.inventory (sku, product_name, quantity)
            VALUES (%s, %s, %s)
            ON DUPLICATE KEY UPDATE product_name = VALUES(product_name)
            """,
            (sku, fake.catch_phrase()[:255], random.randint(50, 500)),
        )

    conn.commit()
    cur.close()
    conn.close()


def apply_schema_change_once():
    conn = connect()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_schema = 'commerce'
          AND table_name = 'orders'
          AND column_name = 'risk_score'
        """
    )
    exists = cur.fetchone()[0] > 0
    if not exists:
        cur.execute("ALTER TABLE commerce.orders ADD COLUMN risk_score DECIMAL(5,2) NULL")
    conn.commit()
    cur.close()
    conn.close()


def create_order():
    conn = connect()
    cur = conn.cursor()

    item_count = random.randint(1, 5)
    items = []
    total = Decimal("0.00")

    for _ in range(item_count):
        sku = f"SKU-{random.randint(1, 500):05d}"
        qty = random.randint(1, 3)
        price = Decimal(random.randint(500, 50000)) / Decimal("100")
        total += price * qty
        items.append((sku, qty, price))

    cur.execute(
        "INSERT INTO commerce.orders (customer_id, status, total_amount) VALUES (%s, %s, %s)",
        (random.randint(1, 100000), "CREATED", total),
    )
    order_id = cur.lastrowid

    for sku, qty, price in items:
        cur.execute(
            "INSERT INTO commerce.order_items (order_id, sku, quantity, unit_price) VALUES (%s, %s, %s, %s)",
            (order_id, sku, qty, price),
        )
        cur.execute(
            "UPDATE commerce.inventory SET quantity = quantity - %s WHERE sku = %s",
            (qty, sku),
        )

    payment_status = "APPROVED" if random.random() > 0.08 else "FAILED"
    cur.execute(
        """
        INSERT INTO payment.payments (order_id, status, amount, approved_at)
        VALUES (%s, %s, %s, CASE WHEN %s = 'APPROVED' THEN CURRENT_TIMESTAMP ELSE NULL END)
        """,
        (order_id, payment_status, total, payment_status),
    )

    order_status = "PAID" if payment_status == "APPROVED" else "PAYMENT_FAILED"
    cur.execute("UPDATE commerce.orders SET status = %s WHERE order_id = %s", (order_status, order_id))

    if payment_status == "APPROVED":
        cur.execute(
            """
            INSERT INTO logistics.shipments (order_id, status, carrier)
            VALUES (%s, %s, %s)
            """,
            (order_id, "READY", random.choice(["CJ", "LOTTE", "HANJIN", "POST"])),
        )

    conn.commit()
    cur.close()
    conn.close()


def delete_order_item():
    conn = connect()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT oi.order_item_id
        FROM commerce.order_items oi
        JOIN commerce.orders o ON o.order_id = oi.order_id
        WHERE o.created_at < CURRENT_TIMESTAMP - INTERVAL 30 SECOND
        ORDER BY RAND()
        LIMIT 1
        """
    )
    row = cur.fetchone()
    if not row:
        conn.rollback()
        cur.close()
        conn.close()
        return

    cur.execute("DELETE FROM commerce.order_items WHERE order_item_id = %s", (row[0],))
    conn.commit()
    cur.close()
    conn.close()


def mutate_existing_order():
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT order_id FROM commerce.orders ORDER BY RAND() LIMIT 1")
    row = cur.fetchone()
    if not row:
        conn.rollback()
        return

    order_id = row[0]
    action = random.choice(["ship", "deliver", "cancel"])

    if action == "ship":
        cur.execute(
            "UPDATE logistics.shipments SET status = 'SHIPPED', shipped_at = CURRENT_TIMESTAMP WHERE order_id = %s",
            (order_id,),
        )
        cur.execute("UPDATE commerce.orders SET status = 'SHIPPED' WHERE order_id = %s", (order_id,))
    elif action == "deliver":
        cur.execute(
            "UPDATE logistics.shipments SET status = 'DELIVERED', delivered_at = CURRENT_TIMESTAMP WHERE order_id = %s",
            (order_id,),
        )
        cur.execute("UPDATE commerce.orders SET status = 'DELIVERED' WHERE order_id = %s", (order_id,))
    else:
        cur.execute("UPDATE commerce.orders SET status = 'CANCELLED' WHERE order_id = %s", (order_id,))
        cur.execute("UPDATE payment.payments SET status = 'REFUNDED' WHERE order_id = %s", (order_id,))

    conn.commit()
    cur.close()
    conn.close()


def run(rate_per_second):
    apply_schema_change_once()
    metrics_port = int(os.environ.get("METRICS_PORT", "9102"))
    start_http_server(metrics_port)
    TARGET_RATE.set(rate_per_second)
    delay = 1.0 / rate_per_second
    while True:
        action = random.random()
        if action < 0.72:
            action_name = "create_order"
            handler = create_order
        elif action < 0.92:
            action_name = "mutate_existing_order"
            handler = mutate_existing_order
        else:
            action_name = "delete_order_item"
            handler = delete_order_item

        try:
            with ACTION_DURATION_SECONDS.labels(action_name).time():
                handler()
            EVENTS_TOTAL.labels(action_name).inc()
        except Exception as exc:
            ERRORS_TOTAL.labels(action_name, exc.__class__.__name__).inc()
            raise
        time.sleep(delay)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("bootstrap")
    run_parser = sub.add_parser("run")
    run_parser.add_argument("--rate-per-second", type=float, default=1.0)
    args = parser.parse_args()

    if args.command == "bootstrap":
        bootstrap()
    elif args.command == "run":
        run(args.rate_per_second)


if __name__ == "__main__":
    main()
