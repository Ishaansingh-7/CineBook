CREATE TABLE users (
  user_id NUMBER GENERATED ALWAYS AS IDENTITY,
  name    VARCHAR2(50)  NOT NULL,
  email   VARCHAR2(100) NOT NULL,
  phone   VARCHAR2(10),
  CONSTRAINT pk_users PRIMARY KEY (user_id),
  CONSTRAINT uq_users_email UNIQUE (email),
  CONSTRAINT chk_users_phone CHECK (REGEXP_LIKE(phone, '^[6-9][0-9]{9}$'))
);

CREATE TABLE movies (
  movie_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  title        VARCHAR2(100) NOT NULL,
  genre        VARCHAR2(30),
  language     VARCHAR2(20),
  duration_min NUMBER(3),
  certificate  VARCHAR2(2),
  CONSTRAINT pk_movies PRIMARY KEY (movie_id),
  CONSTRAINT chk_movies_duration CHECK (duration_min > 0),
  CONSTRAINT chk_movies_cert CHECK (certificate IN ('U', 'UA', 'A'))
);

CREATE TABLE screens (
  screen_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  screen_name VARCHAR2(20) NOT NULL,
  CONSTRAINT pk_screens PRIMARY KEY (screen_id),
  CONSTRAINT uq_screens_name UNIQUE (screen_name)
);

CREATE TABLE seats (
  seat_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  screen_id NUMBER NOT NULL,
  row_label CHAR(1) NOT NULL,
  seat_no   NUMBER(2) NOT NULL,
  seat_type VARCHAR2(10) DEFAULT 'REGULAR' NOT NULL,
  CONSTRAINT pk_seats PRIMARY KEY (seat_id),
  CONSTRAINT fk_seats_screen FOREIGN KEY (screen_id) REFERENCES screens (screen_id),
  CONSTRAINT uq_seats_position UNIQUE (screen_id, row_label, seat_no),
  CONSTRAINT chk_seats_type CHECK (seat_type IN ('REGULAR', 'PREMIUM'))
);

CREATE TABLE shows (
  show_id    NUMBER GENERATED ALWAYS AS IDENTITY,
  movie_id   NUMBER NOT NULL,
  screen_id  NUMBER NOT NULL,
  show_time  TIMESTAMP NOT NULL,
  base_price NUMBER(6,2) NOT NULL,
  CONSTRAINT pk_shows PRIMARY KEY (show_id),
  CONSTRAINT fk_shows_movie FOREIGN KEY (movie_id) REFERENCES movies (movie_id),
  CONSTRAINT fk_shows_screen FOREIGN KEY (screen_id) REFERENCES screens (screen_id),
  CONSTRAINT uq_shows_slot UNIQUE (screen_id, show_time),
  CONSTRAINT chk_shows_price CHECK (base_price > 0)
);

CREATE TABLE bookings (
  booking_id   NUMBER GENERATED ALWAYS AS IDENTITY,
  user_id      NUMBER NOT NULL,
  show_id      NUMBER NOT NULL,
  booked_at    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  total_amount NUMBER(8,2) DEFAULT 0 NOT NULL,
  status       VARCHAR2(10) DEFAULT 'CONFIRMED' NOT NULL,
  CONSTRAINT pk_bookings PRIMARY KEY (booking_id),
  CONSTRAINT fk_bookings_user FOREIGN KEY (user_id) REFERENCES users (user_id),
  CONSTRAINT fk_bookings_show FOREIGN KEY (show_id) REFERENCES shows (show_id),
  CONSTRAINT chk_bookings_status CHECK (status IN ('CONFIRMED', 'CANCELLED'))
);

CREATE TABLE booking_seats (
  booking_id NUMBER NOT NULL,
  seat_id    NUMBER NOT NULL,
  price      NUMBER(6,2) NOT NULL,
  CONSTRAINT pk_booking_seats PRIMARY KEY (booking_id, seat_id),
  CONSTRAINT fk_bseats_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id),
  CONSTRAINT fk_bseats_seat FOREIGN KEY (seat_id) REFERENCES seats (seat_id)
);

CREATE TABLE booking_log (
  log_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  booking_id NUMBER NOT NULL,
  action     VARCHAR2(20) NOT NULL,
  amount     NUMBER(8,2),
  logged_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_booking_log PRIMARY KEY (log_id),
  CONSTRAINT fk_log_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id),
  CONSTRAINT chk_log_action CHECK (action IN ('BOOKED', 'CANCELLED'))
);

CREATE INDEX idx_shows_movie_time ON shows (movie_id, show_time);
CREATE INDEX idx_bookings_show ON bookings (show_id, status);
CREATE INDEX idx_bookings_user ON bookings (user_id);
CREATE INDEX idx_bseats_seat ON booking_seats (seat_id);

SELECT table_name FROM user_tables ORDER BY table_name;
