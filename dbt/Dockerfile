FROM python:3.12-slim

# Microsoft ODBC driver 18: how dbt talks to SQL Server.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gnupg ca-certificates unixodbc git \
 && curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && curl -sSL https://packages.microsoft.com/config/debian/12/prod.list -o /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/app/dbt
COPY dbt/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

ENV DBT_PROFILES_DIR=/usr/app/dbt
ENTRYPOINT ["dbt"]
