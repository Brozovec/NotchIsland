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
  const [mode, setMode] = useState("routes");
  const rows = [["FlixBus", "#8ad326", "14:35", "17:10", "2:35 h", "Praha (ÚAN Florenc) → Brno (aut. nádr. Hotel Grand)", "", "279 CZK"], ["RegioJet", "#ffd21f", "15:00", "17:30", "2:30 h", "Prague – ÚAN Florenc → Brno – bus station Grand", "7 seats", "329 CZK"], ["RegioJet", "#ffd21f", "15:00", "17:25", "2:25 h", "Praha hl. n. → Brno hl. n.", "2 seats", "529 CZK"]];
  const stops = [["Anděl", "9", "Spořilov", "now"], ["Anděl", "12", "Sídliště Barrandov", "2 min"], ["Anděl", "20", "Divoká Šárka", "4 min"], ["Anděl", "B", "Zličín", "5 min"]];
  return (
    <div className="ni-transit">
      <div className="ni-tside"><button className={mode === "stop" ? "on" : ""} onClick={() => setMode("stop")}><I n="bus-simple" /> Stop</button><button className={mode === "routes" ? "on" : ""} onClick={() => setMode("routes")}><I n="bus" /> Routes</button><small>RegioJet · FlixBus</small></div>
      <div className="ni-tmain">
        {mode === "routes" ? <>
          <div className="ni-trow"><input defaultValue="Prague" /><button className="ni-ic"><I n="right-left" /></button><input defaultValue="Brno" /><button className="ni-ic"><I n="star" style={{ color: "#ffd21f" }} /></button><button className="ni-search"><I n="magnifying-glass" /></button><button className="ni-idos">ČD · IDOS</button></div>
          <div className="ni-list">{rows.map((r, i) => <div key={i} className="ni-route"><span className="ni-brand" style={{ background: r[1] }}><I n="bus" /> {r[0]}</span><div className="ni-rt"><div><b>{r[2]}</b> <I n="arrow-right" className="ni-arr" /> <b>{r[3]}</b> <small>{r[4]}</small></div><span>{r[5]}</span></div><div className="ni-rr">{r[6] && <small>{r[6]}</small>}<b>{r[7]}</b><I n="cart-shopping" /><I n="location-arrow" /></div></div>)}</div>
        </> : <>
          <div className="ni-trow"><input defaultValue="Anděl" /><button className="ni-search"><I n="magnifying-glass" /></button></div>
          <div className="ni-list">{stops.map((s, i) => <div key={i} className="ni-route"><span className="ni-brand" style={{ background: s[1] === "B" ? "#ffd21f" : "#d32f2f", color: s[1] === "B" ? "#000" : "#fff" }}>{s[1] === "B" ? <I n="train-subway" /> : <I n="train-tram" />} {s[1]}</span><div className="ni-rt"><div><b>{s[2]}</b></div><span>on time</span></div><div className="ni-rr"><b>{s[3]}</b></div></div>)}</div>
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
  const hours = ["7:10", "8:00", "8:50", "9:45", "10:50", "11:40", "12:35", "13:25", "14:20"];
  const les = [["MAT", "A204"], ["ČJL", "A204"], ["PRG", "B17"], ["PRG", "B17"], ["ANJ", "C3"], ["TV", "TV"], ["TV", "TV"], null, null];
  return <div className="ni-tt"><div className="ni-tthead"><button className="on">Today</button><button>Week</button><span><I n="mug-hot" /> Break · next PRG in 4:12</span><b>Fri 16. 10.</b></div><div className="ni-ttrow">{les.map((l, i) => <div key={i} className={"ni-les" + (i === 2 ? " now" : "") + (l ? "" : " free")}><small>{hours[i]}</small>{l ? <><b>{l[0]}</b><span>{l[1]}</span></> : <span>–</span>}</div>)}</div></div>;
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
