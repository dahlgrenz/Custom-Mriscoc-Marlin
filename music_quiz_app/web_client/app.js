// Webbklient för musikquizet. Serveras av värdens telefon över LAN och pratar
// med samma Firebase-databas som mobilappen. Håller ingen Spotify-uppspelning —
// låten spelas högt på värdens telefon ("jukebox").

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import {
  getAuth,
  signInAnonymously,
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";
import {
  getDatabase,
  ref,
  onValue,
  update,
  get,
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js";
import { firebaseConfig } from "./firebase-config.js";

const AVATARS = ["🎧", "🎸", "🎤", "🥁", "🎹", "🎺", "🎷", "🎻"];

// Slumpat men valbart namn: den som ansluter via QR får direkt ett namn att se.
const NAME_ADJ = ["Glada", "Snabba", "Vilda", "Coola", "Grymma", "Fräcka", "Rockiga", "Läckra"];
const NAME_NOUN = ["Gitarren", "Trumman", "Basen", "Pianot", "Mikrofonen", "Synten", "Trumpeten", "Fiolen"];
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const randomName = () => `${pick(NAME_ADJ)} ${pick(NAME_NOUN)}`;
const MAX_YEAR = new Date().getFullYear();

const appEl = document.getElementById("app");
const db = getDatabase(initializeApp(firebaseConfig));
const auth = getAuth();

const state = {
  uid: null,
  code: new URLSearchParams(location.search).get("code")?.toUpperCase() || "",
  name: randomName(), // förifyllt, men redigerbart
  avatar: pick(AVATARS),
  joined: false,
  room: null,
  yearGuess: 1990,
  banner: null, // { ok: bool, text }
  error: null,
};

// ---- Hjälpare: konvertera Firebase-mappar till ordnade arrayer ----------

function mapToSortedArray(map) {
  if (!map) return [];
  return Object.keys(map)
    .map(Number)
    .sort((a, b) => a - b)
    .map((k) => map[k]);
}

function arrayToMap(arr) {
  const out = {};
  arr.forEach((v, i) => (out[i] = v));
  return out;
}

function timelineOf(player) {
  return mapToSortedArray(player && player.timeline);
}

function deckOf(room) {
  return mapToSortedArray(room && room.deck);
}

function actorId(round) {
  if (!round) return null;
  return round.phase === "stealing"
    ? round.stealerId || round.activePlayerId
    : round.activePlayerId;
}

function rankValue(room, p) {
  return room.mode === "year" ? p.score || 0 : timelineOf(p).length;
}

function ranking(room) {
  return Object.values(room.players || {}).sort(
    (a, b) => rankValue(room, b) - rankValue(room, a)
  );
}

// ---- Spellogik (spegel av Dart-sidans Scoring) --------------------------

function isCorrectPlacement(timeline, candidate, position) {
  if (position < 0 || position > timeline.length) return false;
  const before = position > 0 ? timeline[position - 1].year : null;
  const after = position < timeline.length ? timeline[position].year : null;
  if (before !== null && candidate.year < before) return false;
  if (after !== null && candidate.year > after) return false;
  return true;
}

function insertSorted(timeline, candidate) {
  const result = timeline.slice();
  let i = 0;
  while (i < result.length && result[i].year <= candidate.year) i++;
  result.splice(i, 0, candidate);
  return result;
}

// Poäng för årtalsgissning: exakt=5, 1–2 år=3, 3–5 år=1, annars 0.
function yearGuessPoints(actual, guess) {
  const diff = Math.abs(actual - guess);
  if (diff === 0) return 5;
  if (diff <= 2) return 3;
  if (diff <= 5) return 1;
  return 0;
}

// ---- Nätverksåtgärder ---------------------------------------------------

async function joinRoom() {
  state.error = null;
  if (!state.name.trim()) return setError("Skriv ditt namn.");
  if (!state.code) return setError("Ange en rumskod.");

  const snap = await get(ref(db, `rooms/${state.code}`));
  if (!snap.exists()) return setError(`Rummet ${state.code} finns inte.`);
  const room = snap.val();
  if (room.status !== "lobby")
    return setError(`Spelet i rum ${state.code} har redan startat.`);

  await update(ref(db, `rooms/${state.code}/players/${state.uid}`), {
    id: state.uid,
    name: state.name.trim(),
    avatar: state.avatar,
    score: 0,
  });
  state.joined = true;
  subscribeRoom();
}

function subscribeRoom() {
  onValue(ref(db, `rooms/${state.code}`), (snap) => {
    state.room = snap.exists() ? snap.val() : null;
    render();
  });
}

// Placerar den nu spelande låten på [position] i min tidslinje.
// Speglar GameController.placeCurrentTrack (gissning + steal).
async function placeCurrentTrack(position) {
  const room = state.room;
  const round = room && room.currentRound;
  const me = room && room.players && room.players[state.uid];
  if (!room || !round || !me) return;
  if (actorId(round) !== state.uid) return;
  if (room.mode === "year") return; // årtalsläge använder submitYearGuess

  const myTimeline = timelineOf(me);
  const correct = isCorrectPlacement(myTimeline, round.track, position);

  if (round.phase === "guessing") {
    if (correct) {
      await advanceTurn(room, round, insertSorted(myTimeline, round.track), (me.score || 0) + 1);
      showBanner(true, "Rätt! Kortet är ditt 🎉");
    } else {
      // Fel → nästa spelare får stjäla.
      const turnOrder = room.turnOrder || [];
      const stealer = turnOrder[(room.turnIndex + 1) % turnOrder.length];
      await update(ref(db, `rooms/${state.code}/currentRound`), {
        track: round.track,
        activePlayerId: round.activePlayerId,
        phase: "stealing",
        stealerId: stealer,
      });
      showBanner(false, "Fel plats! Nästa spelare får chansen att stjäla.");
    }
  } else {
    // Steal-fas: jag är utmanaren.
    if (correct) {
      await advanceTurn(room, round, insertSorted(myTimeline, round.track), (me.score || 0) + 1);
      showBanner(true, "Stöld! Du snodde kortet 😎");
    } else {
      await advanceTurn(room, round, myTimeline, me.score || 0);
      showBanner(false, "Missade stölden — kortet försvinner.");
    }
  }
}

async function submitYearGuess(year) {
  const room = state.room;
  const round = room && room.currentRound;
  const me = room && room.players && room.players[state.uid];
  if (!room || !round || !me) return;
  if (actorId(round) !== state.uid) return;
  if (room.mode !== "year") return;

  const points = yearGuessPoints(round.track.year, year);
  const myTimeline = timelineOf(me);
  await advanceTurn(
    room,
    round,
    insertSorted(myTimeline, round.track),
    (me.score || 0) + points
  );
  const actual = round.track.year;
  const msg =
    points === 5
      ? `🎯 Full träff! Rätt år: ${actual}. +5 poäng`
      : points === 3
      ? `Nära! Rätt år: ${actual}. +3 poäng`
      : points === 1
      ? `Rätt år: ${actual}. +1 poäng`
      : `Fel — rätt år: ${actual}. 0 poäng`;
  showBanner(points > 0, msg);
}

async function advanceTurn(room, round, newTimeline, newScore) {
  const turnOrder = room.turnOrder || [];
  const deck = deckOf(room);
  const nextTurnIndex = room.turnIndex + 1;
  const nextActive = turnOrder[nextTurnIndex % turnOrder.length];
  const nextTrack = deck.length ? deck[nextTurnIndex % deck.length] : round.track;

  await update(ref(db, `rooms/${state.code}`), {
    [`players/${state.uid}/timeline`]: arrayToMap(newTimeline),
    [`players/${state.uid}/score`]: newScore,
    turnIndex: nextTurnIndex,
    currentRound: {
      track: nextTrack,
      activePlayerId: nextActive,
      phase: "guessing",
      stealerId: null,
    },
  });

  const reached =
    room.mode === "year"
      ? newScore >= room.targetCards
      : newTimeline.length >= room.targetCards;
  if (reached) {
    await update(ref(db, `rooms/${state.code}`), { status: "finished" });
  }
}

// ---- UI-hjälpare --------------------------------------------------------

function setError(msg) {
  state.error = msg;
  render();
}
function showBanner(ok, text) {
  state.banner = { ok, text };
  render();
  setTimeout(() => {
    state.banner = null;
    render();
  }, 2500);
}
const esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );

// ---- Rendering ----------------------------------------------------------

function render() {
  if (!state.uid) return; // väntar på auth
  if (!state.joined) return renderJoin();
  const room = state.room;
  if (!room) return html(`<div class="center"><div class="spinner"></div></div>`);
  if (room.status === "lobby") return renderLobby(room);
  if (room.status === "finished") return renderFinished(room);
  return renderGame(room);
}

function html(s) {
  appEl.innerHTML = s;
}

function renderJoin() {
  html(`
    <h1>🎵 Musikquiz</h1>
    <p class="muted">Gå med i spelet från din webbläsare.</p>
    <div class="card">
      <label>Rumskod</label>
      <input id="code" type="text" value="${esc(state.code)}" maxlength="6"
             style="text-transform:uppercase" />
      <label>Ditt namn</label>
      <input id="name" type="text" value="${esc(state.name)}" />
      <label>Välj avatar</label>
      <div class="avatars">
        ${AVATARS.map(
          (a) =>
            `<div class="avatar ${a === state.avatar ? "selected" : ""}" data-a="${a}">${a}</div>`
        ).join("")}
      </div>
      ${state.error ? `<p class="error">${esc(state.error)}</p>` : ""}
      <button id="join">Gå med</button>
    </div>
  `);
  document.getElementById("code").oninput = (e) =>
    (state.code = e.target.value.toUpperCase().trim());
  document.getElementById("name").oninput = (e) => (state.name = e.target.value);
  appEl.querySelectorAll(".avatar").forEach((el) => {
    el.onclick = () => {
      state.avatar = el.dataset.a;
      render();
    };
  });
  document.getElementById("join").onclick = () => joinRoom().catch((e) => setError("" + e));
}

function playerRows(room) {
  const players = Object.values(room.players || {});
  return players
    .map(
      (p) => `
      <div class="player-row">
        <span class="a">${esc(p.avatar || "🎧")}</span>
        <span>${esc(p.name)}</span>
        ${p.id === room.hostId ? `<span class="tag">Värd</span>` : ""}
      </div>`
    )
    .join("");
}

function renderLobby(room) {
  html(`
    <h1>Väntrum</h1>
    <p class="muted">Rumskod <b>${esc(room.code)}</b>${
    room.playlistName ? ` • ${esc(room.playlistName)}` : ""
  }</p>
    <div class="card">${playerRows(room)}</div>
    <p class="muted center">Väntar på att värden startar spelet…</p>
  `);
}

const MEDALS = ["🥇", "🥈", "🥉"];

function leaderboardHtml(room) {
  const rows = ranking(room)
    .map((p, i) => {
      const val =
        room.mode === "year"
          ? `${p.score || 0} p`
          : `${timelineOf(p).length} kort`;
      const cls = `lb-row${i === 0 ? " lead" : ""}${p.id === state.uid ? " me" : ""}`;
      return `<div class="${cls}">
        <span class="rank">${i < 3 ? MEDALS[i] : i + 1}</span>
        <span class="a">${esc(p.avatar || "🎧")}</span>
        <span class="nm">${esc(p.name)}${p.id === state.uid ? " (du)" : ""}</span>
        <span class="val">${val}</span>
      </div>`;
    })
    .join("");
  return `<div class="leaderboard">${rows}</div>`;
}

function renderGame(room) {
  const round = room.currentRound;
  const me = room.players[state.uid];
  const canAct = actorId(round) === state.uid;
  const isYear = room.mode === "year";
  const steal = round && round.phase === "stealing";
  const actorName = (room.players[actorId(round)] || {}).name || "–";

  let header;
  if (canAct && steal) header = "STEAL! 😎 Placera låten rätt och stjäl kortet";
  else if (canAct) header = isYear ? "Din tur — gissa utgivningsåret" : "Din tur — placera låten rätt i tiden";
  else if (steal) header = `${esc(actorName)} försöker stjäla kortet…`;
  else header = isYear ? `${esc(actorName)} gissar årtalet` : `${esc(actorName)} spelar`;

  const myTimeline = timelineOf(me);

  // Åtgärdsyta beroende på läge.
  let actionHtml = "";
  if (isYear && canAct) {
    actionHtml = `
      <div class="card">
        <div class="muted">5 p exakt • 3 p 1–2 år • 1 p 3–5 år</div>
        <div id="yearval" style="font-size:2.2rem;text-align:center;font-weight:700">${state.yearGuess}</div>
        <input id="yearslider" type="range" min="1950" max="${MAX_YEAR}" value="${state.yearGuess}" style="width:100%" />
        <button id="guess">Gissa</button>
      </div>`;
  } else if (!isYear) {
    // Tidslinje med placeringsknappar (bara när det är min tur).
    for (let i = 0; i <= myTimeline.length; i++) {
      if (canAct)
        actionHtml += `<button class="place-btn" data-pos="${i}">Placera här</button>`;
      if (i < myTimeline.length) {
        const t = myTimeline[i];
        actionHtml += cardHtml(t);
      }
    }
  }

  // I årtalsläge visas insamlade låtar som read-only board.
  const boardHtml = isYear
    ? `<h3 style="margin-top:20px">Dina låtar (${myTimeline.length})</h3>` +
      (myTimeline.length ? myTimeline.map(cardHtml).join("") : `<p class="muted">Inga låtar än.</p>`)
    : `<h3 style="margin-top:20px">Din tidslinje</h3>` +
      (myTimeline.length || canAct ? "" : `<p class="muted">Inga kort än.</p>`);

  html(`
    <p class="muted">Först till ${room.targetCards} ${isYear ? "poäng" : "kort"}</p>
    ${leaderboardHtml(room)}
    ${
      state.banner
        ? `<div class="banner ${state.banner.ok ? "ok" : "bad"}">${esc(state.banner.text)}</div>`
        : ""
    }
    <div class="nowplaying ${steal ? "steal" : ""}">
      <div>${esc(header)}</div>
      <div class="mystery">🎶</div>
      <div class="title">${round ? esc(round.track.title) : "—"}</div>
      <div class="muted">${round ? esc(round.track.artist) : ""}</div>
      <div class="muted" style="margin-top:8px">🔊 Lyssna på värdens telefon</div>
    </div>
    ${isYear ? actionHtml : `<h3 style="margin-top:20px">Din tidslinje</h3>${actionHtml || `<p class="muted">Inga kort än.</p>`}`}
    ${isYear ? boardHtml : ""}
  `);

  if (isYear && canAct) {
    const slider = document.getElementById("yearslider");
    slider.oninput = (e) => {
      state.yearGuess = Number(e.target.value);
      document.getElementById("yearval").textContent = state.yearGuess;
    };
    document.getElementById("guess").onclick = () =>
      submitYearGuess(state.yearGuess).catch((e) => setError("" + e));
  } else if (!isYear && canAct) {
    appEl.querySelectorAll(".place-btn").forEach((el) => {
      el.onclick = () =>
        placeCurrentTrack(Number(el.dataset.pos)).catch((e) => setError("" + e));
    });
  }
}

function cardHtml(t) {
  return `
    <div class="timeline-card">
      <div class="year-badge">${esc(t.year)}</div>
      <div><div><b>${esc(t.title)}</b></div>
      <div class="muted">${esc(t.artist)}</div></div>
    </div>`;
}

function renderFinished(room) {
  const winner = ranking(room)[0];
  html(`
    <div style="text-align:center">
      <div style="font-size:72px">🏆</div>
      <h1>${winner ? esc(winner.name) : "Ingen"} vann!</h1>
    </div>
    <h3>Slutställning</h3>
    ${leaderboardHtml(room)}
  `);
}

// ---- Start --------------------------------------------------------------

signInAnonymously(auth)
  .then((cred) => {
    state.uid = cred.user.uid;
    render();
  })
  .catch((e) => {
    html(`<div class="center"><p class="error">Kunde inte logga in: ${esc(
      "" + e
    )}</p></div>`);
  });
