const MAX_SEATS = 6;
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAYS_LONG = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTHS_LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const $app = document.getElementById('app');
const $toast = document.getElementById('toast');
const $modalRoot = document.getElementById('modal-root');

const state = {
  user: loadUser(),
  day: null,
  pick: { showId: null, seats: [] },
  justBooked: null,
  reportTab: 'shows',
  reportShow: null,
  reportDay: null,
};

function loadUser() {
  try {
    return JSON.parse(localStorage.getItem('cinebook.user'));
  } catch {
    return null;
  }
}

function saveUser(user) {
  try {
    if (user) localStorage.setItem('cinebook.user', JSON.stringify(user));
    else localStorage.removeItem('cinebook.user');
  } catch {
    // Storage can be unavailable in private windows; the session still works.
  }
}

/* Formatting */

const esc = (v) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const pad = (n) => String(n).padStart(2, '0');
const rupees = (n) => '₹' + Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const dayKey = (t) => {
  const d = new Date(t);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const fromKey = (key) => new Date(`${key}T00:00:00`);
const fmtTime = (t) => {
  const d = new Date(t);
  const h = d.getHours();
  return `${((h + 11) % 12) + 1}:${pad(d.getMinutes())} ${h < 12 ? 'AM' : 'PM'}`;
};
const fmtDay = (t) => {
  const d = new Date(t);
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
};
const fmtLongDay = (t) => {
  const d = new Date(t);
  return `${DAYS_LONG[d.getDay()]} ${d.getDate()} ${MONTHS_LONG[d.getMonth()]}`;
};
const fmtDuration = (m) => `${Math.floor(m / 60)}h ${m % 60}m`;
const seatLabel = (s) => s.row_label + s.seat_no;
const bySeat = (a, b) => a.localeCompare(b, undefined, { numeric: true });
const relativeDay = (key) => {
  const today = dayKey(Date.now());
  const tomorrow = dayKey(Date.now() + 864e5);
  if (key === today) return 'Today';
  if (key === tomorrow) return 'Tomorrow';
  return DAYS[fromKey(key).getDay()];
};

/* Server */

async function api(path, options = {}) {
  let res;
  try {
    res = await fetch('/api' + path, { headers: { 'Content-Type': 'application/json' }, ...options });
  } catch {
    throw new Error('CineBook can’t reach its server. Check that the python main.py window is still open.');
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  if (!res.ok) {
    const detail = data && data.detail;
    throw new Error(Array.isArray(detail) ? detail[0].msg : detail || `The server returned an error (${res.status}).`);
  }
  return data;
}

/* Feedback */

let toastTimer;

function toast(message, kind = 'ok') {
  $toast.textContent = message;
  $toast.className = kind === 'error' ? 'show error' : 'show';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    $toast.className = '';
  }, 3600);
}

function confirmDialog({ title, body, ok, cancel = 'Cancel', danger = false }) {
  return new Promise((resolve) => {
    const previous = document.activeElement;
    $modalRoot.innerHTML = `
      <div class="modal-backdrop">
        <div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
          <h2 id="modal-title">${esc(title)}</h2>
          <p>${esc(body)}</p>
          <div class="modal-actions">
            <button class="btn ghost" data-answer="no">${esc(cancel)}</button>
            <button class="btn ${danger ? 'danger' : ''}" data-answer="yes">${esc(ok)}</button>
          </div>
        </div>
      </div>`;

    const close = (answer) => {
      $modalRoot.innerHTML = '';
      document.removeEventListener('keydown', onKey);
      if (previous && previous.focus) previous.focus();
      resolve(answer);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') close(false);
    };

    document.addEventListener('keydown', onKey);
    $modalRoot.querySelector('.modal-backdrop').addEventListener('click', (e) => {
      if (e.target.classList.contains('modal-backdrop')) return close(false);
      const button = e.target.closest('[data-answer]');
      if (button) close(button.dataset.answer === 'yes');
    });
    $modalRoot.querySelector('[data-answer="no"]').focus();
  });
}

/* Routing */

const ROUTES = [
  [/^#\/?$/, showtimesPage, 'showtimes'],
  [/^#\/show\/(\d+)$/, seatsPage, 'showtimes'],
  [/^#\/ticket\/(\d+)$/, ticketPage, 'tickets'],
  [/^#\/tickets$/, ticketsPage, 'tickets'],
  [/^#\/reports$/, reportsPage, 'reports'],
];

let renderId = 0;

async function render() {
  if (!state.user) {
    loginPage();
    return;
  }

  const hash = location.hash || '#/';
  const route = ROUTES.map(([pattern, page, nav]) => ({ match: hash.match(pattern), page, nav })).find((r) => r.match);
  if (!route) {
    location.replace('#/');
    return;
  }

  shell(route.nav);
  const id = ++renderId;
  const current = () => id === renderId;
  const $main = document.getElementById('main');
  const loader = setTimeout(() => {
    if (current()) $main.innerHTML = '<div class="state loading">Loading</div>';
  }, 200);

  try {
    await route.page($main, current, route.match);
  } catch (e) {
    if (!current()) return;
    $main.innerHTML = `
      <div class="state">
        <p>${esc(e.message)}</p>
        <button class="btn ghost" id="retry">Try again</button>
      </div>`;
    document.getElementById('retry').onclick = render;
  } finally {
    clearTimeout(loader);
  }
}

function shell(nav) {
  if (!document.getElementById('main')) {
    $app.innerHTML = `
      <div class="shell">
        <aside class="sidebar">
          <a class="brand" href="#/">CineBook</a>
          <nav class="nav" aria-label="Main">
            <a href="#/" data-nav="showtimes">Showtimes</a>
            <a href="#/tickets" data-nav="tickets">My tickets</a>
            <a href="#/reports" data-nav="reports">Reports</a>
          </nav>
          <div class="account">
            <div class="account-name">${esc(state.user.name)}</div>
            <div class="account-email">${esc(state.user.email)}</div>
            <button class="link-button" id="logout">Log out</button>
          </div>
        </aside>
        <main class="main" id="main" tabindex="-1"></main>
      </div>`;

    document.getElementById('logout').onclick = async () => {
      const ok = await confirmDialog({
        title: 'Log out?',
        body: `You’re signed in as ${state.user.name}.`,
        ok: 'Log out',
      });
      if (!ok) return;
      state.user = null;
      state.pick = { showId: null, seats: [] };
      saveUser(null);
      $app.innerHTML = '';
      render();
    };
  }

  document.querySelectorAll('[data-nav]').forEach((a) => {
    if (a.dataset.nav === nav) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  });
}

function pageHead(title, sub = '', extra = '') {
  document.title = `${title} | CineBook`;
  return `
    <header class="page-head">
      <div>
        <h1 class="page-title">${esc(title)}</h1>
        ${sub ? `<p class="page-sub">${sub}</p>` : ''}
      </div>
      ${extra}
    </header>`;
}

/* Login */

function loginPage() {
  document.title = 'Log in | CineBook';
  $app.innerHTML = `
    <div class="login">
      <div class="login-panel">
        <h1 class="login-brand">CineBook</h1>
        <p class="login-sub">Choose an account to book tickets.</p>
        <div class="accounts" id="accounts"><div class="loading">Loading accounts</div></div>
        <div class="or">or log in with email</div>
        <form class="login-form" id="login-form">
          <label class="sr-only" for="email">Email</label>
          <input class="input" id="email" type="email" placeholder="name@cinebook.in" autocomplete="email" required>
          <button class="btn" type="submit">Log in</button>
        </form>
      </div>
    </div>`;

  document.getElementById('login-form').addEventListener('submit', (e) => {
    e.preventDefault();
    login(document.getElementById('email').value);
  });

  const $accounts = document.getElementById('accounts');
  api('/users')
    .then((users) => {
      $accounts.innerHTML = users
        .map(
          (u) => `
            <button class="account-btn" data-email="${esc(u.email)}">
              <strong>${esc(u.name)}</strong>
              <span>${esc(u.email)}</span>
            </button>`
        )
        .join('');
      $accounts.querySelectorAll('[data-email]').forEach((b) => {
        b.onclick = () => login(b.dataset.email);
      });
    })
    .catch((e) => {
      $accounts.innerHTML = `<p class="summary-empty">${esc(e.message)}</p>`;
    });
}

async function login(email) {
  try {
    const user = await api('/login', { method: 'POST', body: JSON.stringify({ email }) });
    state.user = user;
    saveUser(user);
    $app.innerHTML = '';
    render();
    toast(`Welcome, ${user.name.split(' ')[0]}.`);
  } catch (e) {
    toast(e.message, 'error');
  }
}

/* Showtimes */

async function showtimesPage($main, current) {
  const shows = await api('/showtimes');
  if (!current()) return;

  const days = [...new Set(shows.map((s) => dayKey(s.show_time)))];
  if (!days.length) {
    $main.innerHTML = pageHead('Showtimes') + '<div class="state">No shows are scheduled yet.</div>';
    return;
  }
  if (!days.includes(state.day)) state.day = days[0];

  const draw = () => {
    const films = new Map();
    shows
      .filter((s) => dayKey(s.show_time) === state.day)
      .forEach((s) => {
        if (!films.has(s.movie_id)) films.set(s.movie_id, { ...s, shows: [] });
        films.get(s.movie_id).shows.push(s);
      });

    $main.innerHTML = `
      ${pageHead('Showtimes', 'Pick a date, then a show to choose your seats.')}
      <div class="days" role="group" aria-label="Date">
        ${days.map(dayButton).join('')}
      </div>
      <div class="listing">
        ${[...films.values()].map(filmRow).join('')}
      </div>`;

    $main.querySelectorAll('[data-day]').forEach((b) => {
      b.onclick = () => {
        state.day = b.dataset.day;
        draw();
        $main.querySelector(`[data-day="${state.day}"]`).focus();
      };
    });
    $main.querySelectorAll('[data-show]').forEach((b) => {
      b.onclick = () => {
        location.hash = `#/show/${b.dataset.show}`;
      };
    });
  };

  draw();
}

function dayButton(key) {
  const d = fromKey(key);
  return `
    <button class="day" data-day="${key}" aria-pressed="${key === state.day}">
      <div class="day-week">${relativeDay(key)}</div>
      <div class="day-num">${d.getDate()}</div>
      <div class="day-month">${MONTHS[d.getMonth()]}</div>
    </button>`;
}

function filmRow(film) {
  return `
    <article class="film">
      <div>
        <h2 class="film-title">${esc(film.title)}</h2>
        <div class="film-meta">
          <span class="cert" title="Certificate">${esc(film.certificate)}</span>
          <span>${esc(film.genre)}</span>
          <span>${esc(film.language)}</span>
          <span>${fmtDuration(film.duration_min)}</span>
        </div>
      </div>
      <div class="times">${film.shows.map(timeButton).join('')}</div>
    </article>`;
}

function timeButton(s) {
  const left = s.free_seats;
  const [cls, text] =
    left === 0 ? ['left-none', 'Sold out'] : left <= 10 ? ['left-low', `Only ${left} left`] : ['left-ok', `${left} seats left`];
  return `
    <button class="time" data-show="${s.show_id}" ${left === 0 ? 'disabled' : ''}
      aria-label="${fmtTime(s.show_time)} in ${esc(s.screen_name)}, ${text}">
      <div class="time-clock">${fmtTime(s.show_time)}</div>
      <div class="time-screen">${esc(s.screen_name)}, from ${rupees(s.base_price)}</div>
      <div class="time-left ${cls}">${text}</div>
    </button>`;
}

/* Seat selection */

async function seatsPage($main, current, match) {
  const showId = Number(match[1]);
  const [show, seats] = await Promise.all([api(`/shows/${showId}`), api(`/shows/${showId}/seats`)]);
  if (!current()) return;

  const back = '<a class="back" href="#/">Back to showtimes</a>';
  const sub = `${fmtLongDay(show.show_time)} at ${fmtTime(show.show_time)}, ${esc(show.screen_name)}`;

  if (!show.upcoming) {
    $main.innerHTML = `${back}${pageHead(show.title, sub)}
      <div class="notice">This show has already started, so it can’t be booked any more.</div>`;
    return;
  }

  if (state.pick.showId !== showId) state.pick = { showId, seats: [] };
  const free = new Set(seats.filter((s) => s.status === 'FREE').map(seatLabel));
  state.pick.seats = state.pick.seats.filter((l) => free.has(l));

  const rows = [...new Set(seats.map((s) => s.row_label))];
  const priceOf = Object.fromEntries(seats.map((s) => [seatLabel(s), s]));

  const draw = (focusLabel) => {
    const picked = [...state.pick.seats].sort(bySeat);
    const total = picked.reduce((sum, l) => sum + priceOf[l].price, 0);
    let band = null;

    const grid = rows
      .map((r) => {
        const rowSeats = seats.filter((s) => s.row_label === r);
        const type = rowSeats[0].seat_type;
        const mid = Math.ceil(rowSeats.length / 2);
        let heading = '';
        if (type !== band) {
          band = type;
          const bandRows = rows.filter((x) => seats.find((s) => s.row_label === x).seat_type === type);
          heading = `<div class="seat-band">${type === 'PREMIUM' ? 'Premium' : 'Regular'}, rows ${bandRows[0]} to ${
            bandRows[bandRows.length - 1]
          }, ${rupees(rowSeats[0].price)} a seat</div>`;
        }
        const buttons = rowSeats
          .map((s) => {
            const l = seatLabel(s);
            const booked = s.status === 'BOOKED';
            const on = picked.includes(l);
            const kind = s.seat_type === 'PREMIUM' ? 'premium' : 'regular';
            const label = `Seat ${l}, ${kind}, ${booked ? 'already booked' : rupees(s.price)}`;
            return `<button class="seat ${kind}" data-seat="${l}" aria-pressed="${on}" aria-label="${label}" ${
              booked ? 'disabled' : ''
            }>${s.seat_no}</button>${s.seat_no === mid ? '<span class="aisle" aria-hidden="true"></span>' : ''}`;
          })
          .join('');
        return `${heading}<div class="seat-row"><span class="row-label" aria-hidden="true">${r}</span>${buttons}<span class="row-label" aria-hidden="true">${r}</span></div>`;
      })
      .join('');

    const list = picked.length
      ? `<ul class="picked">${picked
          .map(
            (l) =>
              `<li><span>${l} <span class="muted">${priceOf[l].seat_type === 'PREMIUM' ? 'Premium' : 'Regular'}</span></span><span>${rupees(
                priceOf[l].price
              )}</span></li>`
          )
          .join('')}</ul>`
      : `<p class="summary-empty">Click seats on the map to add them. You can book up to ${MAX_SEATS} at a time.</p>`;

    const bookText = picked.length ? `Book ${picked.length} seat${picked.length === 1 ? '' : 's'}` : 'Book seats';

    $main.innerHTML = `
      ${back}
      ${pageHead(show.title, sub)}
      <div class="booking-layout">
        <section class="hall" aria-label="Seat map">
          <div class="screen-arc" aria-hidden="true"></div>
          <div class="screen-label">Screen</div>
          <div class="seat-grid">${grid}</div>
          <div class="legend">
            <span><i class="swatch" style="background:var(--mint);border-color:var(--mint-edge)"></i>Regular</span>
            <span><i class="swatch" style="background:var(--pink);border-color:var(--pink-edge)"></i>Premium</span>
            <span><i class="swatch" style="background:var(--ink);border-color:var(--ink)"></i>Your selection</span>
            <span><i class="swatch" style="background:repeating-linear-gradient(135deg,#e7e5ed 0 4px,#d6d3df 4px 8px);border-color:#c9c6d3"></i>Booked</span>
          </div>
        </section>
        <aside class="summary" aria-live="polite">
          <h2>Your seats</h2>
          ${list}
          <div class="total"><span>Total</span><strong>${rupees(total)}</strong></div>
          <button class="btn block" id="book" ${picked.length ? '' : 'disabled'}>${bookText}</button>
          <p class="hint">${free.size} of ${seats.length} seats free. Cancel more than 2 hours before the show for a full refund.</p>
        </aside>
      </div>`;

    $main.querySelectorAll('[data-seat]').forEach((b) => {
      b.onclick = () => toggleSeat(b.dataset.seat);
    });
    document.getElementById('book').onclick = (e) => book(e.currentTarget);
    if (focusLabel) $main.querySelector(`[data-seat="${focusLabel}"]`)?.focus();
  };

  const toggleSeat = (l) => {
    const picks = state.pick.seats;
    if (picks.includes(l)) {
      state.pick.seats = picks.filter((x) => x !== l);
    } else if (picks.length >= MAX_SEATS) {
      toast(`You can book up to ${MAX_SEATS} seats at a time.`, 'error');
      return;
    } else {
      state.pick.seats = [...picks, l];
    }
    draw(l);
  };

  const book = async (button) => {
    button.disabled = true;
    button.textContent = 'Booking…';
    try {
      const result = await api('/bookings', {
        method: 'POST',
        body: JSON.stringify({ user_id: state.user.user_id, show_id: showId, seats: state.pick.seats }),
      });
      state.pick = { showId: null, seats: [] };
      state.justBooked = result.booking_id;
      location.hash = `#/ticket/${result.booking_id}`;
    } catch (e) {
      toast(e.message, 'error');
      state.pick.seats = [];
      render();
    }
  };

  draw();
}

/* Tickets */

function ticketHtml(b, { large = false, printing = false } = {}) {
  const cancelled = b.status === 'CANCELLED';
  const over = !cancelled && !b.upcoming;
  const classes = ['ticket', cancelled && 'cancelled', over && 'over', large && 'large', printing && 'printing'].filter(Boolean);
  const fact = (label, value) => `<div><div class="fact-label">${label}</div><div class="fact-value">${esc(value)}</div></div>`;

  return `
    <div class="${classes.join(' ')}">
      <div class="ticket-main">
        <div class="ticket-title">${esc(b.title)} <span class="cert">${esc(b.certificate)}</span></div>
        <div class="facts">
          ${fact('Date', fmtLongDay(b.show_time))}
          ${fact('Time', fmtTime(b.show_time))}
          ${fact('Screen', b.screen_name)}
          ${fact('Seats', b.seats)}
        </div>
        ${cancelled ? '<div class="stamp">Cancelled</div>' : ''}
      </div>
      <div class="ticket-stub">
        <div class="fact-label">Booking</div>
        <div class="ticket-no">${b.booking_id}</div>
        <div class="fact-value">${rupees(b.total_amount)}</div>
        ${cancelled && b.refund != null ? `<div class="fact-label">Refunded ${rupees(b.refund)}</div>` : ''}
        ${over ? '<div class="fact-label">Show over</div>' : ''}
      </div>
    </div>`;
}

async function ticketPage($main, current, match) {
  const id = Number(match[1]);
  const b = await api(`/bookings/${id}`);
  if (!current()) return;

  if (b.user_id !== state.user.user_id) {
    $main.innerHTML = pageHead(`Booking ${id}`) + '<div class="notice">This booking belongs to another account.</div>';
    return;
  }

  const fresh = state.justBooked === id;
  state.justBooked = null;

  $main.innerHTML = `
    ${fresh ? '' : '<a class="back" href="#/tickets">Back to my tickets</a>'}
    ${pageHead(
      fresh ? 'Booking confirmed' : `Booking ${id}`,
      fresh ? 'Your seats are reserved. Show the booking number at the counter.' : ''
    )}
    ${ticketHtml(b, { large: true, printing: fresh })}
    <div class="actions">
      <a class="btn" href="#/tickets">View my tickets</a>
      <a class="btn ghost" href="#/">Book another show</a>
    </div>`;
}

async function ticketsPage($main, current) {
  const list = await api(`/users/${state.user.user_id}/bookings`);
  if (!current()) return;

  const active = (b) => b.status === 'CONFIRMED' && b.upcoming;
  const upcoming = list.filter(active).sort((a, b) => new Date(a.show_time) - new Date(b.show_time));
  const past = list.filter((b) => !active(b));

  const row = (b) => `
    <div class="ticket-row">
      <a class="ticket-link" href="#/ticket/${b.booking_id}" aria-label="Booking ${b.booking_id}, ${esc(b.title)}">${ticketHtml(b)}</a>
      <div>${active(b) ? `<button class="btn ghost" data-cancel="${b.booking_id}">Cancel booking</button>` : ''}</div>
    </div>`;

  const section = (title, items, empty) => `
    <h2 class="section-title">${title}</h2>
    ${items.length ? `<div class="ticket-list">${items.map(row).join('')}</div>` : `<p class="summary-empty">${empty}</p>`}`;

  $main.innerHTML = `
    ${pageHead('My tickets', `Bookings for ${esc(state.user.name)}.`)}
    ${
      list.length
        ? section('Upcoming', upcoming, 'No upcoming shows. <a href="#/">Find a show</a> to book.') +
          (past.length ? section('Past and cancelled', past, '') : '')
        : '<div class="state">You haven’t booked anything yet. <a href="#/">Browse showtimes</a> to get started.</div>'
    }`;

  $main.querySelectorAll('[data-cancel]').forEach((button) => {
    button.onclick = () => cancelBooking(list.find((b) => b.booking_id === Number(button.dataset.cancel)));
  });
}

async function cancelBooking(b) {
  const hours = (new Date(b.show_time) - Date.now()) / 36e5;
  const refund =
    hours > 2
      ? `You’ll get a full refund of ${rupees(b.total_amount)}.`
      : `The show starts in less than 2 hours, so you’ll get half back (${rupees(b.total_amount / 2)}).`;

  const ok = await confirmDialog({
    title: `Cancel booking ${b.booking_id}?`,
    body: `${b.title}, ${fmtDay(b.show_time)} at ${fmtTime(b.show_time)}\nSeats ${b.seats}\n\n${refund}`,
    ok: 'Cancel booking',
    cancel: 'Keep booking',
    danger: true,
  });
  if (!ok) return;

  try {
    const result = await api(`/bookings/${b.booking_id}/cancel`, {
      method: 'POST',
      body: JSON.stringify({ user_id: state.user.user_id }),
    });
    toast(`Booking ${b.booking_id} cancelled. ${rupees(result.refund)} refunded.`);
    render();
  } catch (e) {
    toast(e.message, 'error');
  }
}

/* Reports */

async function reportsPage($main, current) {
  const summary = await api('/reports/summary');
  if (!current()) return;

  const stat = (value, label) => `<div class="stat"><div class="stat-value">${value}</div><div class="stat-label">${label}</div></div>`;
  const tabs = [
    ['shows', 'Shows'],
    ['schedule', 'Daily schedule'],
    ['log', 'Booking log'],
  ];

  $main.innerHTML = `
    ${pageHead('Reports', 'Live figures from the database.', '<button class="btn ghost" id="refresh">Refresh</button>')}
    <div class="stats">
      ${stat(summary.tickets, 'Tickets sold')}
      ${stat(rupees(summary.revenue), 'Revenue')}
      ${stat(summary.confirmed, 'Active bookings')}
      ${stat(summary.cancelled, 'Cancellations')}
      ${stat(rupees(summary.refunds), 'Refunded')}
      ${stat(summary.upcoming_shows, 'Upcoming shows')}
    </div>
    <div class="tabs" role="tablist">
      ${tabs
        .map(
          ([key, label]) =>
            `<button class="tab" role="tab" data-tab="${key}" aria-selected="${state.reportTab === key}">${label}</button>`
        )
        .join('')}
    </div>
    <div id="tab-panel" role="tabpanel"></div>`;

  document.getElementById('refresh').onclick = render;
  $main.querySelectorAll('[data-tab]').forEach((b) => {
    b.onclick = () => {
      state.reportTab = b.dataset.tab;
      $main.querySelectorAll('[data-tab]').forEach((t) => t.setAttribute('aria-selected', t === b));
      loadTab();
    };
  });

  const $panel = document.getElementById('tab-panel');
  const loadTab = async () => {
    const tab = state.reportTab;
    $panel.innerHTML = '<div class="state loading">Loading</div>';
    try {
      if (tab === 'shows') await showsTab($panel);
      if (tab === 'schedule') await scheduleTab($panel);
      if (tab === 'log') await logTab($panel);
    } catch (e) {
      if (state.reportTab === tab) $panel.innerHTML = `<div class="state">${esc(e.message)}</div>`;
    }
  };

  await loadTab();
}

async function showsTab($panel) {
  const shows = await api('/reports/shows');
  if (!shows.some((s) => s.show_id === state.reportShow)) {
    const firstBooked = shows.find((s) => s.upcoming && s.bookings > 0) || shows.find((s) => s.upcoming) || shows[0];
    state.reportShow = firstBooked ? firstBooked.show_id : null;
  }

  $panel.innerHTML = `
    <div class="report-layout split">
      <div class="table-wrap tall">
        <table>
          <thead>
            <tr><th>Show</th><th>Movie</th><th>When</th><th>Occupancy</th><th class="num">Revenue</th></tr>
          </thead>
          <tbody>
            ${shows
              .map((s) => {
                const sold = s.capacity - s.free_seats;
                const pct = Math.round((sold / s.capacity) * 100);
                return `
                  <tr class="clickable ${s.upcoming ? '' : 'past'}" data-report-show="${s.show_id}" tabindex="0"
                    aria-selected="${s.show_id === state.reportShow}">
                    <td>${s.show_id}</td>
                    <td>${esc(s.title)}</td>
                    <td>${fmtDay(s.show_time)}, ${fmtTime(s.show_time)}<br><span class="fact-label">${esc(s.screen_name)}</span></td>
                    <td><span class="bar" aria-hidden="true"><i style="width:${pct}%"></i></span>${sold} of ${s.capacity}</td>
                    <td class="num">${rupees(s.revenue)}</td>
                  </tr>`;
              })
              .join('')}
          </tbody>
        </table>
      </div>
      <div>
        <div class="console-caption" id="report-caption"></div>
        <pre class="console" id="report-output"></pre>
      </div>
    </div>`;

  const select = async (id) => {
    state.reportShow = id;
    $panel.querySelectorAll('[data-report-show]').forEach((tr) => {
      tr.setAttribute('aria-selected', Number(tr.dataset.reportShow) === id);
    });
    document.getElementById('report-caption').innerHTML = `Output of <code>movie_pkg.show_report(${id})</code>`;
    const $out = document.getElementById('report-output');
    $out.textContent = 'Running report…';
    try {
      const report = await api(`/reports/show/${id}`);
      if (state.reportShow === id) $out.textContent = report.lines.join('\n');
    } catch (e) {
      $out.textContent = e.message;
    }
  };

  $panel.querySelectorAll('[data-report-show]').forEach((tr) => {
    tr.onclick = () => select(Number(tr.dataset.reportShow));
    tr.onkeydown = (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        select(Number(tr.dataset.reportShow));
      }
    };
  });

  if (state.reportShow != null) await select(state.reportShow);
}

async function scheduleTab($panel) {
  if (!state.reportDay) state.reportDay = dayKey(Date.now() + 864e5);

  $panel.innerHTML = `
    <div class="toolbar">
      <label for="schedule-day">Date</label>
      <input class="input" type="date" id="schedule-day" value="${state.reportDay}">
    </div>
    <div class="console-caption" id="schedule-caption"></div>
    <pre class="console" id="schedule-output"></pre>`;

  const run = async () => {
    const day = state.reportDay;
    document.getElementById('schedule-caption').innerHTML = `Output of <code>movie_pkg.daily_schedule(DATE '${day}')</code>`;
    const $out = document.getElementById('schedule-output');
    $out.textContent = 'Running report…';
    try {
      const report = await api(`/reports/schedule?day=${day}`);
      if (state.reportDay === day) $out.textContent = report.lines.join('\n');
    } catch (e) {
      $out.textContent = e.message;
    }
  };

  document.getElementById('schedule-day').onchange = (e) => {
    if (!e.target.value) return;
    state.reportDay = e.target.value;
    run();
  };

  await run();
}

async function logTab($panel) {
  const log = await api('/reports/log');
  $panel.innerHTML = `
    <p class="table-note">Every booking and cancellation is recorded automatically. Bookings are logged by the
      <code>book_seats</code> procedure and cancellations by the <code>trg_booking_cancel</code> trigger.</p>
    ${
      log.length
        ? `<div class="table-wrap">
            <table>
              <thead>
                <tr><th>Entry</th><th>Logged</th><th>Booking</th><th>Customer</th><th>Movie</th><th>Action</th><th class="num">Amount</th></tr>
              </thead>
              <tbody>
                ${log
                  .map(
                    (l) => `
                      <tr>
                        <td>${l.log_id}</td>
                        <td>${fmtDay(l.logged_at)}, ${fmtTime(l.logged_at)}</td>
                        <td>${l.booking_id}</td>
                        <td>${esc(l.name)}</td>
                        <td>${esc(l.title)}</td>
                        <td>${
                          l.action === 'BOOKED'
                            ? '<span class="pill booked">Booked</span>'
                            : '<span class="pill cancelled">Cancelled</span>'
                        }</td>
                        <td class="num">${rupees(l.amount)} ${l.action === 'BOOKED' ? 'paid' : 'refunded'}</td>
                      </tr>`
                  )
                  .join('')}
              </tbody>
            </table>
          </div>`
        : '<div class="state">Nothing logged yet.</div>'
    }`;
}

/* Start */

window.addEventListener('hashchange', () => {
  render();
  window.scrollTo(0, 0);
});

render();
