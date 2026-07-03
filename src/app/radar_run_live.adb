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

--  MODE LIVE : surveillance temps reel servie dans le navigateur.
--
--  Un serveur HTTP minimal, ecrit en Ada pur (GNAT.Sockets), fait
--  tourner la simulation en continu (un tour de scan toutes les
--  Turn_Ms millisecondes) et sert :
--    /            la page 3D (Three.js), qui se met a jour seule ;
--    /state.json  les pistes courantes (id, position, vitesse) ;
--    /cloud.json  le decor statique appris au 1er tour (les murs).
--
--  Le TOUR 1 sert de CALIBRATION : tout echo est memorise dans la
--  carte de clutter (Radar_Clutter) comme decor statique. Ensuite,
--  seuls les echos qui s'en ecartent deviennent des pistes : c'est le
--  MTI (Moving Target Indication) d'un radar de veille au sol. Un
--  objet immobile pendant la calibration est invisible jusqu'a ce
--  qu'il bouge - comportement normal d'une carte de clutter.
--
--  Architecture volontairement MONO-THREAD : entre deux tours, le
--  serveur attend les connexions avec un selector a timeout. Pas de
--  taches ici - la concurrence Ravenscar vit dans radar_demo et, a
--  terme, sur la carte ; le jour du materiel, seule la source change
--  (UART au lieu du simulateur).
procedure Radar_Run_Live is

   Port    : constant := 8080;
   Turn_Ms : constant := 800;

   --  Tours de calibration : le decor est appris a chaque tour jusqu'a
   --  atteindre le niveau de confirmation de la carte de clutter ; le
   --  pistage ne demarre qu'apres.
   Calibration_Turns : constant := 2;

   --  Apprentissage de fond (1 tour sur N) : le decor qui apparait
   --  (meuble deplace...) finit par etre appris, mais un mobile qui ne
   --  fait que passer n'est vu qu'une fois par case : il ne devient
   --  pas du decor.
   Learn_Period : constant := 4;

   --  Oubli lent (1 vieillissement tous les N tours) : le decor qui
   --  disparait finit par etre oublie.
   Age_Period : constant := 8;

   Src  : Simulated_Source := Make (Sweeps => Positive'Last, See_Room => True);
   Trk  : Tracker;
   Clut : Clutter_Map;

   Turn : Natural := 0;

   State_Json : Unbounded_String :=
     To_Unbounded_String ("{""turn"":0,""turn_ms"":800,""tracks"":[]}");
   Cloud_Json : Unbounded_String :=
     To_Unbounded_String ("{""points"":[]}");

   Srv : Radar_Http.Server;

   --  ================= LA PAGE (visualiseur live) =================

   function Build_Page return Unbounded_String is
      P : Unbounded_String;
      procedure L (S : String) is
      begin
         Append (P, S);
         Append (P, ASCII.LF);
      end L;
   begin
      L ("<!DOCTYPE html><html lang='fr'><head><meta charset='UTF-8'>");
      L ("<title>radar_fw - Live</title><style>");
      L ("body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
      L ("#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.7;background:rgba(6,16,12,.6);padding:10px 12px;border:1px solid #1c3a2e;border-radius:6px;max-width:320px}");
      L ("#info b{color:#34e29b}#tgts{color:#ffd23b}");
      L (".hint{color:#6f8c80;font-size:11px;margin-top:6px;line-height:1.4}</style></head><body>");
      L ("<div id='info'><b>radar_fw - surveillance live</b>");
      L ("<div id='status'>connexion...</div><div id='tgts'></div>");
      L ("<div class='hint'>Glisser : tourner &middot; molette : zoom<br>ZQSD/WASD : se deplacer &middot; R/F : monter/descendre<br>Points verts : decor appris &middot; spheres : cibles CONFIRMEES<br>Gris + * : piste non revue ce tour (position extrapolee)</div></div>");
      L ("<script src='https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'></script>");
      L ("<script>");
      L ("const scene=new THREE.Scene();");
      L ("const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,100000);");
      L ("const rnd=new THREE.WebGLRenderer({antialias:true});");
      L ("rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
      L ("document.body.appendChild(rnd.domElement);");
      L ("scene.add(new THREE.GridHelper(8000,16,0x1c3a2e,0x1c3a2e));");
      L ("scene.add(new THREE.Mesh(new THREE.SphereGeometry(90,16,16),new THREE.MeshBasicMaterial({color:0xff5d3b})));");
      --  Decor statique : charge UNE fois (il ne change pas).
      L ("fetch('/cloud.json').then(r=>r.json()).then(c=>{");
      L (" const g=new THREE.BufferGeometry(),pos=[];");
      L (" c.points.forEach(p=>pos.push(p[0],p[2],p[1]));");
      L (" g.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
      L (" scene.add(new THREE.Points(g,new THREE.PointsMaterial({color:0x1f7a5a,size:35})));});");
      L ("const dyn=new THREE.Group();scene.add(dyn);");
      L ("function v3(p){return new THREE.Vector3(p.x,p.z,p.y);}");
      L ("function makeLabel(t){");
      L (" const c=document.createElement('canvas');c.width=256;c.height=64;");
      L (" const g=c.getContext('2d');g.font='26px monospace';g.fillStyle='#d8f5e8';g.textAlign='center';g.fillText(t,128,40);");
      L (" const s=new THREE.Sprite(new THREE.SpriteMaterial({map:new THREE.CanvasTexture(c),depthTest:false}));");
      L (" s.scale.set(1100,275,1);return s;}");
      L ("function clearDyn(){");
      L (" dyn.traverse(o=>{if(o!==dyn){if(o.geometry)o.geometry.dispose();if(o.material){if(o.material.map)o.material.map.dispose();o.material.dispose();}}});");
      L (" while(dyn.children.length)dyn.remove(dyn.children[0]);}");
      --  Etat courant + trainees cote client (id -> dernieres positions).
      L ("const status=document.getElementById('status'),tgts=document.getElementById('tgts');");
      L ("let TURN_MS=800,lastTurn=-1;const trails={};");
      L ("function draw(s){");
      L (" clearDyn();let list='';");
      L (" for(const tk of s.tracks){");
      L ("  const p=v3(tk);");
      L ("  const col=tk.coast?0x777777:0x34e29b;");
      L ("  const b=new THREE.Mesh(new THREE.SphereGeometry(70,16,16),new THREE.MeshBasicMaterial({color:col}));");
      L ("  b.position.copy(p);dyn.add(b);");
      L ("  const vel=new THREE.Vector3(tk.vx,tk.vz,tk.vy),sp=vel.length();");
      L ("  if(sp>1){const len=Math.min(2500,sp*5);dyn.add(new THREE.ArrowHelper(vel.clone().normalize(),p,len,0xffd23b,len*0.3,len*0.2));}");
      L ("  const d=Math.round(Math.sqrt(tk.x*tk.x+tk.y*tk.y+tk.z*tk.z));");
      L ("  const ms=(sp*1000/TURN_MS/1000).toFixed(2);");
      L ("  const lab=makeLabel('#'+tk.id+'  '+d+'mm  '+ms+'m/s'+(tk.coast?' *':''));");
      L ("  lab.position.copy(p).add(new THREE.Vector3(0,220,0));dyn.add(lab);");
      L ("  const tp=(trails[tk.id]||[]).map(v3);tp.push(p);");
      L ("  if(tp.length>1)dyn.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(tp),new THREE.LineBasicMaterial({color:0x1f7a5a})));");
      L ("  list+='#'+tk.id+' &mdash; '+d+' mm &mdash; '+ms+' m/s<br>';");
      L (" }");
      L (" status.innerHTML=(s.turn<2)?'calibration du decor...':'Tour '+s.turn+' &middot; '+s.tracks.length+' cible(s) confirmee(s)';");
      L (" tgts.innerHTML=list;}");
      L ("async function tick(){");
      L (" try{const s=await(await fetch('/state.json')).json();TURN_MS=s.turn_ms;");
      L ("  if(s.turn!==lastTurn){lastTurn=s.turn;");
      L ("   for(const tk of s.tracks){(trails[tk.id]=trails[tk.id]||[]).push({x:tk.x,y:tk.y,z:tk.z});if(trails[tk.id].length>10)trails[tk.id].shift();}}");
      L ("  draw(s);}catch(e){status.innerHTML='serveur arrete';}}");
      L ("setInterval(tick,250);");
      --  Camera : orbite autour d'un centre deplacable (memes commandes
      --  que le mode cartographie).
      L ("let rotY=0.6,rotX=0.4,dist=7000;const ctr=new THREE.Vector3(0,0,0);");
      L ("let down=false,px=0,py=0;");
      L ("addEventListener('mousedown',e=>{down=true;px=e.clientX;py=e.clientY;});");
      L ("addEventListener('mouseup',()=>down=false);");
      L ("addEventListener('mousemove',e=>{if(!down)return;rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;rotX=Math.max(-1.5,Math.min(1.5,rotX));px=e.clientX;py=e.clientY;});");
      L ("addEventListener('wheel',e=>{dist*=(1+e.deltaY*0.001);dist=Math.max(300,Math.min(40000,dist));});");
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

   --  ================= LE PIPELINE (un tour de scan) =================

   function Build_State return Unbounded_String is
      R     : Unbounded_String;
      First : Boolean := True;
   begin
      Append (R, "{""turn"":" & Img (Turn) & ",""turn_ms"":"
                 & Img (Turn_Ms) & ",""tracks"":[");
      --  Seules les pistes CONFIRMEES (M-sur-N) sont publiees : les
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
            --  soustrait, seuls les echos NOUVEAUX (= mobiles)
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
         Update (Trk, Cluster (F));
      end if;

      --  Oubli lent du decor disparu.
      if Turn > 0 and then Turn mod Age_Period = 0 then
         Age (Clut);
      end if;

      Turn       := Turn + 1;
      State_Json := Build_State;
   end Process_Turn;

   --  ================= LES ROUTES HTTP =================

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
   Put_Line ("Tour 1 = calibration du decor, les cibles apparaissent au tour 2.");

   Next_Turn := Clock;
   loop
      Process_Turn;
      Next_Turn := Next_Turn + Milliseconds (Turn_Ms);
      Serve_Until (Srv, Next_Turn, Route'Access);
   end loop;
end Radar_Run_Live;
