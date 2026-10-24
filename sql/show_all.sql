SET LINESIZE 150
SET PAGESIZE 100
COLUMN table_name FORMAT A15
COLUMN constraint_name FORMAT A22
COLUMN search_condition FORMAT A45
COLUMN object_name FORMAT A20
COLUMN object_type FORMAT A13
COLUMN title FORMAT A14
COLUMN name FORMAT A14
COLUMN email FORMAT A20
COLUMN screen_name FORMAT A10
COLUMN genre FORMAT A10
COLUMN language FORMAT A10

PROMPT
PROMPT ===== 1. All tables =====
SELECT table_name FROM user_tables ORDER BY table_name;

PROMPT ===== 2. Constraints on every table =====
SELECT table_name, constraint_name,
       DECODE(constraint_type, 'P', 'PRIMARY KEY', 'R', 'FOREIGN KEY', 'U', 'UNIQUE', 'C', 'CHECK') AS type
FROM user_constraints
WHERE constraint_name NOT LIKE 'SYS%'
ORDER BY table_name, constraint_type;

PROMPT ===== 3. Package, triggers and their status =====
SELECT object_name, object_type, status FROM user_objects
WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
ORDER BY object_type, object_name;

PROMPT ===== 4. Data =====
SELECT * FROM users;
SELECT * FROM movies;
SELECT * FROM screens;
SELECT screen_id, seat_type, COUNT(*) AS seats FROM seats GROUP BY screen_id, seat_type ORDER BY 1, 2;
SELECT show_id, movie_id, screen_id, TO_CHAR(show_time, 'DD-MON HH24:MI') AS show_time, base_price
FROM shows ORDER BY show_time;
SELECT booking_id, user_id, show_id, total_amount, status FROM bookings ORDER BY booking_id;
SELECT * FROM booking_seats ORDER BY booking_id, seat_id;
SELECT log_id, booking_id, action, amount, TO_CHAR(logged_at, 'DD-MON HH24:MI') AS logged_at
FROM booking_log ORDER BY log_id;
