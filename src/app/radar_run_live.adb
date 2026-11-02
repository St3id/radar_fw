with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;            use Ada.Text_IO;
with GNAT.Sockets;           use GNAT.Sockets;

with Radar_Clutter;          use Radar_Clutter;
with Radar_Detect;           use Radar_Detect;
with Radar_Geometry;         use Radar_Geometry;
with Radar_Html;             use Radar_Html;
with Radar_Http;             use Radar_Http;
with Radar_Sim_Source;       use Radar_Sim_Source;
with Radar_Source;           use Radar_Source;
with Radar_Sweep;            use Radar_Sweep;
with Radar_Track;            use Radar_Track;

--  Ce programme melange Ada et HTML/JS : lignes longues assumees.
pragma Style_Checks ("M300");

--  Mode live : surveillance temps reel servie dans le navigateur.
--
--  Un serveur HTTP minimal, ecrit en Ada pur (GNAT.Sockets), fait
--  tourner la simulation en continu (un tour de scan toutes les
--  Turn_Ms millisecondes) et sert :
--    /            la page 3D (Three.js), qui se met a jour seule ;
--    /events      le flux pousse des etats (Server-Sent Events) ;
--    /state.json  les pistes courantes (id, position, vitesse) ;
--    /cloud.json  le decor statique appris a la calibration (les murs).
--
--  Les Calibration_Turns premiers tours servent de calibration : tout
--  echo y est memorise dans la carte de clutter (Radar_Clutter) comme
--  appartenant au decor. Ensuite, seuls les echos qui s'en ecartent
--  deviennent des pistes : c'est le MTI (Moving Target Indication) d'un
--  radar de veille au sol. Un objet reste immobile pendant la
--  calibration est donc invisible jusqu'a ce qu'il bouge, comportement
--  normal et voulu d'une carte de clutter.
--
--  Architecture volontairement mono-thread : entre deux tours, le
--  serveur attend les connexions avec un selector a timeout. Pas de
--  taches ici - la concurrence Ravenscar vit dans radar_demo et, a
--  terme, sur la carte. Un vrai capteur demandera un adaptateur de son
--  format de sortie ; le LD2450 ne produit pas le Sweep simule.
procedure Radar_Run_Live is

   Port    : constant := 8080;
   --  La grille simule 120 x 7 profils, horodates a 1 ms chacun.
   --  Garder l'animation alignee sur cette base de temps evite que les
   --  vitesses affichees et la cadence murale racontent deux chronologies.
   Turn_Ms : constant := 840;

   --  Tours de calibration : le decor est appris a chaque tour jusqu'a
   --  atteindre le niveau de confirmation de la carte de clutter ; le
   --  pistage ne demarre qu'apres. 8 et non 2 depuis les murs
   --  speculaires (realisme point 9) : un mur vu de biais renvoie un echo
   --  proche du seuil CFAR, detecte un tour sur deux ou sur cinq. En
   --  2 tours, ces cases n'etaient pas apprises et le pistage les
   --  agregeait en 5 a 7 pistes fantomes des la mise en route (mesure).
   Calibration_Turns : constant := 8;

   --  Apprentissage de fond (1 tour sur N) : le decor qui apparait
   --  (meuble deplace...) finit par etre appris, mais un mobile qui ne
   --  fait que passer n'est vu qu'une fois par case : il ne devient
   --  pas du decor.
   Learn_Period : constant := 4;

   --  Oubli lent (1 vieillissement tous les N tours) : le decor qui
   --  disparait finit par etre oublie. L'equilibre se calcule : une case
   --  detectee avec la probabilite p gagne en moyenne p x N / Learn_Period
   --  crans par periode d'oubli et en perd 1. Elle n'est donc apprise que
   --  si p > Learn_Period / N. A N = 8, seules les cases vues plus d'une
   --  fois sur deux l'etaient : les echos intermittents des murs vus de
   --  biais restaient hors carte, et le mode live affichait 8 a 11 pistes
   --  fantomes. A N = 32, le seuil tombe a p > 12,5 % : 0 a 1 fantome
   --  bref (mesure sur 120 s). Revers : un meuble retire met environ
   --  30 s, au lieu de 7, a sortir de la carte.
   Age_Period : constant := 32;

   --  Source'Class : les appels sont dispatchants (voir Radar_Source).
   Src  : Source'Class := Make (Sweeps => Positive'Last, See_Room => True);
   Trk  : Tracker;
   Clut : Clutter_Map;

   Turn : Natural := 0;

   State_Json : Unbounded_String :=
     To_Unbounded_String
       ("{""turn"":0,""turn_ms"":840,""calibrating"":true,""tracks"":[]}");
   Cloud_Json : Unbounded_String :=
     To_Unbounded_String ("{""points"":[]}");

   Srv : Radar_Http.Server;

   --  ----- La page (visualiseur live) -----

   function Build_Page return Unbounded_String is
      P : Unbounded_String;
      procedure L (S : String) is
      begin
         Append (P, S);
         Append (P, ASCII.LF);
      end L;
   begin
      L ("<!DOCTYPE html><html lang='fr'><head><meta charset='UTF-8'>");
      L ("<title>radar_fw - Surveillance live</title>");
      L ("<meta name='viewport' content='width=device-width, initial-scale=1'>");
      L ("<style>");
      L ("*{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden}");
      L ("body{background:#080d0b;color:#d8e6df;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;font-size:13px}");
      L ("canvas{position:fixed;inset:0;display:block;touch-action:none}");
      L (":root{--panel:rgba(10,17,14,.94);--line:#26372f;--muted:#91a49a;--green:#49e0a2;--amber:#ffc36a}");
      L ("#topbar{position:fixed;z-index:2;inset:0 0 auto;height:62px;display:flex;align-items:center;justify-content:space-between;" &
         "padding:0 22px;background:rgba(8,13,11,.88);border-bottom:1px solid #22332b;pointer-events:none}");
      L (".brand{display:flex;align-items:center;gap:13px}.brand-mark{width:29px;height:29px;display:grid;place-items:center;border:1px solid #39775d;color:var(--green);font-size:11px;font-weight:800;letter-spacing:-1px}");
      L (".brand-name{font-size:13px;font-weight:750;letter-spacing:.13em;color:#edf7f2}.brand-sub{margin-top:2px;color:var(--muted);font-size:10px;letter-spacing:.12em;text-transform:uppercase}");
      L (".top-right{display:flex;align-items:center;gap:15px}.mode-tag,.link-state{display:flex;align-items:center;gap:8px;font-size:10px;font-weight:750;letter-spacing:.1em;text-transform:uppercase}");
      L (".mode-tag{padding:7px 10px;border:1px solid #72502b;color:#ffd08a;background:#291e12}.link-state{color:#aab9b1}" &
         ".dot{width:7px;height:7px;border-radius:50%;background:#718078}.link-state.online .dot{background:var(--green);box-shadow:0 0 10px #49e0a255}" &
         ".link-state.offline .dot{background:#f07867}");
      L ("#console{position:fixed;z-index:2;top:82px;left:20px;width:318px;max-height:calc(100vh - 112px);overflow:auto;background:var(--panel);border:1px solid var(--line);box-shadow:0 14px 44px #0007;pointer-events:auto}");
      L (".panel-head{padding:15px 16px 11px;border-bottom:1px solid #22332b;color:var(--muted);font-size:10px;font-weight:750;letter-spacing:.13em;text-transform:uppercase}");
      L (".status-row{display:flex;align-items:flex-start;gap:10px;padding:15px 16px 13px}.status-indicator{width:8px;height:8px;flex:none;margin-top:4px;background:var(--amber);box-shadow:0 0 10px #ffc36a44}.status-indicator.active{background:var(--green);box-shadow:0 0 10px #49e0a255}");
      L ("#status{font-size:14px;font-weight:700;color:#f1f6f3;line-height:1.3}.status-note{margin-top:4px;color:var(--muted);font-size:11px;line-height:1.45}");
      L (".count-row{display:flex;align-items:baseline;justify-content:space-between;padding:12px 16px;border-top:1px solid #22332b;border-bottom:1px solid #22332b}");
      L (".count-label{color:var(--muted);font-size:10px;font-weight:750;letter-spacing:.1em;text-transform:uppercase}#target-count{color:var(--green);font-size:25px;font-weight:700;font-variant-numeric:tabular-nums}");
      L (".target-list{padding:3px 16px 10px}.empty-state{padding:11px 0 13px;color:#9aaca2;font-size:12px}");
      L (".target-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 0;border-bottom:1px solid #1e2b25}.target-row:last-child{border-bottom:0}");
      L (".target-id{display:flex;align-items:center;gap:8px;color:#e4eee8;font-weight:700;font-variant-numeric:tabular-nums}");
      L (".target-mark{width:7px;height:7px;background:var(--green);border-radius:50%}.target-row.coasting .target-mark{background:#929a96}");
      L (".target-data{display:flex;align-items:center;gap:9px;color:#d9e5de;font-size:11px;font-variant-numeric:tabular-nums;white-space:nowrap}");
      L (".target-speed{color:var(--amber)}.track-state{color:#91a49a;font-size:9px;letter-spacing:.06em;text-transform:uppercase}");
      L (".target-row{width:100%;background:transparent;color:inherit;font:inherit;text-align:left;cursor:pointer}");
      L (".target-row:hover,.target-row.selected{background:#17251e}.display-options{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:10px 16px;border-top:1px solid #22332b;color:#c4d2ca;font-size:10px}");
      L (".display-options label{display:flex;align-items:center;gap:6px;cursor:pointer}.display-options input{accent-color:var(--green)}");
      L (".view-reset{grid-column:1/-1;padding:7px 9px;border:1px solid #45564d;background:#131e18;color:#e5eee9;font:inherit;cursor:pointer}.view-reset:hover{border-color:var(--green)}");
      L ("#legend{position:fixed;z-index:2;left:20px;bottom:20px;display:flex;flex-wrap:wrap;gap:10px 15px;max-width:430px;padding:11px 13px;background:var(--panel);border:1px solid var(--line);color:#c4d2ca;font-size:10px;pointer-events:none}");
      L (".legend-item{display:flex;align-items:center;gap:7px;white-space:nowrap}.legend-dot{width:7px;height:7px;border-radius:50%;background:#1f7a5a}" &
         ".legend-target{background:var(--green)}.legend-sensor{background:#ff7657}.legend-coast{background:#929a96}" &
         ".legend-arrow{width:15px;height:2px;background:var(--amber);position:relative}.legend-arrow:after{content:'';position:absolute;right:-1px;top:-3px;border-left:5px solid var(--amber);border-top:4px solid transparent;border-bottom:4px solid transparent}");
      L ("#controls{position:fixed;z-index:2;right:20px;bottom:20px;max-width:350px;padding:11px 13px;background:var(--panel);border:1px solid var(--line);color:#c4d2ca;font-size:10px;line-height:1.8;pointer-events:none}");
      L (".control-title{margin-bottom:3px;color:var(--muted);font-size:9px;font-weight:750;letter-spacing:.12em;text-transform:uppercase}.key{display:inline-block;min-width:19px;margin-right:2px;padding:0 4px;border:1px solid #45564d;color:#e5eee9;text-align:center;line-height:17px}");
      L ("@media(max-width:700px){#topbar{height:54px;padding:0 13px}.brand-mark{width:25px;height:25px}.brand-name{font-size:11px}.brand-sub{font-size:9px}" &
         ".top-right{gap:8px}.mode-tag,.link-state{font-size:9px;padding:6px 7px}#console{top:66px;left:10px;width:min(310px,calc(100vw - 20px));max-height:calc(100vh - 155px)}" &
         ".panel-head{padding:11px 13px 8px}.status-row{padding:11px 13px}.count-row{padding:8px 13px}#target-count{font-size:21px}.target-list{padding:2px 13px 7px}.target-row{padding:8px 0}" &
         "#legend{left:10px;right:10px;bottom:10px;max-width:none;gap:7px 11px;padding:9px 10px;font-size:9px}#controls{display:none}}");
      L ("@media(max-width:390px){.brand-sub{display:none}.mode-tag{font-size:8px}.target-data{gap:6px;font-size:10px}#legend{gap:6px 9px}.legend-item{font-size:8px}}");
      L ("@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important}}</style></head><body>");
      L ("<header id='topbar'><div class='brand'><div class='brand-mark'>RF</div><div><div class='brand-name'>RADAR_FW</div><div class='brand-sub'>Console de surveillance</div></div></div>");
      L ("<div class='top-right'><div class='mode-tag'>LIVE &middot; SIMULATION</div><div id='link-state' class='link-state'><span class='dot'></span><span id='link-label'>Connexion...</span></div></div></header>");
      L ("<main id='console' aria-label='Etat de la surveillance'>");
      L ("<div class='panel-head'>Etat du radar</div><div class='status-row'><span id='status-indicator' class='status-indicator'></span>" &
         "<div><div id='status' aria-live='polite'>Connexion en cours...</div><div id='status-note' class='status-note'>Reception du premier etat de simulation.</div></div></div>");
      L ("<div class='count-row'><span class='count-label'>Pistes confirmees</span><strong id='target-count'>0</strong></div>");
      L ("<div id='tgts' class='target-list' role='list'><div id='empty-state' class='empty-state'>En attente de pistes confirmees.</div></div>");
      L ("<div class='display-options' aria-label='Options visuelles'>");
      L ("<label><input id='show-cloud' type='checkbox' checked> Decor</label><label><input id='show-vectors' type='checkbox' checked> Vecteurs</label>");
      L ("<label><input id='show-trails' type='checkbox' checked> Trainees</label><label><input id='show-labels' type='checkbox'> Etiquettes 3D</label>");
      L ("<button id='reset-view' class='view-reset' type='button'>Recentrer la vue</button></div></main>");
      L ("<aside id='legend' aria-label='Legende de la scene 3D'>");
      L ("<span class='legend-item'><i class='legend-dot legend-sensor'></i>Capteur</span><span class='legend-item'><i class='legend-dot'></i>Decor appris</span>");
      L ("<span class='legend-item'><i class='legend-dot legend-target'></i>Cible confirmee</span>" &
         "<span class='legend-item'><i class='legend-arrow'></i>Vitesse</span>" &
         "<span class='legend-item'><i class='legend-dot legend-coast'></i>Piste extrapolee</span></aside>");
      L ("<aside id='controls' aria-label='Commandes de camera'><div class='control-title'>Navigation 3D</div>");
      L ("Glisser : orbiter &middot; Molette : zoom<br><span class='key'>Z</span><span class='key'>Q</span>" &
         "<span class='key'>S</span><span class='key'>D</span> / <span class='key'>W</span><span class='key'>A</span>" &
         "<span class='key'>S</span><span class='key'>D</span> : deplacer<br><span class='key'>R</span>" &
         " / <span class='key'>F</span> : monter / descendre</aside>");
      L ("<script src='https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'></script>");
      L ("<script>");
      L ("const scene=new THREE.Scene();");
      L ("const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,100000);");
      L ("const rnd=new THREE.WebGLRenderer({antialias:true});");
      L ("rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
      L ("document.body.appendChild(rnd.domElement);");
      L ("scene.add(new THREE.GridHelper(8000,16,0x1c3a2e,0x1c3a2e));");
      L ("scene.add(new THREE.Mesh(new THREE.SphereGeometry(90,16,16),new THREE.MeshBasicMaterial({color:0xff5d3b})));");
      --  Decor statique : charge une fois (il ne change pas).
      L (" let cloudObject=null;fetch('/cloud.json').then(r=>r.json()).then(c=>{");
      L (" const g=new THREE.BufferGeometry(),pos=[];");
      L (" c.points.forEach(p=>pos.push(p[0],p[2],p[1]));");
      L (" g.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
      L (" cloudObject=new THREE.Points(g,new THREE.PointsMaterial({color:0x1f7a5a,size:35}));scene.add(cloudObject);");
      L (" cloudObject.visible=showCloud.checked;});");
      L ("const dyn=new THREE.Group();scene.add(dyn);");
      L ("function v3(p){return new THREE.Vector3(p.x,p.z,p.y);}");
      --  Une reserve d'objets PAR PISTE, reutilises d'un etat a l'autre.
      --  La version precedente detruisait et recreait tout a chaque etat :
      --  sphere, fleche, trainee, et surtout un canvas et une texture
      --  d'etiquette neufs. Sans enjeu a un etat par seconde ; a 10 Hz avec
      --  plusieurs pistes, des centaines d'allocations par seconde, que le
      --  ramasse-miettes du navigateur paie en a-coups. Ici, geometrie et
      --  materiaux sont partages, l'etiquette n'est redessinee que si son
      --  texte change, et la trainee vit dans un tampon de 11 points.
      --  Purement de l'affichage : aucune decision n'est prise (R1).
      L ("const BALL=new THREE.SphereGeometry(70,16,16);");
      L ("const M_ON=new THREE.MeshBasicMaterial({color:0x34e29b}),M_COAST=new THREE.MeshBasicMaterial({color:0x777777}),M_SELECTED=new THREE.MeshBasicMaterial({color:0xffd23b});");
      L ("const M_TRAIL=new THREE.LineBasicMaterial({color:0x1f7a5a});");
      L ("const pool={};");
      L ("function objFor(id){");
      L (" let o=pool[id];if(o)return o;");
      L (" const c=document.createElement('canvas');c.width=256;c.height=64;");
      L (" const tex=new THREE.CanvasTexture(c);");
      L (" const lab=new THREE.Sprite(new THREE.SpriteMaterial({map:tex,depthTest:false}));lab.scale.set(1100,275,1);");
      L (" const tg=new THREE.BufferGeometry();tg.setAttribute('position',new THREE.BufferAttribute(new Float32Array(33),3));");
      L (" o={ball:new THREE.Mesh(BALL,M_ON),arrow:new THREE.ArrowHelper(new THREE.Vector3(1,0,0),new THREE.Vector3(),1,0xffd23b),");
      L ("    lab:lab,g:c.getContext('2d'),tex:tex,text:'',trail:new THREE.Line(tg,M_TRAIL)};");
      L (" o.trail.frustumCulled=false;dyn.add(o.ball,o.arrow,o.lab,o.trail);pool[id]=o;return o;}");
      L ("function setLabel(o,t){");
      L (" if(o.text===t)return;o.text=t;");
      L (" o.g.clearRect(0,0,256,64);o.g.font='26px monospace';o.g.fillStyle='#d8f5e8';o.g.textAlign='center';o.g.fillText(t,128,40);");
      L (" o.tex.needsUpdate=true;}");
      L ("function drop(id){");
      L (" const o=pool[id];dyn.remove(o.ball,o.arrow,o.lab,o.trail);");
      L (" o.lab.material.dispose();o.tex.dispose();o.trail.geometry.dispose();");
      L (" o.arrow.line.material.dispose();o.arrow.cone.material.dispose();delete pool[id];}");
      --  Etat courant + trainees cote client (id -> dernieres positions).
      L ("const statusEl=document.getElementById('status'),statusNote=document.getElementById('status-note');");
      L ("const statusIndicator=document.getElementById('status-indicator'),linkState=document.getElementById('link-state');");
      L ("const linkLabel=document.getElementById('link-label'),tgts=document.getElementById('tgts');");
      L ("const emptyState=document.getElementById('empty-state'),targetCount=document.getElementById('target-count');");
      L ("const showCloud=document.getElementById('show-cloud'),showVectors=document.getElementById('show-vectors');");
      L ("const showTrails=document.getElementById('show-trails'),showLabels=document.getElementById('show-labels');");
      L ("let lastTurn=-1,selectedId=null;const trails={};");
      L ("showCloud.addEventListener('change',()=>{if(cloudObject)cloudObject.visible=showCloud.checked;});");
      L ("showVectors.addEventListener('change',()=>{for(const id in pool)pool[id].arrow.visible=showVectors.checked&&pool[id].hasVelocity;});");
      L ("showTrails.addEventListener('change',()=>{for(const id in pool)pool[id].trail.visible=showTrails.checked&&pool[id].hasTrail;});");
      L ("showLabels.addEventListener('change',()=>{for(const id in pool)pool[id].lab.visible=showLabels.checked&&Number(id)===selectedId;});");
      L ("function draw(s){");
      L (" const list=document.createDocumentFragment(),seen={};");
      L (" for(const tk of s.tracks){");
      L ("  const o=objFor(tk.id);seen[tk.id]=1;");
      L ("  const p=v3(tk);");
      L ("  o.ball.position.copy(p);o.ball.material=tk.id===selectedId?M_SELECTED:(tk.coast?M_COAST:M_ON);");
      L ("  const vel=new THREE.Vector3(tk.vx,tk.vz,tk.vy),sp=vel.length();");
      L ("  if(sp>1){const len=Math.min(2500,sp*5);o.arrow.position.copy(p);o.arrow.setDirection(vel.normalize());o.arrow.setLength(len,len*0.3,len*0.2);o.hasVelocity=true;}else{o.hasVelocity=false;}o.arrow.visible=showVectors.checked&&o.hasVelocity;");
      L ("  const d=Math.round(Math.sqrt(tk.x*tk.x+tk.y*tk.y+tk.z*tk.z));");
      --  Les vitesses arrivent en mm/s : la page divise par 1000 pour
      --  afficher des m/s, et rien de plus. Avant la base de temps elle
      --  devait connaitre TURN_MS pour interpreter un "mm/tour" - une
      --  regle metier dans la page, et fausse des que le dt varie (R1).
      L ("  const ms=(sp/1000).toFixed(2);");
      L ("  setLabel(o,'#'+tk.id+'  '+d+'mm  '+ms+'m/s'+(tk.coast?' *':''));");
      L ("  o.lab.visible=showLabels.checked&&tk.id===selectedId;");
      L ("  o.lab.position.copy(p).add(new THREE.Vector3(0,220,0));");
      L ("  const tp=(trails[tk.id]||[]).map(v3);tp.push(p);");
      L ("  const a=o.trail.geometry.attributes.position,n=Math.min(tp.length,11);");
      L ("  for(let i=0;i<n;i++){const q=tp[tp.length-n+i];a.setXYZ(i,q.x,q.y,q.z);}");
      L ("  a.needsUpdate=true;o.trail.geometry.setDrawRange(0,n);o.hasTrail=n>1;o.trail.visible=showTrails.checked&&o.hasTrail;");
      L ("  const row=document.createElement('button');row.type='button';row.className='target-row'+(tk.coast?' coasting':'')+(tk.id===selectedId?' selected':'');row.setAttribute('aria-pressed',tk.id===selectedId);");
      L ("  row.addEventListener('click',()=>{selectedId=tk.id;ctr.copy(p);});");
      L ("  const ident=document.createElement('span');ident.className='target-id';");
      L ("  const mark=document.createElement('i');mark.className='target-mark';ident.append(mark,document.createTextNode('#'+tk.id));");
      L ("  const details=document.createElement('span');details.className='target-data';");
      L ("  const range=document.createElement('span');range.textContent=(d/1000).toFixed(2)+' m';");
      L ("  const speed=document.createElement('span');speed.className='target-speed';speed.textContent=ms+' m/s';");
      L ("  const state=document.createElement('span');state.className='track-state';state.textContent=tk.coast?'Extrapolee':'Suivi';");
      L ("  details.append(range,speed,state);row.append(ident,details);list.append(row);");
      L (" }");
      --  Une piste qui n'est plus publiee rend ses objets.
      L (" for(const id in pool)if(!seen[id])drop(id);");
      L (" if(selectedId!==null&&!seen[selectedId])selectedId=null;");
      L (" targetCount.textContent=s.tracks.length;");
      L (" statusEl.textContent=s.calibrating?'Calibration du decor':'Surveillance active';");
      L (" statusNote.textContent=s.calibrating?'Tour '+s.turn+' : apprentissage des echos fixes.':'Tour '+s.turn+' : suivi des mouvements en temps reel.';");
      L (" statusIndicator.classList.toggle('active',!s.calibrating);");
      L (" emptyState.hidden=s.tracks.length>0;tgts.replaceChildren(emptyState,list);}");
      --  Flux pousse par le serveur (Server-Sent Events, route /events) :
      --  chaque etat arrive des qu'il est calcule, au lieu d'etre redemande
      --  toutes les 250 ms. EventSource se reconnecte seul si le lien tombe.
      L ("const es=new EventSource('/events');");
      L ("es.onopen=()=>{linkState.classList.add('online');linkState.classList.remove('offline');linkLabel.textContent='Connecte';};");
      L ("es.onmessage=ev=>{const s=JSON.parse(ev.data);");
      L (" if(s.turn!==lastTurn){lastTurn=s.turn;");
      L ("  for(const tk of s.tracks){(trails[tk.id]=trails[tk.id]||[]).push({x:tk.x,y:tk.y,z:tk.z});if(trails[tk.id].length>10)trails[tk.id].shift();}}");
      L (" draw(s);};");
      L ("es.onerror=()=>{linkState.classList.remove('online');linkState.classList.add('offline');linkLabel.textContent='Reconnexion';};");
      --  Camera : orbite autour d'un centre deplacable (memes commandes
      --  que le mode cartographie).
      L ("let rotY=0.6,rotX=0.4,dist=7000;const ctr=new THREE.Vector3(0,0,0);");
      L ("document.getElementById('reset-view').addEventListener('click',()=>{selectedId=null;ctr.set(0,0,0);rotY=0.6;rotX=0.4;dist=7000;});");
      L ("let down=false,px=0,py=0;");
      L ("rnd.domElement.addEventListener('pointerdown',e=>{down=true;px=e.clientX;py=e.clientY;rnd.domElement.setPointerCapture(e.pointerId);});");
      L ("addEventListener('pointerup',()=>down=false);addEventListener('pointercancel',()=>down=false);");
      L ("rnd.domElement.addEventListener('pointermove',e=>{if(!down)return;rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;rotX=Math.max(-1.5,Math.min(1.5,rotX));px=e.clientX;py=e.clientY;});");
      L ("rnd.domElement.addEventListener('wheel',e=>{dist*=(1+e.deltaY*0.001);dist=Math.max(300,Math.min(40000,dist));},{passive:true});");
      L ("const keys={};");
      L ("addEventListener('keydown',e=>keys[e.key.toLowerCase()]=true);");
      L ("addEventListener('keyup',e=>keys[e.key.toLowerCase()]=false);");
      L ("function moveCtr(){const sp=dist*0.02;");
      L (" const fwd=new THREE.Vector3(ctr.x-cam.position.x,0,ctr.z-cam.position.z).normalize();");
      L (" const rgt=new THREE.Vector3(-fwd.z,0,fwd.x);");
      L (" if(keys['z']||keys['w'])ctr.addScaledVector(fwd,sp);");
      L (" if(keys['s'])ctr.addScaledVector(fwd,-sp);");
      L (" if(keys['q']||keys['a'])ctr.addScaledVector(rgt,-sp);");
      L (" if(keys['d'])ctr.addScaledVector(rgt,sp);");
      L (" if(keys['r'])ctr.y+=sp;if(keys['f'])ctr.y-=sp;}");
      L ("addEventListener('resize',()=>{cam.aspect=innerWidth/innerHeight;cam.updateProjectionMatrix();rnd.setSize(innerWidth,innerHeight);});");
      L ("function loop(){requestAnimationFrame(loop);moveCtr();");
      L (" cam.position.x=ctr.x+Math.cos(rotY)*Math.cos(rotX)*dist;");
      L (" cam.position.z=ctr.z+Math.sin(rotY)*Math.cos(rotX)*dist;");
      L (" cam.position.y=ctr.y+Math.sin(rotX)*dist;cam.lookAt(ctr);");
      L (" rnd.render(scene,cam);}loop();");
      L ("</script></body></html>");
      return P;
   end Build_Page;

   Page : constant Unbounded_String := Build_Page;

   --  ----- Le pipeline (un tour de scan) -----

   function Build_State return Unbounded_String is
      R     : Unbounded_String;
      First : Boolean := True;
   begin
      --  "calibrating" : c'est le serveur qui sait si la calibration dure
      --  encore, pas la page. Elle testait autrefois turn < 2 elle-meme :
      --  une regle metier dans le JavaScript (R1), fausse des que
      --  Calibration_Turns a change.
      Append (R, "{""turn"":" & Img (Turn) & ",""turn_ms"":"
                 & Img (Turn_Ms) & ",""calibrating"":"
                 & (if Turn < Calibration_Turns then "true" else "false")
                 & ",""tracks"":[");
      --  Seules les pistes confirmees (M-sur-N) sont publiees : les
      --  tentatives et les fantomes de multitrajet restent invisibles.
      --  "coast" = 1 : piste non revue ce tour, position extrapolee.
      for I in Trk.Tracks'Range loop
         if Trk.Tracks (I).Active and then Trk.Tracks (I).Confirmed then
            if not First then
               Append (R, ",");
            end if;
            First := False;
            Append (R, "{""id"":" & Img (Trk.Tracks (I).Id)
                       & ",""x"":" & F_Img (Trk.Tracks (I).Pos.X)
                       & ",""y"":" & F_Img (Trk.Tracks (I).Pos.Y)
                       & ",""z"":" & F_Img (Trk.Tracks (I).Pos.Z)
                       & ",""vx"":" & F_Img (Trk.Tracks (I).Velocity.X)
                       & ",""vy"":" & F_Img (Trk.Tracks (I).Velocity.Y)
                       & ",""vz"":" & F_Img (Trk.Tracks (I).Velocity.Z)
                       & ",""coast"":"
                       & (if Trk.Tracks (I).Missing > 0 then "1" else "0")
                       & "}");
         end if;
      end loop;
      Append (R, "]}");
      return R;
   end Build_State;

   procedure Process_Turn is
      F      : Frame;
      M      : Measurement;
      OK     : Boolean;
      Points : Unbounded_String;
      First  : Boolean := True;
   begin
      Reset (F);
      if Turn = 0 then
         Append (Points, "{""points"":[");
      end if;

      for I in 1 .. Per_Turn (Src) loop
         exit when not Src.Has_More;
         Src.Next (M, OK);
         exit when not OK;

         --  Ce mode remplit F.Items lui-meme (il insere le filtre de
         --  clutter entre la detection et la conversion 3D) et court-
         --  circuite donc Radar_Detect.Add : c est a lui de dater la
         --  frame. Sans cette ligne, le dt vaut son plancher et les
         --  vitesses sortent mille fois trop grandes. Meme raison pour
         --  Min_Range : sans lui, une piste qui passe au pied du radar
         --  serait tenue pour perdue au bout du delai ordinaire.
         F.Stamp     := M.Stamp;
         F.Min_Range := Profile_Min_Range;

         declare
            D : constant Detection := Detect_Adaptive (M.Data);
         begin
            --  Apprentissage du decor : chaque tour pendant la
            --  calibration, puis a faible cadence en tache de fond.
            if Turn < Calibration_Turns
              or else Turn mod Learn_Period = 0
            then
               Learn (Clut, M.Azimuth, M.Elevation, D);
            end if;

            --  Nuage decoratif (affichage) : collecte au premier tour.
            if Turn = 0 then
               for K in 1 .. D.Count loop
                  declare
                     P : constant Point_3D :=
                       To_Point (Float (Bin_Distance (D.Targets (K))),
                                 M.Azimuth, M.Elevation);
                  begin
                     if not First then
                        Append (Points, ",");
                     end if;
                     First := False;
                     Append (Points, "[" & F_Img (P.X) & "," & F_Img (P.Y)
                                     & "," & F_Img (P.Z) & "]");
                  end;
               end loop;
            end if;

            --  Surveillance (apres calibration) : le clutter est
            --  soustrait, seuls les echos nouveaux (= mobiles)
            --  alimentent le pistage.
            if Turn >= Calibration_Turns then
               declare
                  DF : constant Detection :=
                    Filter (Clut, M.Azimuth, M.Elevation, D);
               begin
                  for K in 1 .. DF.Count loop
                     exit when F.Count = Max_Detections;
                     declare
                        Dist : constant Float :=
                          Float (Bin_Distance (DF.Targets (K)));
                     begin
                        F.Count := F.Count + 1;
                        F.Items (F.Count) :=
                          (Pos      => To_Point (Dist, M.Azimuth, M.Elevation),
                           Distance => Dist);
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;

      if Turn = 0 then
         Append (Points, "]}");
         Cloud_Json := Points;
      end if;

      if Turn >= Calibration_Turns then
         --  Regroupement guide par les pistes : deux personnes qui se
         --  croisent ne deviennent pas une seule detection (CAP dette 16).
         Update (Trk, Cluster (F, Owners (Trk, F)));
      end if;

      --  Oubli lent du decor disparu.
      if Turn > 0 and then Turn mod Age_Period = 0 then
         Age (Clut);
      end if;

      Turn       := Turn + 1;
      State_Json := Build_State;
   end Process_Turn;

   --  ----- Les routes HTTP -----

   procedure Route (Path : String; Sock : Socket_Type) is
   begin
      if Path = "/" then
         Send_Response (Sock, "text/html", Page);
      elsif Path = "/state.json" then
         Send_Response (Sock, "application/json", State_Json);
      elsif Path = "/cloud.json" then
         Send_Response (Sock, "application/json", Cloud_Json);
      else
         Send_Response (Sock, "text/plain",
                        To_Unbounded_String ("not found"),
                        "404 Not Found");
      end if;
   end Route;

   Next_Turn : Time;

begin
   Clear (Clut);
   Start (Srv, Port);

   Put_Line ("Mode LIVE : ouvre http://localhost:" & Img (Port)
             & "  (Ctrl+C pour arreter)");
   Put_Line ("Tours 1 a " & Img (Calibration_Turns)
             & " = calibration du decor, les cibles apparaissent ensuite.");

   Next_Turn := Clock;
   loop
      Process_Turn;
      --  Pousse le nouvel etat aux pages abonnees des qu'il existe.
      Broadcast (Srv, To_String (State_Json));
      Next_Turn := Next_Turn + Milliseconds (Turn_Ms);
      Serve_Until (Srv, Next_Turn, Route'Access);
   end loop;
end Radar_Run_Live;
