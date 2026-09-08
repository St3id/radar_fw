with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;            use Ada.Text_IO;
with GNAT.Sockets;           use GNAT.Sockets;

with Radar_Cloud;            use Radar_Cloud;
with Radar_Geometry;         use Radar_Geometry;
with Radar_Html;             use Radar_Html;
with Radar_Http;             use Radar_Http;
with Radar_Sim_Source;       use Radar_Sim_Source;
with Radar_Source;           use Radar_Source;
with Radar_Sweep;            use Radar_Sweep;

--  Ce programme melange Ada et HTML/JS : lignes longues assumees.
pragma Style_Checks ("M300");

--  MODE SCAN : cartographie PROGRESSIVE dans le navigateur.
--
--  Sur le vrai materiel, un scan de piece prendra des MINUTES (tourelle
--  pas-a-pas + temps d'integration par direction) : l'attente doit se
--  voir. Ici le balayage est cadence (une colonne d'azimut par pas de
--  Step_Ms) et la page se remplit au fil de l'eau, avec la progression.
--  Scan termine, le serveur continue de servir le nuage : il reste
--  explorable (deplacement ZQSD, clic sur un point pour ses details),
--  comme le fichier du mode "map".
procedure Radar_Run_Scan is

   Port    : constant := 8080;
   Step_Ms : constant := 60;   --  une colonne d'azimut toutes les 60 ms

   --  Une colonne = toutes les elevations d'un azimut (grille 180 x 24
   --  de Make_Room_Scan : le scan complet dure ~11 s).
   Column : constant := 24;

   --  Source'CLASS : les appels sont dispatchants (voir Radar_Source).
   Src   : Source'Class := Make_Room_Scan;
   Total : constant Positive := Per_Turn (Src);

   Cloud : Point_Cloud := Empty_Cloud;

   Done      : Boolean := False;
   Processed : Natural := 0;

   --  Les points deja acquis, en JSON "[x,y,z],[x,y,z]..." (le corps du
   --  tableau ; les accolades sont ajoutees a la demande).
   Body_Json : Unbounded_String;

   function Cloud_Json return Unbounded_String is
     (To_Unbounded_String ("{""points"":[") & Body_Json
      & To_Unbounded_String ("]}"));

   function State_Json return Unbounded_String is
     (To_Unbounded_String
        ("{""done"":" & (if Done then "1" else "0")
         & ",""count"":" & Img (Cloud.Count)
         & ",""progress"":" & Img (100 * Processed / Total) & "}"));

   --  ================= LA PAGE (nuage progressif) =================

   function Build_Page return Unbounded_String is
      P : Unbounded_String;
      procedure L (S : String) is
      begin
         Append (P, S);
         Append (P, ASCII.LF);
      end L;
   begin
      L ("<!DOCTYPE html><html lang='fr'><head><meta charset='UTF-8'>");
      L ("<title>radar_fw - Scan progressif</title><style>");
      L ("body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
      L ("#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.7;background:rgba(6,16,12,.6);padding:10px 12px;border:1px solid #1c3a2e;border-radius:6px;max-width:320px}");
      L ("#info b{color:#34e29b}#sel{margin-top:8px;color:#ffd23b;line-height:1.5}");
      L (".hint{color:#6f8c80;font-size:11px;margin-top:6px;line-height:1.4}</style></head><body>");
      L ("<div id='info'><b>radar_fw - scan progressif</b>");
      L ("<div id='status'>connexion...</div><div id='sel'></div>");
      L ("<div class='hint'>Glisser : tourner &middot; molette : zoom<br>ZQSD/WASD : se deplacer &middot; R/F : monter/descendre<br>Clic sur un point : details</div></div>");
      L ("<script src='https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js'></script>");
      L ("<script>");
      L ("const scene=new THREE.Scene();");
      L ("const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,50000);");
      L ("const rnd=new THREE.WebGLRenderer({antialias:true});");
      L ("rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
      L ("document.body.appendChild(rnd.domElement);");
      L ("scene.add(new THREE.GridHelper(6000,12,0x1c3a2e,0x1c3a2e));");
      L ("scene.add(new THREE.Mesh(new THREE.SphereGeometry(80,16,16),new THREE.MeshBasicMaterial({color:0xff5d3b})));");
      --  Marqueur du point selectionne + panneau de details.
      L ("const selM=new THREE.Mesh(new THREE.SphereGeometry(70,12,12),new THREE.MeshBasicMaterial({color:0xffd23b,wireframe:true}));");
      L ("selM.visible=false;scene.add(selM);");
      L ("const status=document.getElementById('status'),selDiv=document.getElementById('sel');");
      --  Le nuage : reconstruit quand le serveur annonce de nouveaux
      --  points (couleur par hauteur, comme le mode map).
      L ("let PTS=[],ptsObj=null;");
      L ("function rebuild(){");
      L (" if(ptsObj){scene.remove(ptsObj);ptsObj.geometry.dispose();ptsObj.material.dispose();}");
      L (" if(!PTS.length)return;");
      L (" const pos=[],col=[];let zmin=1e9,zmax=-1e9;");
      L (" PTS.forEach(p=>{if(p[2]<zmin)zmin=p[2];if(p[2]>zmax)zmax=p[2];});");
      L (" const c0=new THREE.Color(0x14523c),c1=new THREE.Color(0x8ef5c8);");
      L (" PTS.forEach(p=>{pos.push(p[0],p[2],p[1]);const t=(p[2]-zmin)/Math.max(1,zmax-zmin);const c=c0.clone().lerp(c1,t);col.push(c.r,c.g,c.b);});");
      L (" const geo=new THREE.BufferGeometry();");
      L (" geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
      L (" geo.setAttribute('color',new THREE.Float32BufferAttribute(col,3));");
      L (" ptsObj=new THREE.Points(geo,new THREE.PointsMaterial({vertexColors:true,size:45}));");
      L (" scene.add(ptsObj);}");
      --  Sondage : progression + rechargement du nuage si necessaire.
      L ("const timer=setInterval(tick,400);");
      L ("async function tick(){");
      L (" try{const s=await(await fetch('/state.json')).json();");
      L ("  status.innerHTML=s.done?('Scan termine &middot; '+s.count+' points &mdash; explore !'):('Scan en cours... '+s.progress+'% &middot; '+s.count+' points');");
      L ("  if(s.count!==PTS.length){const c=await(await fetch('/cloud.json')).json();PTS=c.points;rebuild();}");
      L ("  if(s.done)clearInterval(timer);");
      L (" }catch(e){status.innerHTML='serveur arrete';clearInterval(timer);}}");
      L ("tick();");
      --  Camera : orbite autour d'un centre deplacable + clic-details
      --  (memes commandes que le mode map).
      L ("let rotY=0.6,rotX=0.4,dist=5000;const ctr=new THREE.Vector3(0,0,0);");
      L ("let down=false,px=0,py=0,moved=0;");
      L ("addEventListener('mousedown',e=>{down=true;moved=0;px=e.clientX;py=e.clientY;});");
      L ("addEventListener('mouseup',e=>{down=false;if(moved<5)pick(e);});");
      L ("addEventListener('mousemove',e=>{if(!down)return;moved+=Math.abs(e.clientX-px)+Math.abs(e.clientY-py);");
      L ("rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;rotX=Math.max(-1.5,Math.min(1.5,rotX));px=e.clientX;py=e.clientY;});");
      L ("addEventListener('wheel',e=>{dist*=(1+e.deltaY*0.001);dist=Math.max(200,Math.min(30000,dist));});");
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
      L ("const ray=new THREE.Raycaster();ray.params.Points.threshold=80;");
      L ("function pick(e){");
      L (" if(!ptsObj)return;");
      L (" const m=new THREE.Vector2(e.clientX/innerWidth*2-1,-(e.clientY/innerHeight)*2+1);");
      L (" ray.setFromCamera(m,cam);");
      L (" const hits=ray.intersectObject(ptsObj);");
      L (" if(!hits.length){selM.visible=false;selDiv.innerHTML='';return;}");
      L (" const i=hits[0].index,p=PTS[i];");
      L (" selM.visible=true;selM.position.set(p[0],p[2],p[1]);");
      --  d, az, el arrivent calcules d'Ada : aucun calcul ici (R1).
      L (" const d=p[3],az=p[4],el=p[5];");
      L (" selDiv.innerHTML='Point #'+i+'<br>x '+Math.round(p[0])+'  y '+Math.round(p[1])+'  z '+Math.round(p[2])+' mm'+");
      L ("  '<br>distance '+Math.round(d)+' mm<br>azimut '+az.toFixed(1)+' deg &middot; elevation '+el.toFixed(1)+' deg';}");
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

   --  ================= LE SCAN (une colonne par pas) =================

   procedure Process_Column is
      M  : Measurement;
      OK : Boolean;
   begin
      for I in 1 .. Column loop
         if not Src.Has_More then
            Done := True;
            return;
         end if;
         Src.Next (M, OK);
         if not OK then
            Done := True;
            return;
         end if;
         Processed := Processed + 1;

         declare
            D : constant Detection := Detect_Adaptive (M.Data);
         begin
            for K in 1 .. D.Count loop
               declare
                  P : constant Point_3D :=
                    To_Point (Float (Bin_Distance (D.Targets (K))),
                              M.Azimuth, M.Elevation);

                  --  Position polaire calculee ICI, en Ada, par la
                  --  fonction To_Polar couverte par les tests. Elle
                  --  part avec le point : la page n'a plus aucune
                  --  geometrie a refaire (regle R1).
                  Pl : constant Polar := To_Polar (P);
               begin
                  Append (Cloud, P);
                  if Length (Body_Json) > 0 then
                     Append (Body_Json, ",");
                  end if;
                  Append (Body_Json,
                          "[" & F_Img (P.X)
                          & "," & F_Img (P.Y)
                          & "," & F_Img (P.Z)
                          & "," & F_Img (Pl.Distance)
                          & "," & F_Img (Pl.Azimuth)
                          & "," & F_Img (Pl.Elevation) & "]");
               end;
            end loop;
         end;
      end loop;

      if not Src.Has_More then
         Done := True;
      end if;
   end Process_Column;

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

   Srv       : Radar_Http.Server;
   Next_Step : Time;

begin
   Start (Srv, Port);

   Put_Line ("Mode SCAN : ouvre http://localhost:" & Img (Port)
             & " - le nuage se construit sous tes yeux (Ctrl+C pour arreter).");

   Next_Step := Clock;
   loop
      if not Done then
         Process_Column;
      end if;
      Next_Step := Next_Step + Milliseconds (Step_Ms);
      Serve_Until (Srv, Next_Step, Route'Access);
   end loop;
end Radar_Run_Scan;
