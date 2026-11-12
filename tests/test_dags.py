"""Structure tests for the Airflow DAGs.

They parse the DAG files and check the shape of the graph. No task is executed,
so they need neither SQL Server nor Docker.
"""
import os
from pathlib import Path

import pytest
from airflow.models import DagBag

DAGS_FOLDER = os.environ.get(
    "DAGS_FOLDER", str(Path(__file__).resolve().parents[1] / "airflow" / "dags")
)
LOADS = ("load_erp", "load_crm", "load_ecommerce")


@pytest.fixture(scope="module")
def dagbag():
    return DagBag(dag_folder=DAGS_FOLDER, include_examples=False)


@pytest.fixture(scope="module")
def daily_load(dagbag):
    return dagbag.dags["dwh_daily_load"]


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}


def test_expected_dags_exist(dagbag):
    assert {"hello_airflow", "dwh_checks", "dwh_daily_load"} <= set(dagbag.dags)


def test_daily_load_has_the_expected_tasks(daily_load):
    assert set(daily_load.task_ids) == {
        'load_erp', 'verify_sources', 'load_crm', 'load_ecommerce', 'dbt_snapshot', 'dbt_build', 'loads_done'
    }


@pytest.mark.parametrize("task_id", LOADS)
def test_loads_run_in_parallel(daily_load, task_id):
    task = daily_load.get_task(task_id)
    assert task.upstream_task_ids == set()
    assert task.downstream_task_ids == {"loads_done"}


def test_gate_sits_between_loads_and_dbt(daily_load):
    assert daily_load.get_task("loads_done").downstream_task_ids == {"verify_sources"}
    assert daily_load.get_task("verify_sources").downstream_task_ids == {"dbt_snapshot"}
    assert daily_load.get_task("dbt_snapshot").downstream_task_ids == {"dbt_build"}


def test_loads_retry_but_dbt_does_not(daily_load):
    for task_id in LOADS:
        assert daily_load.get_task(task_id).retries == 2
    for task_id in ("dbt_snapshot", "dbt_build"):
        assert daily_load.get_task(task_id).retries == 0


def test_daily_load_is_scheduled_once_a_day(daily_load):
    assert daily_load.timetable.summary == "0 6 * * *"
    assert daily_load.max_active_runs == 1