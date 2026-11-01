WITH numbers AS (
    SELECT TOP (DATEDIFF(day, CAST('{{ var("start_date") }}' AS date), CAST('{{ var("as_of_date") }}' AS date)) + 1)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)

SELECT
    CAST(DATEADD(day, n, CAST('{{ var("start_date") }}' AS date)) AS date) AS date_day,
    YEAR(DATEADD(day, n, CAST('{{ var("start_date") }}' AS date))) AS year_num,
    MONTH(DATEADD(day, n, CAST('{{ var("start_date") }}' AS date))) AS month_num,
    CASE WHEN 
        EOMONTH(CAST(DATEADD(day, n, CAST('{{ var("start_date") }}' AS date)) AS date)) = CAST(DATEADD(day, n, CAST('{{ var("start_date") }}' AS date)) AS date)
        THEN 1
        ELSE 0
    END AS is_month_end
FROM numbers