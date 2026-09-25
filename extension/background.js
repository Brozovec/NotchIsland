// NotchIsland Media Bridge – service worker. Every second asks tabs for playback state, sends the active one to the app, executes returned commands.
const APP = "http://127.0.0.1:47831/nowplaying";
let lastTab = null;

async function tick() {
  const tabs = await chrome.tabs.query({ url: ["*://www.youtube.com/*", "*://music.youtube.com/*", "*://open.spotify.com/*", "*://soundcloud.com/*", "*://*.deezer.com/*", "*://www.twitch.tv/*"] });
  let best = null, bestTab = null;
  for (const t of tabs) {
    try {
      const s = await chrome.tabs.sendMessage(t.id, { type: "state" });
      if (!s || !s.title) continue;
      if (!best || (s.playing && !best.playing) || (t.id === lastTab && s.playing === best.playing)) { best = s; bestTab = t.id; }
    } catch (e) { /* content script not ready */ }
  }
  lastTab = bestTab;
  try {
    const r = await fetch(APP, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(best || {}) });
    const j = await r.json();
    if (bestTab && j.commands && j.commands.length) for (const c of j.commands) chrome.tabs.sendMessage(bestTab, { type: "command", cmd: c }).catch(() => {});
  } catch (e) { /* app not running */ }
}

chrome.alarms.create("tick", { periodInMinutes: 0.02 });   // ~1 s (alarms min in MV3 is 30 s in some versions, so also loop below)
chrome.alarms.onAlarm.addListener(tick);
(async function loop() { while (true) { await tick(); await new Promise(r => setTimeout(r, 1000)); } })();
