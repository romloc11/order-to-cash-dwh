"""Health check of the pipeline environment.

Checks that dbt can reach the warehouse and that every source has rows in bronze.
Run it before the real pipeline: if this fails, nothing downstream should run.
"""
from datetime import datetime

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, task

DBT = "/opt/airflow/pipeline-venv/bin/dbt"
PIPELINE_PYTHON = "/opt/airflow/pipeline-venv/bin/python"
DBT_PROJECT = "/opt/airflow/project/dbt"

with DAG(
    dag_id="dwh_checks",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["lesson"],
) as dag:
    print_date = BashOperator(task_id="print_date", bash_command="date")
    dbt_debug = BashOperator(
        task_id="dbt_debug",
        bash_command=f"{DBT} debug --project-dir {DBT_PROJECT}",
    )

    @task.external_python(python=PIPELINE_PYTHON)
    def count_bronze_rows():
        import sys

        sys.path.insert(0, "/opt/airflow/project")
        from extractors.common import dwh_connection

        tables = {
            "erp": "bronze.erp_vbrk",
            "crm": "bronze.crm_res_partner",
            "ecommerce": "bronze.ecommerce_orders",
        }
        conn = dwh_connection()
        cursor = conn.cursor()
        counts = {}
        for source, table in tables.items():
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            counts[source] = cursor.fetchone()[0]
        conn.close()
        return counts

    @task
    def check_counts(counts: dict):
        for source, n in counts.items():
            print(f"{source}: {n} rows")
        empty = [s for s, n in counts.items() if n == 0]
        if empty:
            raise ValueError(f"No rows in bronze for: {empty}")

    counts = count_bronze_rows()
    print_date >> dbt_debug >> counts
    check_counts(counts)