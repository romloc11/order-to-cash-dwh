"""Daily load of the three sources into bronze.

The ERP, CRM and e-commerce loads do not depend on each other, so they run in parallel.
`loads_done` waits for all three.
"""
from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.empty import EmptyOperator
from airflow.sdk import DAG, task

PIPELINE_PYTHON = "/opt/airflow/pipeline-venv/bin/python"
PROJECT = "/opt/airflow/project"
DBT = "/opt/airflow/pipeline-venv/bin/dbt"
DBT_PROJECT = "/opt/airflow/project/dbt"
ALERT_LOG = "/opt/airflow/logs/dwh_alerts.log"


def notify_failure(context):
    ti = context["task_instance"]
    line = (
        f"{datetime.now():%Y-%m-%d %H:%M:%S} FAILED dag={ti.dag_id} task={ti.task_id} "
        f"run={ti.run_id} try={ti.try_number}\n"
    )
    with open(ALERT_LOG, "a") as f:
        f.write(line)


with DAG(
    dag_id="dwh_daily_load",
    start_date=datetime(2026, 1, 1),
    schedule="0 6 * * *",
    max_active_runs=1,
    catchup=False,
    tags=["pipeline"],
    default_args={
        "retries": 2,
        "retry_delay": timedelta(seconds=30),
        "on_failure_callback": notify_failure,
    },
) as dag:

    @task.external_python(python=PIPELINE_PYTHON)
    def load_erp():
        import sys

        sys.path.insert(0, "/opt/airflow/project")
        from extractors.common import dwh_connection

        conn = dwh_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC bronze.load_erp")
        while cursor.nextset():
            pass
        conn.commit()
        conn.close()

    erp = load_erp()

    crm = BashOperator(
        task_id="load_crm",
        bash_command=f"cd {PROJECT} && {PIPELINE_PYTHON} -m extractors.crm",
    )

    ecommerce = BashOperator(
        task_id="load_ecommerce",
        bash_command=f"cd {PROJECT} && {PIPELINE_PYTHON} -m extractors.ecommerce",
    )

    loads_done = EmptyOperator(task_id="loads_done")

    @task.external_python(python=PIPELINE_PYTHON)
    def verify_sources():
        import sys

        sys.path.insert(0, "/opt/airflow/project")
        from extractors.common import dwh_connection

        conn = dwh_connection()
        cursor = conn.cursor()
        cursor.execute("EXEC control.verify_sources")
        conn.close()

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"{DBT} snapshot --project-dir {DBT_PROJECT}",
        retries=0,
    )
    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=f"{DBT} build --project-dir {DBT_PROJECT}",
        retries=0,
    )

    [erp, crm, ecommerce] >> loads_done >> verify_sources() >> dbt_snapshot >> dbt_build