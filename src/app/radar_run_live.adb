with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Streams;            use Ada.Streams;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;            use Ada.Text_IO;
with GNAT.Sockets;           use GNAT.Sockets;

with Radar_Clutter;          use Radar_Clutter;
with Radar_Detect;           use Radar_Detect;
with Radar_Geometry;         use Radar_Geometry;
with Radar_Html;             use Radar_Html;
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

   Src  : Simulated_Source := Make (Sweeps => Positive'Last, See_Room => True);
   Trk  : Tracker;
   Clut : Clutter_Map;

   Turn : Natural := 0;

   State_Json : Unbounded_String :=
     To_Unbounded_String ("{""turn"":0,""turn_ms"":800,""tracks"":[]}");
   Cloud_Json : Unbounded_String :=
     To_Unbounded_String ("{""points"":[]}");

   Server : Socket_Type;
   Sel    : Selector_Type;

   CRLF : constant String := ASCII.CR & ASCII.LF;

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
      L ("<div class='hint'>Glisser : tourner &middot; molette : zoom<br>ZQSD/WASD : se deplacer &middot; R/F : monter/descendre<br>Points verts : decor appris (tour 1) &middot; spheres : cibles mobiles</div></div>");
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
      L ("  const b=new THREE.Mesh(new THREE.SphereGeometry(70,16,16),new THREE.MeshBasicMaterial({color:0x34e29b}));");
      L ("  b.position.copy(p);dyn.add(b);");
      L ("  const vel=new THREE.Vector3(tk.vx,tk.vz,tk.vy),sp=vel.length();");
      L ("  if(sp>1){const len=Math.min(2500,sp*5);dyn.add(new THREE.ArrowHelper(vel.clone().normalize(),p,len,0xffd23b,len*0.3,len*0.2));}");
      L ("  const d=Math.round(Math.sqrt(tk.x*tk.x+tk.y*tk.y+tk.z*tk.z));");
      L ("  const ms=(sp*1000/TURN_MS/1000).toFixed(2);");
      L ("  const lab=makeLabel('#'+tk.id+'  '+d+'mm  '+ms+'m/s');");
      L ("  lab.position.copy(p).add(new THREE.Vector3(0,220,0));dyn.add(lab);");
      L ("  const tp=(trails[tk.id]||[]).map(v3);tp.push(p);");
      L ("  if(tp.length>1)dyn.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(tp),new THREE.LineBasicMaterial({color:0x1f7a5a})));");
      L ("  list+='#'+tk.id+' &mdash; '+d+' mm &mdash; '+ms+' m/s<br>';");
      L (" }");
      L (" status.innerHTML=(s.turn===0)?'calibration du decor...':'Tour '+s.turn+' &middot; '+s.tracks.length+' cible(s)';");
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
      for I in Trk.Tracks'Range loop
         if Trk.Tracks (I).Active then
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
            D : constant Detection := Detect_Clustered (M.Data);
         begin
            if Turn = 0 then
               --  Calibration : tout est memorise comme decor statique.
               Learn (Clut, M.Azimuth, M.Elevation, D);
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
            else
               --  Surveillance : le clutter est soustrait, seuls les
               --  echos NOUVEAUX (= mobiles) alimentent le pistage.
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
      else
         Update (Trk, Cluster (F));
      end if;

      Turn       := Turn + 1;
      State_Json := Build_State;
   end Process_Turn;

   --  ================= LE SERVEUR HTTP =================

   procedure Send_Str (Sock : Socket_Type; S : String) is
      Data  : Stream_Element_Array (1 .. Stream_Element_Offset (S'Length));
      First : Stream_Element_Offset := Data'First;
      Last  : Stream_Element_Offset;
   begin
      for I in S'Range loop
         Data (Stream_Element_Offset (I - S'First + 1)) :=
           Stream_Element (Character'Pos (S (I)));
      end loop;
      --  Send_Socket peut envoyer partiellement : on boucle.
      while First <= Data'Last loop
         Send_Socket (Sock, Data (First .. Data'Last), Last);
         exit when Last >= Data'Last;
         First := Last + 1;
      end loop;
   end Send_Str;

   procedure Send_Response
     (Sock   : Socket_Type;
      Ctype  : String;
      Content : Unbounded_String;
      Code   : String := "200 OK")
   is
      B : constant String := To_String (Content);
   begin
      Send_Str (Sock,
        "HTTP/1.1 " & Code & CRLF
        & "Content-Type: " & Ctype & "; charset=utf-8" & CRLF
        & "Content-Length:" & Natural'Image (B'Length) & CRLF
        & "Cache-Control: no-store" & CRLF
        & "Connection: close" & CRLF & CRLF);
      Send_Str (Sock, B);
   end Send_Response;

   procedure Handle (Sock : Socket_Type) is
      Buf  : Stream_Element_Array (1 .. 2048);
      Last : Stream_Element_Offset;
      Req  : String (1 .. 2048) := (others => ' ');
   begin
      Receive_Socket (Sock, Buf, Last);
      for I in Buf'First .. Last loop
         Req (Natural (I)) := Character'Val (Buf (I));
      end loop;

      --  Ligne de requete : "GET /chemin HTTP/1.1". On extrait /chemin.
      declare
         Sp1  : Natural := 0;
         Sp2  : Natural := 0;
      begin
         for I in Req'Range loop
            if Req (I) = ' ' then
               if Sp1 = 0 then
                  Sp1 := I;
               else
                  Sp2 := I;
                  exit;
               end if;
            end if;
         end loop;

         if Sp1 = 0 or else Sp2 = 0 then
            Send_Response (Sock, "text/plain",
                           To_Unbounded_String ("bad request"),
                           "400 Bad Request");
         else
            declare
               Path : constant String := Req (Sp1 + 1 .. Sp2 - 1);
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
            end;
         end if;
      end;

      Close_Socket (Sock);
   exception
      when Socket_Error =>
         --  Client parti en cours de route : on ferme et on continue.
         begin
            Close_Socket (Sock);
         exception
            when Socket_Error => null;
         end;
   end Handle;

   --  Sert les requetes jusqu'a l'echeance du prochain tour : attente
   --  passive sur le socket d'ecoute, avec timeout (selector).
   procedure Serve_Until (Deadline : Time) is
      R_Set  : Socket_Set_Type;
      W_Set  : Socket_Set_Type;
      Status : Selector_Status;
   begin
      loop
         declare
            Remaining : constant Duration := To_Duration (Deadline - Clock);
         begin
            exit when Remaining <= 0.0;
            Empty (R_Set);
            Set (R_Set, Server);
            Empty (W_Set);
            Check_Selector (Sel, R_Set, W_Set, Status, Remaining);
            exit when Status /= Completed;

            declare
               Sock : Socket_Type;
               Addr : Sock_Addr_Type;
            begin
               Accept_Socket (Server, Sock, Addr);
               Handle (Sock);
            end;
         end;
      end loop;
   end Serve_Until;

   Next_Turn : Time;

begin
   Clear (Clut);

   Create_Socket (Server);
   Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
   Bind_Socket (Server, (Family => Family_Inet,
                         Addr   => Inet_Addr ("127.0.0.1"),
                         Port   => Port));
   Listen_Socket (Server);
   Create_Selector (Sel);

   Put_Line ("Mode LIVE : ouvre http://localhost:" & Img (Port)
             & "  (Ctrl+C pour arreter)");
   Put_Line ("Tour 1 = calibration du decor, les cibles apparaissent au tour 2.");

   Next_Turn := Clock;
   loop
      Process_Turn;
      Next_Turn := Next_Turn + Milliseconds (Turn_Ms);
      Serve_Until (Next_Turn);
   end loop;
end Radar_Run_Live;
