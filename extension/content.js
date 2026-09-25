// NotchIsland Media Bridge – content script. Reads navigator.mediaSession + <video>/<audio> and reports to the background worker.
(() => {
  const site = location.hostname.includes("music.youtube") ? "YouTube Music"
    : location.hostname.includes("youtube") ? "YouTube"
    : location.hostname.includes("spotify") ? "Spotify Web"
    : location.hostname.includes("soundcloud") ? "SoundCloud"
    : location.hostname.includes("deezer") ? "Deezer"
    : location.hostname.includes("twitch") ? "Twitch" : location.hostname;

  const media = () => [...document.querySelectorAll("video, audio")].find(m => !m.paused && m.readyState > 2) || document.querySelector("video, audio");

  function state() {
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    const m = media();
    let title = md && md.title || "", artist = md && md.artist || "", album = md && md.album || "";
    let artwork = md && md.artwork && md.artwork.length ? md.artwork[md.artwork.length - 1].src : null;
    if (!title && site === "YouTube") {
      title = (document.querySelector("h1.ytd-watch-metadata yt-formatted-string, h1.title") || {}).textContent || "";
      artist = (document.querySelector("#owner #channel-name a, ytd-channel-name a") || {}).textContent || "";
    }
    if (!title && site === "Spotify Web") {
      title = (document.querySelector('[data-testid="context-item-info-title"]') || {}).textContent || "";
      artist = (document.querySelector('[data-testid="context-item-info-subtitles"]') || {}).textContent || "";
      const img = document.querySelector('[data-testid="now-playing-widget"] img'); if (img) artwork = img.src;
    }
    const playing = m ? !m.paused && !m.ended : (navigator.mediaSession && navigator.mediaSession.playbackState === "playing");
    return { site, title: title.trim(), artist: artist.trim(), album: album.trim(), artwork,
             playing: !!playing, duration: m && isFinite(m.duration) ? m.duration : 0, position: m ? m.currentTime : 0 };
  }

  function run(cmd) {
    const m = media();
    const click = sel => { const b = document.querySelector(sel); if (b) { b.click(); return true; } return false; };
    switch (cmd) {
      case "playpause":
        if (site === "Spotify Web" && click('[data-testid="control-button-playpause"]')) return;
        if (m) { m.paused ? m.play() : m.pause(); } break;
      case "next":
        if (click('[data-testid="control-button-skip-forward"]') || click(".ytp-next-button") || click('.next-button, [aria-label="Next"]')) return;
        if (m) m.currentTime = m.duration; break;
      case "prev":
        if (click('[data-testid="control-button-skip-back"]') || click(".ytp-prev-button") || click('.previous-button, [aria-label="Previous"]')) return;
        if (m) m.currentTime = 0; break;
    }
  }

  chrome.runtime.onMessage.addListener((msg, _s, reply) => {
    if (msg.type === "state") reply(state());
    if (msg.type === "command") { run(msg.cmd); reply(true); }
  });
})();
