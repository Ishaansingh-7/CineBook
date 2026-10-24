CREATE OR REPLACE PACKAGE movie_pkg AS
  c_max_seats CONSTANT PLS_INTEGER := 6;

  FUNCTION seat_price(p_show_id NUMBER, p_seat_id NUMBER) RETURN NUMBER;
  FUNCTION available_seats(p_show_id NUMBER) RETURN NUMBER;
  FUNCTION refund_calc(p_amount NUMBER, p_show_time TIMESTAMP) RETURN NUMBER;
  FUNCTION seat_map(p_show_id NUMBER) RETURN SYS_REFCURSOR;

  PROCEDURE book_seats(p_user_id NUMBER, p_show_id NUMBER, p_seats VARCHAR2, p_booking_id OUT NUMBER);
  PROCEDURE cancel_booking(p_booking_id NUMBER);
  PROCEDURE show_report(p_show_id NUMBER);
  PROCEDURE daily_schedule(p_day DATE);
END movie_pkg;
/

CREATE OR REPLACE PACKAGE BODY movie_pkg AS

  FUNCTION seat_price(p_show_id NUMBER, p_seat_id NUMBER) RETURN NUMBER IS
    v_base shows.base_price%TYPE;
    v_type seats.seat_type%TYPE;
  BEGIN
    SELECT base_price INTO v_base FROM shows WHERE show_id = p_show_id;
    SELECT seat_type INTO v_type FROM seats WHERE seat_id = p_seat_id;
    RETURN CASE v_type WHEN 'PREMIUM' THEN v_base * 1.5 ELSE v_base END;
  END seat_price;

  FUNCTION available_seats(p_show_id NUMBER) RETURN NUMBER IS
    v_total  NUMBER;
    v_booked NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total
    FROM seats st JOIN shows sh ON st.screen_id = sh.screen_id
    WHERE sh.show_id = p_show_id;

    SELECT COUNT(*) INTO v_booked
    FROM booking_seats bs JOIN bookings b ON bs.booking_id = b.booking_id
    WHERE b.show_id = p_show_id AND b.status = 'CONFIRMED';

    RETURN v_total - v_booked;
  END available_seats;

  FUNCTION refund_calc(p_amount NUMBER, p_show_time TIMESTAMP) RETURN NUMBER IS
    v_now TIMESTAMP := CAST(SYSDATE AS TIMESTAMP);
  BEGIN
    IF p_show_time <= v_now THEN
      RETURN 0;
    ELSIF p_show_time - v_now > INTERVAL '2' HOUR THEN
      RETURN p_amount;
    ELSE
      RETURN ROUND(p_amount * 0.5, 2);
    END IF;
  END refund_calc;

  FUNCTION seat_map(p_show_id NUMBER) RETURN SYS_REFCURSOR IS
    rc SYS_REFCURSOR;
  BEGIN
    OPEN rc FOR
      SELECT st.seat_id, st.row_label, st.seat_no, st.seat_type,
             movie_pkg.seat_price(p_show_id, st.seat_id) AS price,
             CASE WHEN EXISTS (SELECT 1
                               FROM booking_seats bs JOIN bookings b ON bs.booking_id = b.booking_id
                               WHERE b.show_id = p_show_id
                                 AND b.status = 'CONFIRMED'
                                 AND bs.seat_id = st.seat_id)
                  THEN 'BOOKED' ELSE 'FREE' END AS status
      FROM seats st JOIN shows s ON st.screen_id = s.screen_id
      WHERE s.show_id = p_show_id
      ORDER BY st.row_label, st.seat_no;
    RETURN rc;
  END seat_map;

  PROCEDURE book_seats(p_user_id NUMBER, p_show_id NUMBER, p_seats VARCHAR2, p_booking_id OUT NUMBER) IS
    v_screen shows.screen_id%TYPE;
    v_time   shows.show_time%TYPE;
    v_seat   seats.seat_id%TYPE;
    v_amt    bookings.total_amount%TYPE;
    v_tok    VARCHAR2(4000);
    v_count  PLS_INTEGER;
    v_taken  NUMBER;
  BEGIN
    v_count := NVL(REGEXP_COUNT(p_seats, '[^,]+'), 0);
    IF v_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20004, 'No seats selected');
    ELSIF v_count > c_max_seats THEN
      RAISE_APPLICATION_ERROR(-20009, 'Maximum ' || c_max_seats || ' seats per booking');
    END IF;

    SELECT screen_id, show_time INTO v_screen, v_time
    FROM shows WHERE show_id = p_show_id
    FOR UPDATE;

    IF v_time <= CAST(SYSDATE AS TIMESTAMP) THEN
      RAISE_APPLICATION_ERROR(-20001, 'Show has already started');
    END IF;

    INSERT INTO bookings (user_id, show_id) VALUES (p_user_id, p_show_id)
    RETURNING booking_id INTO p_booking_id;

    FOR i IN 1..v_count LOOP
      v_tok := UPPER(TRIM(REGEXP_SUBSTR(p_seats, '[^,]+', 1, i)));

      IF v_tok IS NULL OR NOT REGEXP_LIKE(v_tok, '^[A-Z][0-9]{1,2}$') THEN
        RAISE_APPLICATION_ERROR(-20002, 'Invalid seat ' || NVL(v_tok, '(blank)'));
      END IF;

      BEGIN
        SELECT seat_id INTO v_seat
        FROM seats
        WHERE screen_id = v_screen
          AND row_label = SUBSTR(v_tok, 1, 1)
          AND seat_no = TO_NUMBER(SUBSTR(v_tok, 2));
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(-20002, 'Invalid seat ' || v_tok);
      END;

      SELECT COUNT(*) INTO v_taken
      FROM booking_seats bs JOIN bookings b ON bs.booking_id = b.booking_id
      WHERE b.show_id = p_show_id AND b.status = 'CONFIRMED' AND bs.seat_id = v_seat;

      IF v_taken > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Seat ' || v_tok || ' already booked');
      END IF;

      INSERT INTO booking_seats (booking_id, seat_id) VALUES (p_booking_id, v_seat);
    END LOOP;

    SELECT total_amount INTO v_amt FROM bookings WHERE booking_id = p_booking_id;
    INSERT INTO booking_log (booking_id, action, amount) VALUES (p_booking_id, 'BOOKED', v_amt);
    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      p_booking_id := NULL;
      RAISE_APPLICATION_ERROR(-20005, 'Show not found');
    WHEN OTHERS THEN
      ROLLBACK;
      p_booking_id := NULL;
      RAISE;
  END book_seats;

  PROCEDURE cancel_booking(p_booking_id NUMBER) IS
    v_status bookings.status%TYPE;
    v_time   shows.show_time%TYPE;
  BEGIN
    SELECT b.status, s.show_time INTO v_status, v_time
    FROM bookings b JOIN shows s ON b.show_id = s.show_id
    WHERE b.booking_id = p_booking_id
    FOR UPDATE OF b.status;

    IF v_status = 'CANCELLED' THEN
      RAISE_APPLICATION_ERROR(-20006, 'Booking already cancelled');
    ELSIF v_time <= CAST(SYSDATE AS TIMESTAMP) THEN
      RAISE_APPLICATION_ERROR(-20008, 'Show has already started');
    END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;
    COMMIT;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(-20007, 'Booking not found');
    WHEN OTHERS THEN
      ROLLBACK;
      RAISE;
  END cancel_booking;

  PROCEDURE show_report(p_show_id NUMBER) IS
    CURSOR c_bk IS
      SELECT b.booking_id, u.name, b.total_amount, b.status,
             (SELECT LISTAGG(st.row_label || st.seat_no, ',') WITHIN GROUP (ORDER BY st.row_label, st.seat_no)
              FROM booking_seats bs JOIN seats st ON bs.seat_id = st.seat_id
              WHERE bs.booking_id = b.booking_id) AS seat_list
      FROM bookings b JOIN users u ON b.user_id = u.user_id
      WHERE b.show_id = p_show_id
      ORDER BY b.booking_id;
    v_rec   c_bk%ROWTYPE;
    v_title movies.title%TYPE;
    v_time  shows.show_time%TYPE;
    v_total NUMBER;
    v_rev   NUMBER := 0;
  BEGIN
    SELECT m.title, s.show_time INTO v_title, v_time
    FROM shows s JOIN movies m ON s.movie_id = m.movie_id
    WHERE s.show_id = p_show_id;

    DBMS_OUTPUT.PUT_LINE('Show ' || p_show_id || ': ' || v_title || ' | ' || TO_CHAR(v_time, 'DD-Mon HH24:MI'));
    DBMS_OUTPUT.PUT_LINE(RPAD('ID', 6) || RPAD('Customer', 16) || RPAD('Seats', 20) || RPAD('Status', 11) || 'Amount');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 59, '-'));

    OPEN c_bk;
    LOOP
      FETCH c_bk INTO v_rec;
      EXIT WHEN c_bk%NOTFOUND;
      DBMS_OUTPUT.PUT_LINE(RPAD(v_rec.booking_id, 6) || RPAD(v_rec.name, 16) || RPAD(NVL(v_rec.seat_list, '-'), 20)
                           || RPAD(v_rec.status, 11) || v_rec.total_amount);
      IF v_rec.status = 'CONFIRMED' THEN
        v_rev := v_rev + v_rec.total_amount;
      END IF;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 59, '-'));
    DBMS_OUTPUT.PUT_LINE('Bookings: ' || c_bk%ROWCOUNT);
    CLOSE c_bk;

    SELECT COUNT(*) INTO v_total
    FROM seats st JOIN shows s ON st.screen_id = s.screen_id
    WHERE s.show_id = p_show_id;

    DBMS_OUTPUT.PUT_LINE('Occupancy: ' || (v_total - available_seats(p_show_id)) || '/' || v_total
                         || '   Revenue: Rs ' || v_rev);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('Show ' || p_show_id || ' not found');
  END show_report;

  PROCEDURE daily_schedule(p_day DATE) IS
    CURSOR c_sh(d DATE) IS
      SELECT s.show_id, m.title, sc.screen_name, s.show_time, s.base_price
      FROM shows s
      JOIN movies m ON s.movie_id = m.movie_id
      JOIN screens sc ON s.screen_id = sc.screen_id
      WHERE s.show_time >= d AND s.show_time < d + 1
      ORDER BY s.show_time, sc.screen_name;
    v_count PLS_INTEGER := 0;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Schedule for ' || TO_CHAR(p_day, 'Dy DD-Mon-YYYY'));
    DBMS_OUTPUT.PUT_LINE(RPAD('Time', 7) || RPAD('Movie', 16) || RPAD('Screen', 10) || RPAD('Price', 9) || 'Free');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 46, '-'));
    FOR r IN c_sh(TRUNC(p_day)) LOOP
      DBMS_OUTPUT.PUT_LINE(RPAD(TO_CHAR(r.show_time, 'HH24:MI'), 7) || RPAD(r.title, 16) || RPAD(r.screen_name, 10)
                           || RPAD('Rs ' || r.base_price, 9) || available_seats(r.show_id));
      v_count := v_count + 1;
    END LOOP;
    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('No shows');
    END IF;
  END daily_schedule;

END movie_pkg;
/

CREATE OR REPLACE TRIGGER trg_seat_price
BEFORE INSERT ON booking_seats
FOR EACH ROW
DECLARE
  v_show bookings.show_id%TYPE;
BEGIN
  SELECT show_id INTO v_show FROM bookings WHERE booking_id = :NEW.booking_id;
  :NEW.price := movie_pkg.seat_price(v_show, :NEW.seat_id);
END;
/

CREATE OR REPLACE TRIGGER trg_booking_total
AFTER INSERT ON booking_seats
FOR EACH ROW
BEGIN
  UPDATE bookings
  SET total_amount = total_amount + :NEW.price
  WHERE booking_id = :NEW.booking_id;
END;
/

CREATE OR REPLACE TRIGGER trg_booking_cancel
AFTER UPDATE OF status ON bookings
FOR EACH ROW
WHEN (OLD.status = 'CONFIRMED' AND NEW.status = 'CANCELLED')
DECLARE
  v_time shows.show_time%TYPE;
BEGIN
  SELECT show_time INTO v_time FROM shows WHERE show_id = :NEW.show_id;
  INSERT INTO booking_log (booking_id, action, amount)
  VALUES (:NEW.booking_id, 'CANCELLED', movie_pkg.refund_calc(:NEW.total_amount, v_time));
END;
/

COLUMN object_name FORMAT A20
COLUMN object_type FORMAT A13
COLUMN name FORMAT A20
COLUMN text FORMAT A70

SELECT object_name, object_type, status
FROM user_objects
WHERE object_type IN ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
ORDER BY object_type, object_name;

SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;
