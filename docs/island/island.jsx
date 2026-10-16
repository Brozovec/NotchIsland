// NotchIsland – interaktivní replika ostrůvku pro web (React). Rozměry v DIP jako v aplikaci: sbalený 300×36, rozbalený 900×152 (rozvrh 250).
import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

const I = ({ n, brand, style, className }) => <i className={`${brand ? "fa-brands" : "fa-solid"} fa-${n}${className ? " " + className : ""}`} style={style} />;
const TABS = [
  ["home", "house", "Island"], ["tray", "inbox", "Tray"], ["transit", "train-subway", "Transit"], ["calls", "phone", "Calls"], ["shot", "camera", "Shot"],
  ["notes", "note-sticky", "Notes"], ["clipboard", "clipboard", "Clipboard"], ["timer", "stopwatch", "Timer"], ["timetable", "graduation-cap", "Timetable"],
];
const ART = "https://image-cdn-fa.spotifycdn.com/image/ab67616d00001e028863bc11d2aa12b54f5aeb36";

function Equalizer({ active, size = 18 }) {
  const [lv, setLv] = useState([0.3, 0.6, 0.4, 0.8]);
  useEffect(() => { if (!active) return; const t = setInterval(() => setLv(lv.map(() => 0.15 + Math.random() * 0.85)), 120); return () => clearInterval(t); }, [active]);
  return <div className="ni-eq" style={{ width: size, height: size * 0.78 }}>{lv.map((v, i) => <span key={i} style={{ height: `${(active ? v : 0.12) * 100}%` }} />)}</div>;
}

function Home({ playing, setPlaying }) {
  const days = useMemo(() => { const d = new Date(); const out = []; for (let i = -3; i <= 3; i++) { const x = new Date(d); x.setDate(d.getDate() + i); out.push(x); } return out; }, []);
  const [sel, setSel] = useState(3);
  const month = days[sel].toLocaleString("en", { month: "short" });
  return (
    <div className="ni-home">
      <div className="ni-music">
        <div className="ni-art"><img src={ART} alt="" /><span className="ni-badge"><I n="spotify" brand /></span></div>
        <div className="ni-mtxt">
          <b>Blinding Lights</b><span>After Hours</span><span>The Weeknd</span>
          <div className="ni-ctl"><button><I n="backward-step" /></button><button onClick={() => setPlaying(!playing)}><I n={playing ? "pause" : "play"} /></button><button><I n="forward-step" /></button></div>
        </div>
        <div className="ni-eqwrap"><Equalizer active={playing} size={22} /></div>
      </div>
      <div className="ni-sep" />
      <div className="ni-cal">
        <div className="ni-days"><b>{month}</b>{days.map((d, i) => <button key={i} className={i === sel ? "on" : ""} onClick={() => setSel(i)}><small>{d.toLocaleString("en", { weekday: "narrow" })}</small><span>{d.getDate()}</span></button>)}</div>
        <div className="ni-empty"><I n="calendar-check" /><span>Nothing {sel === 3 ? "today" : "on this day"}</span></div>
      </div>
      <div className="ni-sep" />
      <div className="ni-weather">
        <div className="ni-wtop"><b>Prague</b><I n="location-arrow" /></div>
        <div className="ni-wmid"><span className="ni-temp">20°</span><I n="sun" className="ni-sun" /></div>
        <div className="ni-wbot"><b>Clear</b><span>H:20° L:6°</span></div>
      </div>
    </div>
  );
}

function Tray() {
  const files = [["file-image", "preview.png", "#c9c9cf"], ["file-arrow-down", "NotchIsland-1.0.dmg", "#c9c9cf"], ["file-word", "README.md", "#2b7cd3"], ["file-image", "NotchIsland-icon.png", "#c9c9cf"]];
  return <div className="ni-tray"><button className="ni-trayclear" title="Clear"><I n="trash-can" /></button>{files.map(([ic, n, c]) => <div key={n} className="ni-file"><I n={ic} style={{ color: c }} /><span>{n}</span></div>)}</div>;
}

function Transit() {
  const [mode, setMode] = useState("stop"); const [stop, setStop] = useState("Anděl");
  const favs = ["Anděl", "Hlavní nádraží", "Karlovo náměstí"];
  const rows = [["FlixBus", "#8ad326", "14:35", "17:10", "2:35 h", "Praha (ÚAN Florenc) → Brno (aut. nádr. Hotel Grand)", "", "279"], ["RegioJet", "#ffd21f", "15:00", "17:30", "2:30 h", "Prague – ÚAN Florenc → Brno – bus station Grand", "7 seats", "329"], ["RegioJet", "#ffd21f", "15:00", "17:25", "2:25 h", "Praha hl. n. → Brno hl. n.", "2 seats", "529"]];
  // PID: [mode, line, headsign, scheduled, platform, delay, minutes]
  const PID = { tram: ["#9A2B2B", "train-tram"], metro: ["#1F6E43", "train-subway"], bus: ["#1D5FB8", "bus"] };
  const deps = [["tram", "9", "Spořilov", "14:03", "A", 0, 0], ["tram", "12", "Sídliště Barrandov", "14:05", "B", 2, 2], ["metro", "B", "Černý Most", "14:06", "", 0, 3], ["tram", "20", "Divoká Šárka", "14:08", "A", 0, 5], ["bus", "137", "U Waltrovky", "14:09", "C", 1, 6], ["tram", "15", "Kotlářka", "14:11", "B", 0, 8]];
  return (
    <div className="ni-transit">
      <div className="ni-tside"><button className={mode === "stop" ? "on" : ""} onClick={() => setMode("stop")}><I n="bus-simple" /> Stop</button><button className={mode === "routes" ? "on" : ""} onClick={() => setMode("routes")}><I n="bus" /> Routes</button><small>{mode === "stop" ? "PID · live" : "RegioJet · FlixBus"}</small></div>
      <div className="ni-tmain">
        {mode === "routes" ? <>
          <div className="ni-trow"><input defaultValue="Prague" /><button className="ni-ic"><I n="right-left" /></button><input defaultValue="Brno" /><button className="ni-ic"><I n="star" style={{ color: "#ffd21f" }} /></button><button className="ni-search"><I n="magnifying-glass" /></button><button className="ni-idos">ČD · IDOS</button></div>
          <div className="ni-list">{rows.map((r, i) => <div key={i} className="ni-route"><span className="ni-brand" style={{ background: r[1] }}><I n="bus" /> {r[0]}</span><div className="ni-rt"><div><b>{r[2]}</b> <I n="arrow-right" className="ni-arr" /> <b>{r[3]}</b> <small>{r[4]}</small></div><span>{r[5]}</span></div><div className="ni-rr">{r[6] && <small>{r[6]}</small>}<b>{r[7]} CZK</b><I n="cart-shopping" /><I n="location-arrow" /></div></div>)}</div>
        </> : <>
          <div className="ni-stopfield"><I n="magnifying-glass" /><input value={stop} onChange={e => setStop(e.target.value)} placeholder="Stop (Anděl, Hlavní nádraží…)" /><I n="star" style={{ color: "#ffd21f" }} /></div>
          <div className="ni-favs">{favs.map(f => <button key={f} className={f === stop ? "on" : ""} onClick={() => setStop(f)}>{f}</button>)}</div>
          <div className="ni-list ni-deps">{deps.map((d, i) => <div key={i} className="ni-dep"><span className="ni-line" style={{ background: PID[d[0]][0] }}><I n={PID[d[0]][1]} /> {d[1]}</span><div className="ni-dt"><b>{d[2]}</b><span>{d[3]}{d[4] && <> &nbsp; plat. {d[4]}</>}</span></div>{d[5] > 0 ? <em className="ni-late">+{d[5]}′</em> : <em className="ni-ontime">on time</em>}<b className="ni-min">{d[6] === 0 ? "now" : d[6] + " min"}</b><I n="location-arrow" className="ni-track" /></div>)}</div>
        </>}
      </div>
    </div>
  );
}
const Calls = () => <div className="ni-calls"><div className="ni-tile ni-call"><I n="microphone-slash" className="ni-dim" /><b>No call</b><span className="ni-chip"><I n="chrome" brand /> Chrome (Meet)</span></div><div className="ni-tile ni-discord"><div className="ni-dhead"><I n="discord" brand style={{ color: "#5865f2" }} /><b>Discord</b></div><span>Enter Discord Client ID in Settings</span></div></div>;
const Shot = () => <div className="ni-shot"><div className="ni-shotbtns"><button><I n="crop-simple" /> Area <small>⌘⇧2</small></button><button><I n="display" /> Screen <small>⌘⇧1</small></button><button><I n="font" /> Text (OCR) <small>⌘⇧O</small></button></div><div className="ni-empty"><I n="camera" /><span>No screenshots yet</span></div></div>;
function Notes() { const [t, setT] = useState("Groceries: milk, bread, coffee\nCall Jake about the weekend\nMath test on Thursday – chapters 3 and 4\nIdea: show train departures in the notch"); return <div className="ni-notes"><textarea value={t} onChange={e => setT(e.target.value)} spellCheck={false} /><div className="ni-nicons"><button><I n="copy" /></button><button onClick={() => setT("")}><I n="trash-can" /></button></div></div>; }
function Clipboard() {
  const [q, setQ] = useState("");
  const items = [["https://github.com/Brozovec/NotchIsland", "3 min, 55 secs", true], ["Meet at 5:30 pm at Anděl", "10 min, 55 secs"], ["swift build -c release", "26 min, 55 secs"], ["Prague → Brno 15:00 (RJ 1013)", "1 hr, 11 min"]];
  return <div className="ni-clip"><div className="ni-csearch"><I n="magnifying-glass" /><input placeholder="Search clipboard…" value={q} onChange={e => setQ(e.target.value)} /><small>⌘⇧V</small><I n="trash-can" /></div>{items.filter(i => i[0].toLowerCase().includes(q.toLowerCase())).map((i, k) => <div key={k} className="ni-crow"><I n="align-left" className="ni-dim" /><span>{i[0]}</span><small>{i[1]}</small>{i[2] && <I n="thumbtack" style={{ color: "#ffd21f" }} />}</div>)}</div>;
}
function Timer() {
  const [total, setTotal] = useState(25 * 60); const [left, setLeft] = useState(24 * 60 + 56); const [run, setRun] = useState(true); const [pomo, setPomo] = useState(true);
  useEffect(() => { if (!run) return; const t = setInterval(() => setLeft(x => x > 0 ? x - 1 : 0), 1000); return () => clearInterval(t); }, [run]);
  const mm = String(Math.floor(left / 60)).padStart(2, "0"), ss = String(left % 60).padStart(2, "0"); const pct = total ? (left / total) * 360 : 0;
  const start = m => { setTotal(m * 60); setLeft(m * 60); setRun(true); setPomo(false); };
  return <div className="ni-timer"><div className="ni-ring" style={{ background: `conic-gradient(#ff8a1f ${pct}deg, #2a2a2e 0)` }}><div><b>{mm}:{ss}</b><span>{pomo ? "work 1" : "timer"}</span></div></div>
    <div className="ni-tctl"><div className="ni-presets">{[5, 10, 15, 25, 45, 60].map(m => <button key={m} onClick={() => start(m)}>{m}</button>)}<button className={"ni-pomo" + (pomo ? " on" : "")} onClick={() => { setTotal(1500); setLeft(1500); setRun(true); setPomo(true); }}><I n="leaf" /> Pomodoro</button></div>
      <div className="ni-tbtns"><input placeholder="min" /><button onClick={() => setRun(!run)}><I n={run ? "pause" : "play"} /></button><button onClick={() => { setTotal(t => t + 300); setLeft(l => l + 300); }}><I n="plus" /></button><button onClick={() => { setRun(false); setLeft(0); }}><I n="stop" /></button></div>
      <small>Countdown runs beside the camera, click = pause. Pomodoro 25/5, 15 min after 4 rounds.</small></div></div>;
}
function Timetable() {
  const [week, setWeek] = useState(false); const [hov, setHov] = useState(null);
  const hours = [["0", "7:10", "7:55"], ["1", "8:00", "8:45"], ["2", "8:50", "9:35"], ["3", "9:45", "10:30"], ["4", "10:50", "11:35"], ["5", "11:40", "12:25"], ["6", "12:35", "13:20"], ["7", "13:25", "14:10"], ["8", "14:20", "15:05"], ["9", "15:10", "15:55"]];
  // [hour, subject, room, teacher, state(now|cancel|change|null), full name]
  const les = { 1: ["MAT", "A204", "Nov", null, "Matematika"], 2: ["ČJL", "A204", "Svo", null, "Český jazyk a literatura"], 3: ["PRG", "B17", "Kra", "now", "Programování"], 4: ["PRG", "B17", "Kra", null, "Programování"], 5: ["ANJ", "C3", "Hol", "change", "Anglický jazyk"], 6: ["TEV", "TV", "Bar", "cancel", "Tělesná výchova"], 7: ["DOP", "A110", "Pet", null, "Dopravní technika"] };
  const days = ["Mon", "Tue", "Wed", "Thu", "Fri"]; const wk = [["MAT", "ČJL", "PRG", "PRG", "ANJ", "TEV", "DOP"], ["ANJ", "MAT", "ELT", "ELT", "ČJL", "FYZ", null], ["PRG", "PRG", "MAT", "DOP", "DOP", "ANJ", "TEV"], ["ČJL", "FYZ", "MAT", "ELT", "PRG", "PRG", null], ["DOP", "ANJ", "ČJL", "MAT", "TEV", null, null]];
  const h = hov != null ? les[hov] : null;
  return <div className="ni-tt">
    <div className="ni-tthead"><div className="ni-seg"><button className={!week ? "on" : ""} onClick={() => setWeek(false)}>Today</button><button className={week ? "on" : ""} onClick={() => setWeek(true)}>Week</button></div><I n="chevron-left" className="ni-chev" /><b>{week ? "Week 12. 10." : "Friday 16. 10."}</b><I n="chevron-right" className="ni-chev" /><span className="ni-cls">2.B</span><I n="rotate-right" className="ni-chev" /></div>
    {week ? <div className="ni-wgrid"><div className="ni-wrow ni-whead"><span /> {hours.slice(1, 8).map(x => <span key={x[0]}>{x[0]}</span>)}</div>{days.map((d, i) => <div key={d} className="ni-wrow"><span className={i === 4 ? "on" : ""}>{d}</span>{wk[i].map((s, k) => <div key={k} className={"ni-wcell" + (s ? "" : " free")}>{s && <><b>{s}</b><small>{les[k + 1]?.[1] ?? "A204"}</small></>}</div>)}</div>)}</div> : <>
      {h ? <div className="ni-state"><em>{hov}. {hours[hov][1]}–{hours[hov][2]}</em><b>{h[4]}</b><span>·</span><span>{h[2]} · {h[1]}</span>{h[3] === "cancel" && <i className="ni-warn">Cancelled</i>}{h[3] === "change" && <i className="ni-chg">Room change: C3</i>}</div>
        : <div className="ni-state"><I n="book" style={{ color: "#3fe36f" }} /><span>Now: PRG (B17) · ends in 23 min</span></div>}
      <div className="ni-cards">{hours.map(([n, b]) => { const l = les[n]; return l ? <div key={n} className={"ni-lcard " + (l[3] || "")} onMouseEnter={() => setHov(n)} onMouseLeave={() => setHov(null)}><small>{n}</small><b>{l[0]}</b>{l[3] === "cancel" ? <em>Cancelled</em> : <span className={l[3] === "change" ? "chg" : ""}>{l[1]}</span>}<small className="t">{l[2]}</small><small>{b}</small>{l[3] === "cancel" && <i className="ni-bdg red">×</i>}{l[3] === "change" && <i className="ni-bdg org">!</i>}</div> : <div key={n} className="ni-ecard"><small>{n}</small><small className="b">{b}</small></div>; })}</div>
    </>}
  </div>;
}
function Island() {
  const [open, setOpen] = useState(false); const [tab, setTab] = useState("home"); const [playing, setPlaying] = useState(true);
  const closeT = useRef(null); const user = useRef(false);
  const expandedH = tab === "timetable" ? 250 : 152;
  const w = open ? 900 : playing ? 300 : 200, h = open ? expandedH : 36;
  const enter = () => { clearTimeout(closeT.current); setOpen(true); }; const leave = () => { closeT.current = setTimeout(() => setOpen(false), 350); };
  useEffect(() => { // API pro tlačítka pod ukázkou + automatická prohlídka, dokud se uživatel nedotkne
    window.NotchIslandDemo = { open: t => { user.current = true; clearTimeout(closeT.current); setOpen(true); setTab(t); }, close: () => setOpen(false), onTab: null };
    const order = TABS.map(t => t[0]); let i = 0; const tm = setTimeout(() => { if (user.current) return; setOpen(true); const iv = setInterval(() => { if (user.current) { clearInterval(iv); return; } i = (i + 1) % order.length; setTab(order[i]); }, 2800); }, 1200);
    return () => clearTimeout(tm);
  }, []);
  useEffect(() => { window.NotchIslandDemo?.onTab?.(tab); }, [tab]);
  const body = { home: <Home playing={playing} setPlaying={setPlaying} />, tray: <Tray />, transit: <Transit />, calls: <Calls />, shot: <Shot />, notes: <Notes />, clipboard: <Clipboard />, timer: <Timer />, timetable: <Timetable /> }[tab];
  return (
    <div className="ni-hover" onMouseEnter={() => { user.current = true; enter(); }} onMouseLeave={leave} onClick={() => { user.current = true; enter(); }}>
      <div className={"ni-island" + (open ? " open" : "")} style={{ width: w, height: h }}>
        <div className={"ni-compact" + (open ? " hide" : "")}>{playing && <><div className="ni-cart"><img src={ART} alt="" /></div><Equalizer active={playing} /></>}</div>
        <div className={"ni-expanded" + (open ? " show" : "")}>
          <div className="ni-tabs">{TABS.map(([id, ic, label]) => <button key={id} className={id === tab ? "on" : ""} onClick={e => { e.stopPropagation(); user.current = true; setTab(id); }}><I n={ic} />{id === tab && <span>{label}</span>}</button>)}<button className="ni-gear"><I n="gear" /></button></div>
          <div className="ni-body">{body}</div>
        </div>
      </div>
    </div>
  );
}

const el = document.getElementById("island-root"); if (el) createRoot(el).render(<Island />);
