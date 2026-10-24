SET LINESIZE 110
SET PAGESIZE 50
COLUMN customer FORMAT A14
COLUMN movie FORMAT A14
COLUMN seats FORMAT A12
COLUMN seat FORMAT A5
COLUMN seat_type FORMAT A9
COLUMN status FORMAT A10
COLUMN show_time FORMAT A12
COLUMN action FORMAT A10

PROMPT
PROMPT ===== Latest bookings (BOOKINGS) =====
SELECT b.booking_id, u.name AS customer, m.title AS movie,
       TO_CHAR(s.show_time, 'DD-MON HH24:MI') AS show_time,
       (SELECT LISTAGG(st.row_label || st.seat_no, ',') WITHIN GROUP (ORDER BY st.row_label, st.seat_no)
        FROM booking_seats bs JOIN seats st ON bs.seat_id = st.seat_id
        WHERE bs.booking_id = b.booking_id) AS seats,
       b.total_amount, b.status
FROM bookings b
JOIN users u ON b.user_id = u.user_id
JOIN shows s ON b.show_id = s.show_id
JOIN movies m ON s.movie_id = m.movie_id
ORDER BY b.booking_id DESC
FETCH FIRST 5 ROWS ONLY;

PROMPT ===== Seats of the newest booking (BOOKING_SEATS) =====
SELECT bs.booking_id, st.row_label || st.seat_no AS seat, st.seat_type, bs.price
FROM booking_seats bs JOIN seats st ON bs.seat_id = st.seat_id
WHERE bs.booking_id = (SELECT MAX(booking_id) FROM bookings)
ORDER BY st.row_label, st.seat_no;

PROMPT ===== Latest audit entries (BOOKING_LOG) =====
SELECT log_id, booking_id, action, amount, TO_CHAR(logged_at, 'DD-MON HH24:MI') AS logged_at
FROM booking_log
ORDER BY log_id DESC
FETCH FIRST 6 ROWS ONLY;
