SET SERVEROUTPUT ON
SET LINESIZE 160
SET PAGESIZE 100
SET FEEDBACK OFF
SPOOL test_results.txt

COLUMN title FORMAT A14
COLUMN status FORMAT A10
COLUMN action FORMAT A10
COLUMN seat FORMAT A5
COLUMN seat_type FORMAT A9
COLUMN row_label FORMAT A3 HEADING ROW
COLUMN logged_at FORMAT A14

VARIABLE passed NUMBER
VARIABLE b1 NUMBER
VARIABLE b2 NUMBER
VARIABLE b3 NUMBER
VARIABLE b4 NUMBER
VARIABLE s_soon NUMBER
VARIABLE rc REFCURSOR
EXEC :passed := 0

PROMPT
PROMPT ===== TC01: Available seats for a new show =====
BEGIN
  IF movie_pkg.available_seats(1) = 40 THEN
    DBMS_OUTPUT.PUT_LINE('TC01 PASS: 40 of 40 seats free');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC01 FAIL: ' || movie_pkg.available_seats(1) || ' seats free');
  END IF;
END;
/

PROMPT
PROMPT ===== TC02: Book two regular seats (A1, A2) =====
EXEC movie_pkg.book_seats(1, 1, 'A1,A2', :b1)
SELECT booking_id, user_id, show_id, total_amount, status FROM bookings WHERE booking_id = :b1;
BEGIN
  IF movie_pkg.available_seats(1) = 38 THEN
    DBMS_OUTPUT.PUT_LINE('TC02 PASS: booking ' || :b1 || ' created, 38 seats left');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC02 FAIL');
  END IF;
END;
/

PROMPT
PROMPT ===== TC03: Trigger prices premium seats at 1.5x and updates total (D1, D2) =====
EXEC movie_pkg.book_seats(2, 1, 'D1,D2', :b2)
SELECT bs.booking_id, st.row_label || st.seat_no AS seat, st.seat_type, bs.price
FROM booking_seats bs JOIN seats st ON bs.seat_id = st.seat_id
WHERE bs.booking_id IN (:b1, :b2)
ORDER BY bs.booking_id, seat;
DECLARE
  v_t1 NUMBER;
  v_t2 NUMBER;
BEGIN
  SELECT total_amount INTO v_t1 FROM bookings WHERE booking_id = :b1;
  SELECT total_amount INTO v_t2 FROM bookings WHERE booking_id = :b2;
  IF v_t1 = 360 AND v_t2 = 540 THEN
    DBMS_OUTPUT.PUT_LINE('TC03 PASS: regular total Rs 360, premium total Rs 540');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC03 FAIL: totals ' || v_t1 || ', ' || v_t2);
  END IF;
END;
/

PROMPT
PROMPT ===== TC04: Double booking is blocked and nothing is saved =====
DECLARE
  v_id NUMBER;
BEGIN
  movie_pkg.book_seats(3, 1, 'A3,A2', v_id);
  DBMS_OUTPUT.PUT_LINE('TC04 FAIL: double booking allowed');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20003 AND movie_pkg.available_seats(1) = 36 THEN
      DBMS_OUTPUT.PUT_LINE('TC04 PASS: ' || SQLERRM || ' (A3 rolled back, 36 seats still free)');
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC04 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC05: Invalid seat label =====
DECLARE
  v_id NUMBER;
BEGIN
  movie_pkg.book_seats(3, 1, 'Z9', v_id);
  DBMS_OUTPUT.PUT_LINE('TC05 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20002 THEN
      DBMS_OUTPUT.PUT_LINE('TC05 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC05 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC06: Empty seat list =====
DECLARE
  v_id NUMBER;
BEGIN
  movie_pkg.book_seats(3, 1, '', v_id);
  DBMS_OUTPUT.PUT_LINE('TC06 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20004 THEN
      DBMS_OUTPUT.PUT_LINE('TC06 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC06 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC07: More than 6 seats in one booking =====
DECLARE
  v_id NUMBER;
BEGIN
  movie_pkg.book_seats(3, 1, 'B1,B2,B3,B4,B5,B6,B7', v_id);
  DBMS_OUTPUT.PUT_LINE('TC07 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20009 THEN
      DBMS_OUTPUT.PUT_LINE('TC07 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC07 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC08: Booking a show that has already started =====
DECLARE
  v_id   NUMBER;
  v_show NUMBER;
BEGIN
  SELECT MIN(show_id) INTO v_show FROM shows WHERE show_time < SYSDATE;
  movie_pkg.book_seats(3, v_show, 'A1', v_id);
  DBMS_OUTPUT.PUT_LINE('TC08 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20001 THEN
      DBMS_OUTPUT.PUT_LINE('TC08 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC08 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC09: Cancel more than 2 hours before the show (100% refund) =====
EXEC movie_pkg.cancel_booking(:b1)
SELECT booking_id, status, total_amount FROM bookings WHERE booking_id = :b1;
SELECT booking_id, action, amount FROM booking_log WHERE booking_id = :b1 ORDER BY log_id;
DECLARE
  v_refund NUMBER;
BEGIN
  SELECT amount INTO v_refund FROM booking_log WHERE booking_id = :b1 AND action = 'CANCELLED';
  IF v_refund = 360 AND movie_pkg.available_seats(1) = 38 THEN
    DBMS_OUTPUT.PUT_LINE('TC09 PASS: refund Rs 360, seats A1 and A2 released');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC09 FAIL: refund ' || v_refund);
  END IF;
END;
/

PROMPT
PROMPT ===== TC10: Cancelling the same booking twice =====
BEGIN
  movie_pkg.cancel_booking(:b1);
  DBMS_OUTPUT.PUT_LINE('TC10 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -20006 THEN
      DBMS_OUTPUT.PUT_LINE('TC10 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC10 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC11: A released seat can be booked again =====
EXEC movie_pkg.book_seats(3, 1, 'A1', :b3)
SELECT booking_id, user_id, total_amount, status FROM bookings WHERE booking_id = :b3;
BEGIN
  IF :b3 IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('TC11 PASS: A1 rebooked as booking ' || :b3);
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC11 FAIL');
  END IF;
END;
/

PROMPT
PROMPT ===== TC12: Cancel within 2 hours of the show (50% refund) =====
BEGIN
  INSERT INTO shows (movie_id, screen_id, show_time, base_price)
  VALUES (2, 2, CAST(SYSDATE + INTERVAL '1' HOUR AS TIMESTAMP), 200)
  RETURNING show_id INTO :s_soon;
  COMMIT;
END;
/
EXEC movie_pkg.book_seats(4, :s_soon, 'B3,B4', :b4)
EXEC movie_pkg.cancel_booking(:b4)
SELECT booking_id, action, amount FROM booking_log WHERE booking_id = :b4 ORDER BY log_id;
DECLARE
  v_refund NUMBER;
BEGIN
  SELECT amount INTO v_refund FROM booking_log WHERE booking_id = :b4 AND action = 'CANCELLED';
  IF v_refund = 200 THEN
    DBMS_OUTPUT.PUT_LINE('TC12 PASS: paid Rs 400, refund Rs 200');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC12 FAIL: refund ' || v_refund);
  END IF;
END;
/

PROMPT
PROMPT ===== TC13: Phone number CHECK constraint =====
BEGIN
  INSERT INTO users (name, email, phone) VALUES ('Test', 'test@cinebook.in', '12345');
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('TC13 FAIL');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -2290 THEN
      DBMS_OUTPUT.PUT_LINE('TC13 PASS: ' || SQLERRM);
      :passed := :passed + 1;
    ELSE
      DBMS_OUTPUT.PUT_LINE('TC13 FAIL: ' || SQLERRM);
    END IF;
END;
/

PROMPT
PROMPT ===== TC14: Seat map for show 1 (REF CURSOR) =====
EXEC :rc := movie_pkg.seat_map(1)
PRINT rc
DECLARE
  rc       SYS_REFCURSOR;
  v_id     NUMBER;
  v_row    CHAR(1);
  v_no     NUMBER;
  v_type   VARCHAR2(10);
  v_price  NUMBER;
  v_status VARCHAR2(6);
  v_rows   PLS_INTEGER := 0;
  v_booked PLS_INTEGER := 0;
BEGIN
  rc := movie_pkg.seat_map(1);
  LOOP
    FETCH rc INTO v_id, v_row, v_no, v_type, v_price, v_status;
    EXIT WHEN rc%NOTFOUND;
    v_rows := v_rows + 1;
    IF v_status = 'BOOKED' THEN
      v_booked := v_booked + 1;
    END IF;
  END LOOP;
  CLOSE rc;
  IF v_rows = 40 AND v_booked = 3 THEN
    DBMS_OUTPUT.PUT_LINE('TC14 PASS: 40 seats returned, 3 booked (A1, D1, D2)');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC14 FAIL: ' || v_rows || ' seats, ' || v_booked || ' booked');
  END IF;
END;
/

PROMPT
PROMPT ===== TC15: Show report (explicit cursor) =====
BEGIN
  movie_pkg.show_report(1);
  IF movie_pkg.available_seats(1) = 37 THEN
    DBMS_OUTPUT.PUT_LINE('TC15 PASS: report generated, expected occupancy 3/40 and revenue Rs 720');
    :passed := :passed + 1;
  ELSE
    DBMS_OUTPUT.PUT_LINE('TC15 FAIL');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('TC15 FAIL: ' || SQLERRM);
END;
/

PROMPT
PROMPT ===== TC16: Tomorrow's schedule (parameterised cursor) =====
BEGIN
  movie_pkg.daily_schedule(SYSDATE + 1);
  DBMS_OUTPUT.PUT_LINE('TC16 PASS: schedule generated');
  :passed := :passed + 1;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('TC16 FAIL: ' || SQLERRM);
END;
/

PROMPT
PROMPT ===== Booking log =====
SELECT log_id, booking_id, action, amount, TO_CHAR(logged_at, 'DD-MON HH24:MI') AS logged_at
FROM booking_log ORDER BY log_id;

PROMPT
PROMPT ===== Summary =====
BEGIN
  DBMS_OUTPUT.PUT_LINE(:passed || ' of 16 test cases passed');
END;
/

SPOOL OFF
SET FEEDBACK ON
