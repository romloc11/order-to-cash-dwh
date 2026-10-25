-- E-commerce source, simulated in MariaDB.
-- Runs once, the first time the mariadb container starts with an empty data volume.
-- `customer_ref` is the ERP customer number WITHOUT leading zeros.
-- An order can be held for several reasons at once: order_holds has one row per reason.

CREATE TABLE orders (
    id            INT PRIMARY KEY,
    order_number  VARCHAR(20)   NOT NULL,
    customer_ref  VARCHAR(20)   NOT NULL,
    created_at    DATETIME      NOT NULL,
    status        VARCHAR(20)   NOT NULL,   -- confirmed, held, cancelled
    total_amount  DECIMAL(15,2) NOT NULL,
    currency      CHAR(3)       NOT NULL,
    updated_at    DATETIME      NOT NULL,
    KEY ix_orders_updated_at (updated_at),
    KEY ix_orders_customer (customer_ref)
);

CREATE TABLE order_holds (
    id            INT PRIMARY KEY,
    order_id      INT          NOT NULL,
    reason        VARCHAR(30)  NOT NULL,    -- ERP_BLOCK, CREDIT_LIMIT, OVERDUE_BALANCE
    held_at       DATETIME     NOT NULL,
    released_at   DATETIME     NULL,        -- NULL while the order is still in the pool
    release_type  VARCHAR(20)  NULL,        -- auto, manual, cancelled
    updated_at    DATETIME     NOT NULL,
    KEY ix_order_holds_updated_at (updated_at),
    CONSTRAINT fk_order_holds_order FOREIGN KEY (order_id) REFERENCES orders (id)
);

LOAD DATA INFILE '/seed/ecommerce/orders.csv' INTO TABLE orders
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA INFILE '/seed/ecommerce/order_holds.csv' INTO TABLE order_holds
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
    (id, order_id, reason, held_at, @released_at, @release_type, updated_at)
    SET released_at = NULLIF(@released_at, ''), release_type = NULLIF(@release_type, '');
