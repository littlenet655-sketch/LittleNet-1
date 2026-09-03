(()=>{
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>[...r.querySelectorAll(s)];
  const csrf=()=>$('meta[name="csrf-token"]')?.content||'';

  async function postForm(url,data={}){
    const body=new URLSearchParams(data);
    const r=await fetch(url,{method:'POST',headers:{'X-CSRFToken':csrf(),'Content-Type':'application/x-www-form-urlencoded'},body});
    let j={};try{j=await r.json();}catch{}
    return {ok:r.ok,data:j,status:r.status};
  }
  const escapeHtml=v=>{const d=document.createElement('div');d.textContent=String(v??'');return d.innerHTML;};
  function showToast(message){
    const stack=document.querySelector('.toast-stack');if(!stack)return;
    const el=document.createElement('div');el.className='ln-toast';el.textContent=message;stack.appendChild(el);
    requestAnimationFrame(()=>el.classList.add('show'));setTimeout(()=>{el.classList.remove('show');setTimeout(()=>el.remove(),220);},1800);
  }

  $$('[data-language-select]').forEach(sel=>sel.addEventListener('change',()=>sel.form?.submit()));
  $$('[data-review-toggle]').forEach(btn=>btn.addEventListener('click',()=>{
    const panel=btn.closest('[data-review-card]')?.querySelector('[data-review-preview]');if(!panel)return;
    const revealed=panel.classList.toggle('revealed');panel.classList.toggle('blurred',!revealed);btn.setAttribute('aria-expanded',revealed?'true':'false');
    btn.innerHTML=revealed?'Hide flagged media':'Show flagged media';
  }));

  $$('img[data-hide-error]').forEach(img=>{
    const hide=()=>{img.style.visibility='hidden';};
    img.addEventListener('error',hide);
    if(img.complete && !img.naturalWidth)hide();
  });

  function bindLike(root=document){
    $$('[data-like]',root).forEach(b=>{
      if(b.dataset.bound)return;b.dataset.bound='1';
      b.onclick=async()=>{const r=await postForm(`/like/${b.dataset.like}/`);if(r.ok){b.classList.toggle('liked',!!r.data.liked);b.setAttribute('aria-pressed',r.data.liked?'true':'false');const count=document.querySelector(`[data-like-count=\"${b.dataset.like}\"]`);if(count&&Number.isFinite(Number(r.data.likes)))count.textContent=String(r.data.likes);if(r.data.liked)showToast('Liked! 💛');}};
    });
  }

  function bindFollow(root=document){
    $$('[data-follow]',root).forEach(b=>{
      if(b.dataset.bound)return;b.dataset.bound='1';
      b.onclick=async()=>{const r=await postForm(`/follow/${b.dataset.follow}/`);if(r.ok)b.textContent=r.data.status==='pending'?'Requested':r.data.status==='removed'?'Follow':'Follow';};
    });
  }

  async function share(postId){
    let friends=[];
    try{const r=await fetch('/api/following/',{cache:'no-store'});if(r.ok)friends=await r.json();}catch{}
    if(!friends.length){alert('No approved connections available to share with.');return;}
    const backdrop=document.createElement('div');backdrop.className='share-sheet-backdrop';
    const box=document.createElement('div');box.className='share-sheet';
    const h=document.createElement('h3');h.textContent='Share with';box.appendChild(h);
    for(const f of friends){
      const b=document.createElement('button');b.className='share-person';b.textContent=f.full_name;
      b.onclick=async()=>{
        const r=await fetch('/api/share-post/',{method:'POST',headers:{'Content-Type':'application/json','X-CSRFToken':csrf()},body:JSON.stringify({receiver_id:f.user_id,post_id:postId})});
        if(r.ok){b.textContent='Sent ✓';setTimeout(()=>backdrop.remove(),450);}else alert('Could not share this post.');
      };
      box.appendChild(b);
    }
    const cancel=document.createElement('button');cancel.className='btn';cancel.textContent='Cancel';cancel.onclick=()=>backdrop.remove();box.appendChild(cancel);
    backdrop.appendChild(box);backdrop.onclick=e=>{if(e.target===backdrop)backdrop.remove();};document.body.appendChild(backdrop);
  }

  function bindShare(root=document){
    $$('[data-share-post]',root).forEach(b=>{if(b.dataset.bound)return;b.dataset.bound='1';b.onclick=()=>share(Number(b.dataset.sharePost));});
  }

  function bindSave(root=document){
    $$('[data-save-post]',root).forEach(b=>{
      if(b.dataset.bound)return;b.dataset.bound='1';
      b.onclick=async()=>{const r=await postForm(`/save/${b.dataset.savePost}/`);if(r.ok){b.classList.toggle('saved',!!r.data.saved);b.setAttribute('aria-pressed',r.data.saved?'true':'false');showToast(r.data.saved?'Saved for later':'Removed from saved');}};
    });
  }

  function bindReport(root=document){
    $$('[data-report-post]',root).forEach(b=>{
      if(b.dataset.bound)return;b.dataset.bound='1';
      b.onclick=async()=>{const reason=prompt('Report reason: bullying, harassment, unsafe content, spam, or other');if(!reason)return;const r=await postForm('/report/',{target_type:'POST',target_id:b.dataset.reportPost,reason});alert(r.ok?'Report sent to LittleNet safety review.':'Could not report this post.');};
    });
  }

  function bindDouble(root=document){
    $$('[data-double-like]',root).forEach(el=>{
      if(el.dataset.doubleBound)return;el.dataset.doubleBound='1';let last=0;
      el.addEventListener('pointerup',async()=>{const now=Date.now();if(now-last<320){const h=$('.heart-burst',el);h?.classList.add('show');setTimeout(()=>h?.classList.remove('show'),550);const r=await postForm(`/like/${el.dataset.doubleLike}/`);if(r.ok){const b=document.querySelector(`[data-like=\"${el.dataset.doubleLike}\"]`);if(b){b.classList.toggle('liked',!!r.data.liked);b.setAttribute('aria-pressed',r.data.liked?'true':'false');}showToast('Liked! 💛');}}last=now;});
    });
  }

  function observeVideos(root=document){
    const vids=$$('video[data-autoplay]',root);if(!('IntersectionObserver'in window))return;
    const ob=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting&&e.intersectionRatio>.65){$$('video[data-autoplay]').forEach(v=>{if(v!==e.target)v.pause();});e.target.play().catch(()=>{});}else e.target.pause();}),{threshold:[.2,.65,.9]});
    vids.forEach(v=>{if(!v.dataset.observed){v.dataset.observed='1';ob.observe(v);}});
  }

  function bindReelSound(root=document){
    $$('[data-reel-sound]',root).forEach(b=>{if(b.dataset.bound)return;b.dataset.bound='1';b.addEventListener('click',()=>{const reel=b.closest('.reel');const v=reel?.querySelector('video');if(!v)return;v.muted=!v.muted;b.classList.toggle('sound-on',!v.muted);showToast(v.muted?'Sound off':'Sound on');});});
  }
  function observeCards(root=document){
    if(!('IntersectionObserver' in window))return;
    const cards=$$('.post,.parent-card,.reel-teaser',root);
    const ob=new IntersectionObserver(entries=>entries.forEach(e=>{
      if(e.isIntersecting){e.target.classList.add('visible');ob.unobserve(e.target);}
    }),{threshold:.08});
    cards.forEach(c=>ob.observe(c));
  }
  function markActiveNav(){
    const path=location.pathname.replace(/\/$/,'');
    $$('.bottom-nav a,.parent-bottom-nav a,.parent-nav a').forEach(a=>{
      const href=(a.getAttribute('href')||'').replace(/\/$/,'');
      if(href && path===href)a.classList.add('active');
    });
  }
  bindLike();bindFollow();bindShare();bindSave();bindReport();bindDouble();bindReelSound();observeVideos();observeCards();markActiveNav();

  const storyRail=$('.stories');
  if(storyRail)storyRail.addEventListener('wheel',e=>{if(Math.abs(e.deltaY)>Math.abs(e.deltaX)){storyRail.scrollLeft+=e.deltaY;e.preventDefault();}},{passive:false});

  const reelsPage=$('.reels-page');
  if(reelsPage){
    let page=2,loading=false,done=false;
    reelsPage.addEventListener('scroll',async()=>{
      if(done||loading||reelsPage.scrollTop+reelsPage.clientHeight<reelsPage.scrollHeight-reelsPage.clientHeight*1.5)return;
      loading=true;
      try{
        const r=await fetch(`/api/reels/?page=${page}`,{cache:'no-store'});if(!r.ok){done=true;return;}
        const items=await r.json();if(!items.length){done=true;return;}
        items.forEach(x=>{
          const d=document.createElement('section');d.className='reel';d.dataset.doubleLike=x.post_id;
          d.innerHTML=`<video data-autoplay muted loop playsinline preload="metadata" src="/${escapeHtml(x.media_path)}"></video><div class="reel-overlay"></div><span class="heart-burst">♥</span><div class="reel-meta"><a href="/child/view-profile/${Number(x.child_id)}/" style="color:#fff;text-decoration:none"><b>${escapeHtml(x.full_name)}</b></a><p>${escapeHtml(x.caption)}</p><span class="safety-chip">${['Science','Math','Technology','Education','Nature','Books','Coding','General Knowledge'].includes(x.content_category)?'📚 '+escapeHtml(reelsPage.dataset.labelEducational||'Educational Reel'):escapeHtml(reelsPage.dataset.labelSafe||'Kids Safe')}</span></div><div class="reel-actions"><button data-like="${Number(x.post_id)}" aria-label="Like"><svg class="ln-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l7.8-7.5a5.5 5.5 0 0 0 1-8.9z"/></svg></button><a href="/post/${Number(x.post_id)}/" aria-label="Comments"><svg class="ln-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a8 8 0 0 1-8 8H6l-4 2 1.5-5A9 9 0 1 1 21 12z"/></svg></a><button data-share-post="${Number(x.post_id)}" aria-label="Share"><svg class="ln-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m22 2-7 20-4-9-9-4z"/><path d="M22 2 11 13"/></svg></button><button data-save-post="${Number(x.post_id)}" aria-label="Save"><svg class="ln-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1z"/></svg></button><button data-reel-sound aria-label="Sound">🔊</button><button data-report-post="${Number(x.post_id)}" aria-label="Report">•••</button></div>`;
          reelsPage.appendChild(d);bindLike(d);bindShare(d);bindSave(d);bindReport(d);bindDouble(d);bindReelSound(d);observeVideos(d);
        });page++;
      }catch{done=true;}finally{loading=false;}
    });
  }

  if(document.body.dataset.role==='CHILD')setInterval(async()=>{try{const r=await fetch('/api/usage/heartbeat/',{method:'POST',headers:{'X-CSRFToken':csrf()}});if(!r.ok)return;const j=await r.json();if(j.quiet_hours&&j.redirect){location.href=j.redirect;return;}if(j.locked){location.href='/child/dashboard/';}}catch{}},30000);

  if(document.body.dataset.role==='PARENT') {
    const badge=$('[data-parent-alert-count]');
    const alertsLink=$('[data-parent-alerts]');
    let lastLatest=0;
    const pollParentAlerts=async()=>{
      try{
        const r=await fetch('/api/parent/notifications/unread/',{cache:'no-store'});
        if(!r.ok)return;
        const j=await r.json();
        const count=Number(j.count||0);
        if(badge){badge.textContent=String(count);badge.hidden=count===0;}
        if(alertsLink)alertsLink.classList.toggle('has-unread',count>0);
        const latest=Number(j.latest?.notification_id||0);
        if(latest && lastLatest && latest>lastLatest){
          alertsLink?.classList.add('alert-pulse');
          setTimeout(()=>alertsLink?.classList.remove('alert-pulse'),1200);
        }
        if(latest)lastLatest=Math.max(lastLatest,latest);
      }catch{}
    };
    pollParentAlerts();
    setInterval(pollParentAlerts,10000);
  }

  const upload=$('form[data-safe-upload]');
  if(upload){
    const status=$('#uploadStatus'),kind=upload.querySelector('[data-kind]'),music=upload.querySelector('[data-story-music]');
    const sync=()=>{if(music)music.style.display=kind?.value==='story'?'block':'none';};kind?.addEventListener('change',sync);sync();
    upload.addEventListener('submit',async e=>{
      e.preventDefault();const btn=upload.querySelector('button[type=submit]');if(btn)btn.disabled=true;if(status)status.textContent='Running LittleNet safety checks…';
      const data=new FormData(upload);const url=kind?.value==='story'?'/upload-story/':'/child/upload-post/';
      try{const r=await fetch(url,{method:'POST',headers:{'X-CSRFToken':csrf()},body:data});const j=await r.json();if(!r.ok){if(status)status.textContent=j.reason||j.error||'Content could not be published.';return;}if(status)status.textContent=j.status==='REVIEW'?'Sent to Parent Mode for review.':'Published safely.';setTimeout(()=>location.href=kind?.value==='reel'?'/reels/':'/child/dashboard/',550);}catch{if(status)status.textContent='Upload failed. Check the connection and try again.';}finally{if(btn)btn.disabled=false;}
    });
  }

  const photo=$('form[data-profile-photo]');
  if(photo)photo.addEventListener('submit',async e=>{e.preventDefault();const data=new FormData(photo);try{const r=await fetch(photo.action,{method:'POST',headers:{'X-CSRFToken':csrf()},body:data});const j=await r.json();if(r.ok)location.reload();else alert(j.error||'Profile photo was not allowed.');}catch{alert('Photo upload failed.');}});
})();
