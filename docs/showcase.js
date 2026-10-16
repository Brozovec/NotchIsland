// Ukázka: ostrůvek je React komponenta (island.js). Tlačítka pod Macem přepínají záložky, ostrůvek se škáluje podle šířky Macu.
(function(){
  const mac=document.getElementById('demo-mac'), wrap=document.getElementById('ni-wrap'); if(!mac||!wrap) return;
  const btns=[...document.querySelectorAll('#rtabs button')];
  function scale(){ const w=mac.clientWidth; wrap.style.setProperty('--s', w>900 ? (w*0.78/900).toFixed(3) : Math.min(1,(w-8)/900).toFixed(3)); }
  scale(); addEventListener('resize',scale);
  function mark(t){ btns.forEach(b=>b.classList.toggle('on',b.dataset.tab===t)); }
  btns.forEach(b=>b.addEventListener('click',()=>{ window.NotchIslandDemo?.open(b.dataset.tab); mark(b.dataset.tab); }));
  const hook=()=>{ if(window.NotchIslandDemo){ window.NotchIslandDemo.onTab=mark; } else setTimeout(hook,100); }; hook();
  document.addEventListener('click',e=>{ if(!mac.contains(e.target) && !e.target.closest('#rtabs')) window.NotchIslandDemo?.close(); });
})();
