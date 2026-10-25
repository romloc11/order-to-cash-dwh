"""Shared building blocks for the Python extractors.

An extractor does the same few things for every table:
  1. find the watermark (how far bronze already got),
  2. read the newer rows from the source,
  3. MERGE them into the bronze table,
  4. write what happened to control.load_log.

Steps 1, 3 and 4 live here. Step 2 is specific to each source, so it lives in the extractor.
"""
from __future__ import annotations

import os
import traceback
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Iterable, Iterator, Sequence

import pyodbc


def utc_now() -> datetime:
    """Naive UTC time: the same convention as SYSUTCDATETIME() in SQL Server."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def dwh_connection() -> pyodbc.Connection:
    """Connection to the warehouse. Autocommit is off: we decide when to commit."""
    host = os.getenv("DWH_HOST", "sqlserver")
    password = os.environ["MSSQL_SA_PASSWORD"]
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={host},1433;DATABASE=dwh;UID=sa;PWD={password};TrustServerCertificate=yes",
        autocommit=False,
    )


def iter_rows(cursor, size: int = 5000) -> Iterator[tuple]:
    """Yield rows from a source cursor a chunk at a time, so a big table never sits in memory."""
    while True:
        batch = cursor.fetchmany(size)
        if not batch:
            return
        yield from batch


def watermark(cursor, table: str, column: str, lookback: timedelta) -> datetime | None:
    """Latest value of `column` already in bronze, minus a safety margin.

    None means bronze is empty, so the caller should read everything.
    """
    cursor.execute(f"SELECT MAX([{column}]) FROM {table}")
    latest = cursor.fetchone()[0]
    return None if latest is None else latest - lookback


def _plain(value):
    """Decimals are sent as text. With fast_executemany, pyodbc fixes a DECIMAL's precision from the
    first row and then fails on a later row with more digits ('Converting decimal loses precision').
    SQL Server converts the text to DECIMAL(15,2) exactly, so nothing is lost."""
    return str(value) if isinstance(value, Decimal) else value


def _chunks(rows: Iterable[Sequence], size: int) -> Iterator[list[tuple]]:
    chunk: list[tuple] = []
    for row in rows:
        chunk.append(tuple(_plain(v) for v in row))
        if len(chunk) >= size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def merge_rows(cursor, table: str, columns: Sequence[str], keys: Sequence[str],
               rows: Iterable[Sequence], batch_id: str, chunk_size: int = 5000) -> int:
    """Load `rows` into a temporary staging table, then MERGE them into `table`.

    Rows whose key already exists are updated; the rest are inserted. Nothing is deleted.
    Returns the number of rows inserted or updated.
    """
    cols = ", ".join(f"[{c}]" for c in columns)
    marks = ", ".join("?" for _ in columns)
    on = " AND ".join(f"t.[{k}] = s.[{k}]" for k in keys)
    sets = ", ".join(f"t.[{c}] = s.[{c}]" for c in columns if c not in keys)
    src_cols = ", ".join(f"s.[{c}]" for c in columns)
    merge_sql = (
        f"MERGE {table} AS t USING #stage AS s ON {on} "
        f"WHEN MATCHED THEN UPDATE SET {sets}, t._batch_id = ?, t._loaded_at = SYSUTCDATETIME() "
        f"WHEN NOT MATCHED THEN INSERT ({cols}, _batch_id) VALUES ({src_cols}, ?);"
    )

    cursor.execute("IF OBJECT_ID('tempdb..#stage') IS NOT NULL DROP TABLE #stage")
    cursor.execute(f"SELECT TOP 0 {cols} INTO #stage FROM {table}")
    cursor.fast_executemany = True          # send the whole chunk in one round trip

    merged = 0
    for chunk in _chunks(rows, chunk_size):
        cursor.execute("TRUNCATE TABLE #stage")
        cursor.executemany(f"INSERT INTO #stage ({cols}) VALUES ({marks})", chunk)
        cursor.execute(merge_sql, batch_id, batch_id)
        merged += cursor.rowcount
    return merged


class Run:
    """One run of an extractor: a batch id, a warehouse connection and the load log."""

    def __init__(self, process_name: str):
        self.process = process_name
        self.batch_id = str(uuid.uuid4())
        self.started = utc_now()
        self.conn = dwh_connection()
        self.cursor = self.conn.cursor()

    def log(self, step: str, started: datetime, rows: int | None = None,
            error: str | None = None, line: int | None = None) -> None:
        """Write one row to control.load_log (and print it) and commit it."""
        self.cursor.execute("EXEC control.log_step ?, ?, ?, ?, ?, ?, ?",
                            self.batch_id, self.process, step, started, rows, error, line)
        self.conn.commit()
        print(f"{self.process} | {step} | {rows if rows is not None else '-'} rows"
              + (f" | ERROR line {line}: {error}" if error else ""), flush=True)

    def finish(self, total_rows: int) -> None:
        """The 'total' step is what control.verify_sources looks for."""
        self.log("total", self.started, total_rows)

    def fail(self, exc: BaseException) -> None:
        """Undo the open transaction first, then log the error (a log written before it would be lost)."""
        self.conn.rollback()
        frames = traceback.extract_tb(exc.__traceback__)
        self.log("total", self.started, None, str(exc)[:4000], frames[-1].lineno if frames else None)

    def close(self) -> None:
        self.conn.close()
