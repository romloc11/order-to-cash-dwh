FROM apache/airflow:3.1.8

# Microsoft ODBC driver 18: how dbt and the extractors talk to SQL Server.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gnupg ca-certificates unixodbc git \
 && curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && curl -sSL https://packages.microsoft.com/config/debian/12/prod.list -o /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*
USER airflow

# dbt and the extractors live in their own virtualenv, so their dependencies
# never conflict with Airflow's. DAG tasks call /opt/airflow/pipeline-venv/bin/...
COPY dbt/requirements.txt /tmp/dbt-requirements.txt
COPY extractors/requirements.txt /tmp/extractors-requirements.txt
RUN python -m venv /opt/airflow/pipeline-venv \
 && /opt/airflow/pipeline-venv/bin/pip install --no-cache-dir \
      -r /tmp/dbt-requirements.txt -r /tmp/extractors-requirements.txt
