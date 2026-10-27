"""Extract the CRM database (PostgreSQL) into bronze.   <-- YOUR EXERCISE

    docker compose run --rm extractors python -m extractors.crm

Model it on extractors/ecommerce.py, then make it your own. The brief is in
replica/ejercicios/ejercicio_crm.md (outside this repo).
"""
from __future__ import annotations
import os
from datetime import timedelta
import psycopg2
from extractors import common

PROCESS = "bronze.load_crm"          # control.verify_sources already expects this name
LOOKBACK = timedelta(days=1)  


# TODO 3: TABLES, one entry per source table:
#   (source table, bronze table, columns in source order, primary key columns)
#   Tables: res_users, res_partner, collection_activity.
#   The columns must match sql/01_bronze/05_ddl_crm.sql, in that order.
TABLES: list = [
    ("res_users", "bronze.crm_res_users",
     ["id", "login", "name", "active", "create_date", "write_date"],
     ["id"]),
    ("res_partner", "bronze.crm_res_partner",
     ["id", "name", "ref", "vat", "parent_id","user_id", "active", "type", "create_date", "write_date"],
     ["id"]),
    ("collection_activity", "bronze.crm_collection_activity",
     ["id", "partner_id", "invoice_ref", "activity_type", "outcome", "promised_date", "promised_amount", "note", "user_id", "create_date", "write_date"],
     ["id"])
]


def source_connection():
    return psycopg2.connect(
        host=os.getenv("CRM_HOST", "postgres"),
        dbname="crm",
        user="crm",
        password=os.environ["POSTGRES_PASSWORD"],
    )



def read_source(src, table: str, columns: list[str], mark):
    sql = f"SELECT {', '.join(columns)} FROM {table}"
    params: tuple = ()
    if mark is not None:
        sql += " WHERE write_date >= %s"
        params = (mark,)
    cursor = src.cursor(name=f"crm_{table}")
    cursor.execute(sql, params)
    return cursor


def main() -> None:
    run = common.Run(PROCESS)
    src = None
    total = 0
    try:
        src = source_connection()
        for source_table, bronze_table, columns, keys in TABLES:
            started = common.utc_now()
            mark = common.watermark(run.cursor, bronze_table, "write_date", LOOKBACK)
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
        if src is not None:
            src.close()
        run.close()


if __name__ == "__main__":
    main()
