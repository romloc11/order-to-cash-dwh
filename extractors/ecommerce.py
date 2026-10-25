"""Extract the e-commerce database (MariaDB) into bronze. This is the worked example.

    docker compose run --rm extractors python -m extractors.ecommerce
"""
from __future__ import annotations

import os
from datetime import timedelta

import pymysql

from extractors import common

PROCESS = "bronze.load_ecommerce"
LOOKBACK = timedelta(days=1)          # re-read a day before the watermark; MERGE makes it harmless

# (source table, bronze table, columns in source order, primary key columns)
TABLES = [
    ("orders", "bronze.ecommerce_orders",
     ["id", "order_number", "customer_ref", "created_at", "status", "total_amount", "currency", "updated_at"],
     ["id"]),
    ("order_holds", "bronze.ecommerce_order_holds",
     ["id", "order_id", "reason", "held_at", "released_at", "release_type", "updated_at"],
     ["id"]),
]


def source_connection():
    return pymysql.connect(
        host=os.getenv("SHOP_HOST", "mariadb"),
        user="root",
        password=os.environ["MARIADB_ROOT_PASSWORD"],
        database="ecommerce",
    )


def read_source(src, table: str, columns: list[str], mark):
    """Return a cursor over the source rows changed on or after `mark` (all rows if mark is None)."""
    sql = f"SELECT {', '.join(columns)} FROM {table}"
    params: tuple = ()
    if mark is not None:
        sql += " WHERE updated_at >= %s"
        params = (mark,)
    cursor = src.cursor(pymysql.cursors.SSCursor)      # server-side cursor: streams, does not load all rows
    cursor.execute(sql, params)
    return cursor


def main() -> None:
    run = common.Run(PROCESS)
    src = source_connection()
    total = 0
    try:
        for source_table, bronze_table, columns, keys in TABLES:
            started = common.utc_now()
            mark = common.watermark(run.cursor, bronze_table, "updated_at", LOOKBACK)
            source_cursor = read_source(src, source_table, columns, mark)
            merged = common.merge_rows(run.cursor, bronze_table, columns, keys,
                                       common.iter_rows(source_cursor), run.batch_id)
            source_cursor.close()
            run.conn.commit()                          # one transaction per table
            run.log(source_table, started, merged)
            total += merged
        run.finish(total)
    except Exception as exc:
        run.fail(exc)
        raise
    finally:
        src.close()
        run.close()


if __name__ == "__main__":
    main()
