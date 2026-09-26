// Ukázka z reálných snímků: hover/tap rozbalí, tlačítka přepínají záložky, auto-cyklus dokud se uživatel nedotkne.
(function(){
  const d=document.getElementById('rdemo'); if(!d) return;
  const imgs=[...d.querySelectorAll('.panel img')], btns=[...document.querySelectorAll('#rtabs button')];
  const mac=document.getElementById('demo-mac');
  let user=false, idx=0, timer, closeT;
  function show(t){imgs.forEach(i=>i.classList.toggle('on',i.dataset.tab===t));btns.forEach(b=>b.classList.toggle('on',b.dataset.tab===t));}
  function open(){d.classList.add('open');}
  function close(){d.classList.remove('open');}
  btns.forEach(b=>b.addEventListener('click',()=>{user=true;clearInterval(timer);open();show(b.dataset.tab);}));
  d.querySelector('.collapsed').addEventListener('click',()=>{user=true;clearInterval(timer);open();});
  d.addEventListener('mouseenter',()=>{user=true;clearInterval(timer);clearTimeout(closeT);open();});
  mac.addEventListener('mouseleave',()=>{closeT=setTimeout(close,500);});
  const order=imgs.map(i=>i.dataset.tab);
  function step(){ if(user) return; show(order[idx%order.length]); idx++; }
  // auto demo: po 1 s rozbalit, pak střídat záložky
  setTimeout(()=>{ if(user) return; open(); step(); timer=setInterval(step,2800); },1200);
  // na dotykových zařízeních: klepnutí mimo zavře
  document.addEventListener('click',e=>{ if(d.classList.contains('open') && !mac.contains(e.target) && !e.target.closest('#rtabs')) close(); });
})();
