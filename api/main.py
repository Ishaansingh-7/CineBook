import os
import threading
import webbrowser
from datetime import date, timedelta
from pathlib import Path

import oracledb
import uvicorn
from fastapi import APIRouter, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

HOST = "127.0.0.1"
PORT = int(os.getenv("PORT", "8000"))
WEB_DIR = Path(__file__).resolve().parent.parent / "web"

pool = oracledb.create_pool(
    user=os.getenv("DB_USER", "movie"),
    password=os.getenv("DB_PASS", "movie123"),
    dsn=os.getenv("DB_DSN", "localhost:1521/FREEPDB1"),
    min=1,
    max=4,
)

app = FastAPI(title="CineBook API", version="2.0")
api = APIRouter(prefix="/api")


class Login(BaseModel):
    email: str


class BookingIn(BaseModel):
    user_id: int
    show_id: int
    seats: list[str] = Field(min_length=1, max_length=6)


class CancelIn(BaseModel):
    user_id: int


def rows(cur):
    cols = [d[0].lower() for d in cur.description]
    return [dict(zip(cols, r)) for r in cur]


def query(sql, **params):
    with pool.acquire() as con:
        cur = con.cursor()
        cur.execute(sql, params)
        return rows(cur)


def db_error(e):
    err = e.args[0]
    msg = err.message.split("\n")[0]
    if 20000 <= err.code <= 20999:
        raise HTTPException(400, msg.split(": ", 1)[-1])
    if err.code == 2291:
        raise HTTPException(400, "Unknown user or show")
    raise HTTPException(500, msg)


def plsql_output(procedure, args):
    with pool.acquire() as con:
        cur = con.cursor()
        cur.callproc("dbms_output.enable", [None])
        cur.callproc(procedure, args)
        line = cur.var(str, 4000)
        status = cur.var(int)
        lines = []
        while True:
            cur.callproc("dbms_output.get_line", [line, status])
            if status.getvalue() != 0:
                break
            lines.append(line.getvalue() or "")
        return lines


@app.exception_handler(oracledb.Error)
async def database_unavailable(request: Request, exc: oracledb.Error):
    message = exc.args[0].message.split("\n")[0]
    return JSONResponse(status_code=503, content={"detail": f"Database error: {message}"})


BOOKING_SQL = """
    SELECT b.booking_id, b.user_id, m.title, m.language, m.certificate,
           s.show_id, s.show_time, sc.screen_name, b.booked_at, b.total_amount, b.status,
           (SELECT LISTAGG(st.row_label || st.seat_no, ', ') WITHIN GROUP (ORDER BY st.row_label, st.seat_no)
            FROM booking_seats bs JOIN seats st ON bs.seat_id = st.seat_id
            WHERE bs.booking_id = b.booking_id) AS seats,
           (SELECT MAX(l.amount) FROM booking_log l
            WHERE l.booking_id = b.booking_id AND l.action = 'CANCELLED') AS refund,
           CASE WHEN s.show_time > SYSDATE THEN 1 ELSE 0 END AS upcoming
    FROM bookings b
    JOIN shows s ON b.show_id = s.show_id
    JOIN movies m ON s.movie_id = m.movie_id
    JOIN screens sc ON s.screen_id = sc.screen_id
"""


@api.get("/health")
def health():
    return {"database": query("SELECT 'up' AS status FROM dual")[0]["status"]}


@api.get("/users")
def users():
    return query("SELECT user_id, name, email FROM users ORDER BY user_id")


@api.post("/login")
def login(body: Login):
    found = query(
        "SELECT user_id, name, email FROM users WHERE LOWER(email) = LOWER(:e)",
        e=body.email.strip(),
    )
    if not found:
        raise HTTPException(404, "No account with that email. Pick one of the accounts above.")
    return found[0]


@api.get("/movies")
def movies():
    return query(
        """SELECT m.movie_id, m.title, m.genre, m.language, m.duration_min, m.certificate,
                  (SELECT COUNT(*) FROM shows s
                   WHERE s.movie_id = m.movie_id AND s.show_time > SYSDATE) AS upcoming_shows
           FROM movies m
           ORDER BY m.title"""
    )


@api.get("/showtimes")
def showtimes():
    return query(
        """SELECT s.show_id, s.show_time, s.base_price, sc.screen_name,
                  m.movie_id, m.title, m.genre, m.language, m.duration_min, m.certificate,
                  movie_pkg.available_seats(s.show_id) AS free_seats
           FROM shows s
           JOIN movies m ON s.movie_id = m.movie_id
           JOIN screens sc ON s.screen_id = sc.screen_id
           WHERE s.show_time > SYSDATE
           ORDER BY s.show_time, sc.screen_name"""
    )


@api.get("/shows/{show_id}")
def show(show_id: int):
    found = query(
        """SELECT s.show_id, s.show_time, s.base_price, sc.screen_name,
                  m.movie_id, m.title, m.genre, m.language, m.duration_min, m.certificate,
                  movie_pkg.available_seats(s.show_id) AS free_seats,
                  CASE WHEN s.show_time > SYSDATE THEN 1 ELSE 0 END AS upcoming
           FROM shows s
           JOIN movies m ON s.movie_id = m.movie_id
           JOIN screens sc ON s.screen_id = sc.screen_id
           WHERE s.show_id = :s""",
        s=show_id,
    )
    if not found:
        raise HTTPException(404, "Show not found")
    return found[0]


@api.get("/shows/{show_id}/seats")
def seats(show_id: int):
    with pool.acquire() as con:
        cur = con.cursor()
        rc = cur.callfunc("movie_pkg.seat_map", oracledb.DB_TYPE_CURSOR, [show_id])
        result = rows(rc)
    if not result:
        raise HTTPException(404, "Show not found")
    return result


@api.post("/bookings")
def book(body: BookingIn):
    with pool.acquire() as con:
        cur = con.cursor()
        booking_id = cur.var(int)
        try:
            cur.callproc("movie_pkg.book_seats", [body.user_id, body.show_id, ",".join(body.seats), booking_id])
        except oracledb.DatabaseError as e:
            db_error(e)
        cur.execute("SELECT total_amount FROM bookings WHERE booking_id = :b", b=booking_id.getvalue())
        return {"booking_id": booking_id.getvalue(), "total_amount": cur.fetchone()[0]}


@api.get("/bookings/{booking_id}")
def booking(booking_id: int):
    found = query(BOOKING_SQL + " WHERE b.booking_id = :b", b=booking_id)
    if not found:
        raise HTTPException(404, "Booking not found")
    return found[0]


@api.get("/users/{user_id}/bookings")
def user_bookings(user_id: int):
    return query(BOOKING_SQL + " WHERE b.user_id = :u ORDER BY s.show_time DESC, b.booking_id DESC", u=user_id)


@api.post("/bookings/{booking_id}/cancel")
def cancel(booking_id: int, body: CancelIn):
    with pool.acquire() as con:
        cur = con.cursor()
        cur.execute("SELECT user_id FROM bookings WHERE booking_id = :b", b=booking_id)
        owner = cur.fetchone()
        if owner is None:
            raise HTTPException(404, "Booking not found")
        if owner[0] != body.user_id:
            raise HTTPException(403, "This booking belongs to another account")
        try:
            cur.callproc("movie_pkg.cancel_booking", [booking_id])
        except oracledb.DatabaseError as e:
            db_error(e)
        cur.execute(
            "SELECT MAX(amount) FROM booking_log WHERE booking_id = :b AND action = 'CANCELLED'",
            b=booking_id,
        )
        return {"booking_id": booking_id, "refund": cur.fetchone()[0]}


@api.get("/reports/summary")
def report_summary():
    return query(
        """SELECT
             (SELECT COUNT(*) FROM booking_seats bs JOIN bookings b ON bs.booking_id = b.booking_id
              WHERE b.status = 'CONFIRMED') AS tickets,
             (SELECT NVL(SUM(total_amount), 0) FROM bookings WHERE status = 'CONFIRMED') AS revenue,
             (SELECT COUNT(*) FROM bookings WHERE status = 'CONFIRMED') AS confirmed,
             (SELECT COUNT(*) FROM bookings WHERE status = 'CANCELLED') AS cancelled,
             (SELECT NVL(SUM(amount), 0) FROM booking_log WHERE action = 'CANCELLED') AS refunds,
             (SELECT COUNT(*) FROM shows WHERE show_time > SYSDATE) AS upcoming_shows
           FROM dual"""
    )[0]


@api.get("/reports/shows")
def report_shows():
    return query(
        """SELECT s.show_id, m.title, sc.screen_name, s.show_time,
                  (SELECT COUNT(*) FROM seats st WHERE st.screen_id = s.screen_id) AS capacity,
                  movie_pkg.available_seats(s.show_id) AS free_seats,
                  (SELECT COUNT(*) FROM bookings b
                   WHERE b.show_id = s.show_id AND b.status = 'CONFIRMED') AS bookings,
                  (SELECT NVL(SUM(b.total_amount), 0) FROM bookings b
                   WHERE b.show_id = s.show_id AND b.status = 'CONFIRMED') AS revenue,
                  CASE WHEN s.show_time > SYSDATE THEN 1 ELSE 0 END AS upcoming
           FROM shows s
           JOIN movies m ON s.movie_id = m.movie_id
           JOIN screens sc ON s.screen_id = sc.screen_id
           ORDER BY s.show_time, sc.screen_name"""
    )


@api.get("/reports/show/{show_id}")
def report_show(show_id: int):
    return {"show_id": show_id, "lines": plsql_output("movie_pkg.show_report", [show_id])}


@api.get("/reports/schedule")
def report_schedule(day: date | None = None):
    day = day or date.today() + timedelta(days=1)
    return {"day": day.isoformat(), "lines": plsql_output("movie_pkg.daily_schedule", [day])}


@api.get("/reports/log")
def report_log():
    return query(
        """SELECT l.log_id, l.booking_id, l.action, l.amount, l.logged_at, u.name, m.title
           FROM booking_log l
           JOIN bookings b ON l.booking_id = b.booking_id
           JOIN users u ON b.user_id = u.user_id
           JOIN shows s ON b.show_id = s.show_id
           JOIN movies m ON s.movie_id = m.movie_id
           ORDER BY l.log_id DESC
           FETCH FIRST 100 ROWS ONLY"""
    )


app.include_router(api)
app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")


if __name__ == "__main__":
    url = f"http://localhost:{PORT}"
    print(f"\n  CineBook is running at {url}")
    print("  Keep this window open while you use the app. Press Ctrl+C to stop.\n")
    threading.Timer(1.5, lambda: webbrowser.open(url)).start()
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")
