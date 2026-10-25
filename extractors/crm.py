"""Extract the CRM database (PostgreSQL) into bronze.   <-- YOUR EXERCISE

    docker compose run --rm extractors python -m extractors.crm

Model it on extractors/ecommerce.py, then make it your own. The brief is in
replica/ejercicios/ejercicio_crm.md (outside this repo).
"""
from __future__ import annotations

# TODO 1: imports (os, timedelta, psycopg2, and `from extractors import common`)

PROCESS = "bronze.load_crm"          # control.verify_sources already expects this name

# TODO 2: LOOKBACK, the safety margin before the watermark

# TODO 3: TABLES, one entry per source table:
#   (source table, bronze table, columns in source order, primary key columns)
#   Tables: res_users, res_partner, collection_activity.
#   The columns must match sql/01_bronze/05_ddl_crm.sql, in that order.
TABLES: list = []


def source_connection():
    # TODO 4: connect to PostgreSQL. Host from the CRM_HOST env var (default "postgres"),
    #         database "crm", user "crm", password from POSTGRES_PASSWORD.
    raise NotImplementedError


def read_source(src, table: str, columns: list[str], mark):
    # TODO 5: return a cursor over the rows whose write_date is on or after `mark`
    #         (all rows when mark is None). Careful: PostgreSQL has a different cursor API
    #         and a different way of streaming rows than PyMySQL.
    raise NotImplementedError


def main() -> None:
    # TODO 6: the same loop as ecommerce.main(): run, watermark, read, merge, commit, log, finish, fail.
    raise NotImplementedError


if __name__ == "__main__":
    main()
