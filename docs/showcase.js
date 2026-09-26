// Ukázka: rozbalování notche, přepínání záložek, "ruka" kurzoru, auto-cyklus dokud se uživatel nedotkne.
(function(){
  const island=document.getElementById('island'); if(!island) return;
  const tabs=[...island.querySelectorAll('.tabs button[data-tab]')];
  const panes=[...island.querySelectorAll('.pane')];
  const cursor=document.getElementById('cursor');
  let user=false, idx=0, timer;
  function show(name){
    tabs.forEach(b=>b.classList.toggle('on',b.dataset.tab===name));
    panes.forEach(p=>p.classList.toggle('on',p.dataset.pane===name));
    island.classList.toggle('tall',name==='rozvrh');
  }
  function open(){island.classList.add('open');island.classList.remove('compact');}
  function close(){island.classList.remove('open');island.classList.add('compact');}
  tabs.forEach(b=>b.addEventListener('click',()=>{user=true;clearInterval(timer);show(b.dataset.tab);}));
  island.addEventListener('mouseenter',()=>{user=true;clearInterval(timer);open();if(cursor)cursor.style.display='none';});
  island.addEventListener('mouseleave',()=>{setTimeout(()=>{if(!island.matches(':hover'))close();},400);});
  // auto demo
  const order=['island','doprava','rozvrh','shot','schranka','casovac'];
  function step(){
    if(user) return;
    const name=order[idx%order.length]; idx++;
    if(idx===1){open();}
    show(name);
    const btn=tabs.find(b=>b.dataset.tab===name);
    if(cursor&&btn){const r=btn.getBoundingClientRect(), m=island.closest('.mac').getBoundingClientRect(); cursor.style.left=(r.left-m.left+r.width/2)+'px'; cursor.style.top=(r.top-m.top+r.height/2)+'px';}
  }
  island.classList.add('compact');
  setTimeout(()=>{if(cursor){cursor.style.left='50%';cursor.style.top='14px';} setTimeout(()=>{if(!user){open();step();timer=setInterval(step,3200);}},900);},600);
})();
