"""Smoke test DAG: one task that prints a line. Used in lesson A1 to check the setup."""
from datetime import datetime

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

with DAG(
    dag_id="hello_airflow",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["lesson"],
) as dag:
    BashOperator(task_id="say_hello", bash_command="echo hello from airflow, edited by me")
