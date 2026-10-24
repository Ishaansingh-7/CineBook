INSERT INTO users (name, email, phone) VALUES ('Ishaan Singh', 'ishaan@cinebook.in', '9876543210');
INSERT INTO users (name, email, phone) VALUES ('Aarav Mehta', 'aarav@cinebook.in', '9123456780');
INSERT INTO users (name, email, phone) VALUES ('Priya Sharma', 'priya@cinebook.in', '8765432109');
INSERT INTO users (name, email, phone) VALUES ('Rahul Verma', 'rahul@cinebook.in', '7654321098');
INSERT INTO users (name, email, phone) VALUES ('Sneha Reddy', 'sneha@cinebook.in', '6543210987');

INSERT INTO movies (title, genre, language, duration_min, certificate) VALUES ('Interstellar', 'Sci-Fi', 'English', 169, 'UA');
INSERT INTO movies (title, genre, language, duration_min, certificate) VALUES ('RRR', 'Action', 'Telugu', 187, 'UA');
INSERT INTO movies (title, genre, language, duration_min, certificate) VALUES ('3 Idiots', 'Comedy', 'Hindi', 170, 'U');
INSERT INTO movies (title, genre, language, duration_min, certificate) VALUES ('Inception', 'Thriller', 'English', 148, 'UA');

INSERT INTO screens (screen_name) VALUES ('Screen 1');
INSERT INTO screens (screen_name) VALUES ('Screen 2');

BEGIN
  FOR s IN (SELECT screen_id FROM screens ORDER BY screen_id) LOOP
    FOR r IN 1..5 LOOP
      FOR n IN 1..8 LOOP
        INSERT INTO seats (screen_id, row_label, seat_no, seat_type)
        VALUES (s.screen_id, CHR(64 + r), n, CASE WHEN r >= 4 THEN 'PREMIUM' ELSE 'REGULAR' END);
      END LOOP;
    END LOOP;
  END LOOP;
END;
/

DECLARE
  TYPE t_hours IS VARRAY(3) OF NUMBER;
  v_hours t_hours := t_hours(10, 14.5, 19);
BEGIN
  FOR d IN 1..5 LOOP
    FOR sc IN 1..2 LOOP
      FOR t IN 1..3 LOOP
        INSERT INTO shows (movie_id, screen_id, show_time, base_price)
        VALUES (MOD(d + sc + t, 4) + 1, sc,
                CAST(TRUNC(SYSDATE) + d + v_hours(t) / 24 AS TIMESTAMP),
                CASE WHEN t = 3 THEN 250 ELSE 180 END);
      END LOOP;
    END LOOP;
  END LOOP;
  INSERT INTO shows (movie_id, screen_id, show_time, base_price)
  VALUES (1, 1, CAST(TRUNC(SYSDATE) - 1 + 19 / 24 AS TIMESTAMP), 250);
END;
/

COMMIT;

SET LINESIZE 150
COLUMN title FORMAT A14
COLUMN screen_name FORMAT A10
COLUMN show_time FORMAT A16

SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL SELECT 'movies', COUNT(*) FROM movies
UNION ALL SELECT 'screens', COUNT(*) FROM screens
UNION ALL SELECT 'seats', COUNT(*) FROM seats
UNION ALL SELECT 'shows', COUNT(*) FROM shows;

SELECT s.show_id, m.title, sc.screen_name, TO_CHAR(s.show_time, 'DD-MON HH24:MI') AS show_time, s.base_price
FROM shows s
JOIN movies m ON s.movie_id = m.movie_id
JOIN screens sc ON s.screen_id = sc.screen_id
WHERE s.show_time < TRUNC(SYSDATE) + 2
ORDER BY s.show_time, sc.screen_name;
