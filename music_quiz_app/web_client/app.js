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
  remove,
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
  yearDecade: null, // valt årtionde i årtalsläget
  yearGuess: null, // valt år
  classicAnswer: null, // mitt svar i klassisk runda
  lastRound: -1,
  banner: null, // { ok: bool, text }
  error: null,
};

const PROMPTS = { song: "Vilken låt?", artist: "Vilken artist?", year: "Vilket år?" };
let classicTicker = null;

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

function baseValue(room, p) {
  return room.mode === "year" ? p.score || 0 : timelineOf(p).length;
}

function rankValue(room, p) {
  return baseValue(room, p) - (p.handicap || 0);
}

function ranking(room) {
  return Object.values(room.players || {}).sort(
    (a, b) => rankValue(room, b) - rankValue(room, a)
  );
}

function rankingRaw(room) {
  return Object.values(room.players || {}).sort(
    (a, b) => baseValue(room, b) - baseValue(room, a)
  );
}

function anyHandicap(room) {
  return Object.values(room.players || {}).some((p) => (p.handicap || 0) !== 0);
}

// Stat-hjälpare: returnerar spelarens stats med default 0, och en kopia med +1.
function statsOf(p) {
  const s = p.stats || {};
  return {
    perfect: s.perfect || 0,
    threes: s.threes || 0,
    ones: s.ones || 0,
    misses: s.misses || 0,
    steals: s.steals || 0,
  };
}
function bump(stats, ...keys) {
  const out = { ...stats };
  for (const k of keys) out[k] = (out[k] || 0) + 1;
  return out;
}

// Nästa tur (index, id) där spelaren fortfarande är kvar — hoppar över dem som lämnat.
function nextPresentTurn(room) {
  const order = room.turnOrder || [];
  if (!order.length) return null;
  for (let step = 1; step <= order.length; step++) {
    const idx = room.turnIndex + step;
    const id = order[idx % order.length];
    if (room.players && room.players[id]) return [idx, id];
  }
  return null;
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
    // Klassiskt läge: nollställ mitt svar vid ny runda.
    const round = state.room && state.room.currentRound;
    if (round && round.roundNumber !== state.lastRound) {
      state.lastRound = round.roundNumber;
      state.classicAnswer = null;
    }
    render();
  });
}

async function submitClassicAnswer(i) {
  const room = state.room;
  const round = room && room.currentRound;
  if (!round || round.revealed || state.classicAnswer != null) return;
  if (round.deadlineMs && Date.now() > round.deadlineMs) return;
  state.classicAnswer = i;
  render();
  try {
    await update(ref(db, `rooms/${state.code}/answers/${state.uid}`), {
      choice: i,
      at: Date.now(),
    });
  } catch (e) {
    setError("" + e);
  }
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
  const stats = statsOf(me);

  if (round.phase === "guessing") {
    if (correct) {
      await advanceTurn(room, round, insertSorted(myTimeline, round.track),
        (me.score || 0) + 1, bump(stats, "perfect"));
      showBanner(true, "Rätt! Kortet är ditt 🎉");
    } else {
      // Fel → nästa spelare (som är kvar) får stjäla.
      const next = nextPresentTurn(room);
      const stealer = next ? next[1] : round.activePlayerId;
      await update(ref(db, `rooms/${state.code}/currentRound`), {
        track: round.track,
        activePlayerId: round.activePlayerId,
        phase: "stealing",
        stealerId: stealer,
      });
      await update(ref(db, `rooms/${state.code}/players/${state.uid}/stats`),
        bump(stats, "misses"));
      showBanner(false, "Fel plats! Nästa spelare får chansen att stjäla.");
    }
  } else {
    // Steal-fas: jag är utmanaren.
    if (correct) {
      await advanceTurn(room, round, insertSorted(myTimeline, round.track),
        (me.score || 0) + 1, bump(stats, "perfect", "steals"));
      showBanner(true, "Stöld! Du snodde kortet 😎");
    } else {
      await advanceTurn(room, round, myTimeline, me.score || 0, bump(stats, "misses"));
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
  const s = statsOf(me);
  const newStats =
    points === 5 ? bump(s, "perfect")
    : points === 3 ? bump(s, "threes")
    : points === 1 ? bump(s, "ones")
    : bump(s, "misses");
  // Nollställ valet inför nästa tur.
  state.yearDecade = null;
  state.yearGuess = null;
  await advanceTurn(
    room,
    round,
    insertSorted(myTimeline, round.track),
    (me.score || 0) + points,
    newStats
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

async function advanceTurn(room, round, newTimeline, newScore, newStats) {
  const deck = deckOf(room);
  const next = nextPresentTurn(room);
  if (!next) {
    await update(ref(db, `rooms/${state.code}`), { status: "finished" });
    return;
  }
  const [nextTurnIndex, nextActive] = next;
  const nextTrack = deck.length ? deck[nextTurnIndex % deck.length] : round.track;

  await update(ref(db, `rooms/${state.code}`), {
    [`players/${state.uid}/timeline`]: arrayToMap(newTimeline),
    [`players/${state.uid}/score`]: newScore,
    [`players/${state.uid}/stats`]: newStats || statsOf(me()),
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

function me() {
  return (state.room && state.room.players && state.room.players[state.uid]) || {};
}

// Lämna spelet: ta bort mig ur rummet och gå tillbaka till anslutningsvyn.
async function leaveGame() {
  try {
    await remove(ref(db, `rooms/${state.code}/players/${state.uid}`));
  } catch (_) {}
  state.joined = false;
  state.room = null;
  render();
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
  // Stoppa ev. nedräknings-ticker; klassiska vyn startar om den vid behov.
  if (classicTicker) {
    clearInterval(classicTicker);
    classicTicker = null;
  }
  if (!state.uid) return; // väntar på auth
  if (!state.joined) return renderJoin();
  const room = state.room;
  if (!room) return html(`<div class="center"><div class="spinner"></div></div>`);
  if (room.status === "lobby") return renderLobby(room);
  if (room.status === "finished") return renderFinished(room);
  if (room.mode === "classic") return renderClassic(room);
  return renderGame(room);
}

function renderClassic(room) {
  const round = room.currentRound;
  if (!round || !round.options || !round.options.length) {
    html(`<div class="center">Väntar på nästa fråga…</div>`);
    return;
  }
  const totalMs = 15000;
  const now = Date.now();
  const remaining = Math.max(0, Math.min(totalMs, (round.deadlineMs || 0) - now));
  const frac = round.deadlineMs ? remaining / totalMs : 0;
  const revealed = !!round.revealed;
  const my = state.classicAnswer;

  const opts = round.options
    .map((o, i) => {
      let cls = "opt";
      if (revealed) {
        if (i === round.correctIndex) cls += " correct";
        else if (i === my) cls += " wrong";
      } else if (i === my) cls += " sel";
      const dis = revealed || my != null ? "disabled" : "";
      return `<button class="${cls}" data-opt="${i}" ${dis}>${esc(o)}</button>`;
    })
    .join("");

  html(`
    ${leaderboardHtml(room)}
    <h2 style="text-align:center">${esc(PROMPTS[round.questionType] || "")}</h2>
    <p class="muted" style="text-align:center">🔊 Lyssna på värdens telefon · Fråga ${round.roundNumber}/${room.targetCards}</p>
    ${
      revealed
        ? `<p style="text-align:center;color:#7ee2a0">Rätt svar: ${esc(round.options[round.correctIndex])}</p>`
        : `<div class="timerbar"><div class="fill" style="width:${Math.round(frac * 100)}%"></div></div>
           <p style="text-align:center">${Math.ceil(remaining / 1000)} s</p>`
    }
    <div class="opts">${opts}</div>
    ${my != null && !revealed ? '<p class="muted" style="text-align:center">Svar registrerat…</p>' : ""}
    <button class="secondary" id="leave" style="margin-top:24px">Lämna</button>
  `);

  if (!revealed && my == null) {
    appEl.querySelectorAll("[data-opt]").forEach((el) => {
      el.onclick = () => submitClassicAnswer(Number(el.dataset.opt));
    });
    // Räkna ned live.
    classicTicker = setInterval(render, 300);
  }
  wireLeave();
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
    <button class="secondary" id="leave">Lämna</button>
  `);
  wireLeave();
}

function wireLeave() {
  const b = document.getElementById("leave");
  if (b) b.onclick = () => leaveGame();
}

const MEDALS = ["🥇", "🥈", "🥉"];

function leaderboardHtml(room, raw = false) {
  const list = raw ? rankingRaw(room) : ranking(room);
  const rows = list
    .map((p, i) => {
      const v = raw ? baseValue(room, p) : rankValue(room, p);
      const val = room.mode === "timeline" ? `${v} kort` : `${v} p`;
      const hc =
        !raw && (p.handicap || 0) > 0
          ? `<span class="hc">−${p.handicap}</span>`
          : "";
      const cls = `lb-row${i === 0 ? " lead" : ""}${p.id === state.uid ? " me" : ""}`;
      return `<div class="${cls}">
        <span class="rank">${i < 3 ? MEDALS[i] : i + 1}</span>
        <span class="a">${esc(p.avatar || "🎧")}</span>
        <span class="nm">${esc(p.name)}${p.id === state.uid ? " (du)" : ""}</span>
        ${hc}<span class="val">${val}</span>
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
    actionHtml = yearPickerHtml();
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
    <button class="secondary" id="leave" style="margin-top:24px">Lämna spel</button>
  `);
  wireLeave();

  if (isYear && canAct) {
    wireYearPicker();
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

// Tvåstegs årtalsväljare: först årtionde, sedan år.
function yearPickerHtml() {
  const info = `<div class="muted">5 p exakt • 3 p 1–2 år • 1 p 3–5 år</div>`;
  if (state.yearDecade == null) {
    const maxDec = MAX_YEAR - (MAX_YEAR % 10);
    let chips = "";
    for (let d = 1950; d <= maxDec; d += 10)
      chips += `<button class="chip" data-dec="${d}">${d}-tal</button>`;
    return `<div class="card">${info}<p>Välj årtionde</p><div class="chips">${chips}</div></div>`;
  }
  const end = Math.min(state.yearDecade + 9, MAX_YEAR);
  let chips = "";
  for (let y = state.yearDecade; y <= end; y++)
    chips += `<button class="chip ${state.yearGuess === y ? "sel" : ""}" data-year="${y}">${y}</button>`;
  const ready =
    state.yearGuess != null &&
    state.yearGuess >= state.yearDecade &&
    state.yearGuess <= end;
  return `<div class="card">${info}
    <button class="secondary" id="decback">← Byt årtionde</button>
    <p>${state.yearDecade}-tal — välj år</p>
    <div class="chips">${chips}</div>
    <button id="guess" ${ready ? "" : "disabled"}>${ready ? "Gissa " + state.yearGuess : "Välj ett år"}</button>
  </div>`;
}

function wireYearPicker() {
  if (state.yearDecade == null) {
    appEl.querySelectorAll("[data-dec]").forEach((el) => {
      el.onclick = () => {
        state.yearDecade = Number(el.dataset.dec);
        state.yearGuess = null;
        render();
      };
    });
    return;
  }
  const back = document.getElementById("decback");
  if (back)
    back.onclick = () => {
      state.yearDecade = null;
      state.yearGuess = null;
      render();
    };
  appEl.querySelectorAll("[data-year]").forEach((el) => {
    el.onclick = () => {
      state.yearGuess = Number(el.dataset.year);
      render();
    };
  });
  const g = document.getElementById("guess");
  if (g && !g.disabled)
    g.onclick = () => submitYearGuess(state.yearGuess).catch((e) => setError("" + e));
}

function statLineHtml(room, emoji, label, key) {
  let top = null;
  let best = 0;
  for (const p of Object.values(room.players || {})) {
    const v = (p.stats || {})[key] || 0;
    if (v > best) {
      best = v;
      top = p;
    }
  }
  if (!top || best <= 0) return "";
  return `<div class="lb-row">
    <span class="rank">${emoji}</span>
    <span class="nm">${esc(label)}</span>
    <span class="val">${esc(top.avatar || "🎧")} ${esc(top.name)} (${best})</span>
  </div>`;
}

function renderFinished(room) {
  const winner = ranking(room)[0];
  const hc = anyHandicap(room);
  const isYear = room.mode === "year";
  let stats = statLineHtml(room, "🎯", "Flest fullpott", "perfect");
  if (isYear) {
    stats += statLineHtml(room, "🥈", "Flest treor", "threes");
    stats += statLineHtml(room, "1️⃣", "Flest ettor", "ones");
  } else {
    stats += statLineHtml(room, "😎", "Flest stölder", "steals");
  }
  stats += statLineHtml(room, "🙈", "Flest missar", "misses");
  html(`
    <div style="text-align:center">
      <div style="font-size:72px">🏆</div>
      <h1>${winner ? esc(winner.name) : "Ingen"} vann!</h1>
    </div>
    <h3>${hc ? "Slutställning (med handikapp)" : "Slutställning"}</h3>
    ${leaderboardHtml(room)}
    ${hc ? `<h3>Utan handikapp</h3>${leaderboardHtml(room, true)}` : ""}
    <h3>Kul statistik</h3>
    ${stats || '<p class="muted">Ingen statistik.</p>'}
    <button class="secondary" id="leave" style="margin-top:24px">Lämna</button>
  `);
  wireLeave();
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
