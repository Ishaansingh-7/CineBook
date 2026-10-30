SET SERVEROUTPUT ON

CREATE OR REPLACE PROCEDURE add_upcoming_shows(p_days NUMBER DEFAULT 7) IS
  TYPE t_hours IS VARRAY(3) OF NUMBER;
  v_hours t_hours := t_hours(10, 14.5, 19);
  v_time  TIMESTAMP;
  v_added PLS_INTEGER := 0;
BEGIN
  FOR d IN 0..p_days LOOP
    FOR sc IN 1..2 LOOP
      FOR t IN 1..3 LOOP
        v_time := CAST(TRUNC(SYSDATE) + d + v_hours(t) / 24 AS TIMESTAMP);
        IF v_time > SYSTIMESTAMP THEN
          INSERT INTO shows (movie_id, screen_id, show_time, base_price)
          SELECT MOD(TO_NUMBER(TO_CHAR(v_time, 'J')) + sc + t, 4) + 1, sc, v_time,
                 CASE WHEN t = 3 THEN 250 ELSE 180 END
          FROM dual
          WHERE NOT EXISTS (SELECT 1 FROM shows WHERE screen_id = sc AND show_time = v_time);
          v_added := v_added + SQL%ROWCOUNT;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_added || ' shows added');
END add_upcoming_shows;
/

BEGIN
  DBMS_SCHEDULER.DROP_JOB('ADD_SHOWS_JOB', force => TRUE);
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'ADD_SHOWS_JOB',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'ADD_UPCOMING_SHOWS',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=5',
    enabled         => TRUE,
    comments        => 'Keeps the next 7 days of shows scheduled');
END;
/

EXEC add_upcoming_shows

COLUMN job_name FORMAT A15
COLUMN state FORMAT A10
COLUMN next_run FORMAT A14
SELECT job_name, enabled, state, TO_CHAR(next_run_date, 'DD-MON HH24:MI') AS next_run
FROM user_scheduler_jobs;
