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

--  Mode scan : cartographie progressive dans le navigateur.
--
--  Sur le vrai materiel, un scan de piece prendra des minutes (tourelle
--  pas-a-pas + temps d'integration par direction) : l'attente doit se
--  voir. Ici le balayage est cadence (une colonne d'azimut par pas de
--  Step_Ms) et la page se remplit au fil de l'eau, avec la progression.
--  Scan termine, le serveur continue de servir le nuage : il reste
--  explorable (deplacement ZQSD, clic sur un point pour ses details),
--  comme le fichier du mode "map".
procedure Radar_Run_Scan is

   Port    : constant := 8080;
   Quick_Step_Ms  : constant := 25;
   Detail_Step_Ms : constant := 60;

   --  Deux passes sur le meme contrat de source : la premiere donne vite
   --  une vue globale (60 x 8), la seconde ajoute le detail (180 x 24).
   --  La resolution est un choix de cartographie, pas une promesse de
   --  resolution physique du capteur.
   Quick_Azimuth_Steps : constant Grid_Steps := 60;
   Quick_Elevation_Steps : constant Grid_Steps := 8;
   Detail_Azimuth_Steps : constant Grid_Steps := 180;
   Detail_Elevation_Steps : constant Grid_Steps := 24;

   Quick_Src : Source'Class :=
     Make_Room_Scan (Quick_Azimuth_Steps, Quick_Elevation_Steps);
   Detail_Src : Source'Class :=
     Make_Room_Scan (Detail_Azimuth_Steps, Detail_Elevation_Steps);
   Quick_Total : constant Positive := Per_Turn (Quick_Src);
   Detail_Total : constant Positive := Per_Turn (Detail_Src);
   Total : constant Positive := Quick_Total + Detail_Total;

   Cloud : Point_Cloud := Empty_Cloud;

   type Scan_Stage is (Quick_Pass, Detail_Pass, Complete);
   Stage : Scan_Stage := Quick_Pass;

   Processed       : Natural := 0;
   Stage_Processed : Natural := 0;
   Coarse_Count    : Natural := 0;

   function State_Json return Unbounded_String is
      Stage_Total : constant Positive :=
        (if Stage = Quick_Pass then Quick_Total else Detail_Total);
      Stage_Name : constant String :=
        (case Stage is
            when Quick_Pass  => "quick",
            when Detail_Pass => "detail",
            when Complete    => "done");
      Progress : constant Natural :=
        (if Stage = Complete then 100 else 100 * Processed / Total);
      Stage_Progress : constant Natural :=
        (if Stage = Complete then 100
         else 100 * Stage_Processed / Stage_Total);
   begin
      return To_Unbounded_String
        ("{""done"":" & (if Stage = Complete then "1" else "0")
         & ",""stage"":""" & Stage_Name & """"
         & ",""count"":" & Img (Cloud.Count)
         & ",""dropped"":" & Img (Cloud.Dropped)
         & ",""coarse_count"":" & Img (Coarse_Count)
         & ",""progress"":" & Img (Progress)
         & ",""stage_progress"":" & Img (Stage_Progress) & "}");
   end State_Json;

   --  Le navigateur ne redemande que les points apparus depuis son dernier
   --  passage. Cela evite de retransmettre et reconstruire toute la carte a
   --  chaque rafraichissement.
   function Cloud_Json (First_Point : Natural) return Unbounded_String is
      R : Unbounded_String := To_Unbounded_String ("{""points"":[");
      First : Boolean := True;
   begin
      if First_Point <= Natural (Cloud.Count) then
         for I in Point_Count (First_Point) .. Cloud.Count loop
            declare
               Pt : constant Point_3D := Cloud.Points (I);
               Pl : constant Polar := To_Polar (Pt);
            begin
               if not First then
                  Append (R, ",");
               end if;
               First := False;
               Append (R, "[" & F_Img (Pt.X)
                         & "," & F_Img (Pt.Y)
                         & "," & F_Img (Pt.Z)
                         & "," & F_Img (Pl.Distance)
                         & "," & F_Img (Pl.Azimuth)
                         & "," & F_Img (Pl.Elevation)
                         & "," & (if Stage = Quick_Pass
                                    or else I <= Point_Count (Coarse_Count)
                                    then "0]" else "1]"));
            end;
         end loop;
      end if;
      Append (R, "]}");
      return R;
   end Cloud_Json;

   function Cloud_Start (Path : String) return Natural is
      Prefix : constant String := "/cloud.json?from=";
      Value  : Natural := 0;
   begin
      if Path'Length <= Prefix'Length
        or else Path (Path'First .. Path'First + Prefix'Length - 1)
          /= Prefix
      then
         return 1;
      end if;

      for I in Path'First + Prefix'Length .. Path'Last loop
         exit when Path (I) not in '0' .. '9';
         Value := Natural'Min
           (Max_Points + 1,
            Value * 10 + Character'Pos (Path (I)) - Character'Pos ('0'));
      end loop;
      return Natural'Max (1, Value);
   end Cloud_Start;

   --  ----- La page (nuage progressif) -----

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
      L ("<div id='info'><b>radar_fw - carte progressive</b>");
      L ("<div id='status'>connexion...</div><div id='sel'></div>");
      L ("<div class='hint'>Vue rapide en gris, detail ajoute en vert.<br>Glisser : tourner &middot; molette : zoom<br>ZQSD/WASD : se deplacer &middot; R/F : monter/descendre<br>Clic sur un point : details</div></div>");
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
      --  Capacite fixe comme Radar_Cloud ; les nouveaux points ne forcent
      --  ni retransmission du nuage complet ni recreation de la geometrie GPU.
      L ("const MAX_PTS=8192,PTS=[],pos=new Float32Array(MAX_PTS*3),col=new Float32Array(MAX_PTS*3);");
      L ("const quick=new THREE.Color(0x477d6b),fine=new THREE.Color(0x8ef5c8);");
      L ("const geo=new THREE.BufferGeometry();");
      L ("geo.setAttribute('position',new THREE.BufferAttribute(pos,3));");
      L ("geo.setAttribute('color',new THREE.BufferAttribute(col,3));geo.setDrawRange(0,0);");
      L ("const ptsObj=new THREE.Points(geo,new THREE.PointsMaterial({vertexColors:true,size:45}));scene.add(ptsObj);");
      L ("function appendPoints(batch){");
      L (" for(const p of batch){if(PTS.length>=MAX_PTS)break;const i=PTS.length;PTS.push(p);");
      L ("  pos.set([p[0],p[2],p[1]],i*3);const c=p[6]?fine:quick;col.set([c.r,c.g,c.b],i*3);}");
      L (" geo.attributes.position.needsUpdate=true;geo.attributes.color.needsUpdate=true;geo.setDrawRange(0,PTS.length);}");
      --  Sondage leger : l'API ne renvoie que les nouveaux points.
      L ("const timer=setInterval(tick,250);");
      L ("let polling=false;");
      L ("async function tick(){");
      L (" if(polling)return;polling=true;");
      L (" try{const s=await(await fetch('/state.json')).json();");
      L ("  const phase=s.stage==='quick'?'Carte rapide':s.stage==='detail'?'Affinage detaille':'Carte complete';");
      L ("  status.innerHTML=(s.done?'':phase+' &middot; '+s.stage_progress+'%<br>')+s.progress+'% global &middot; '+s.count+' points'+(s.dropped?' &mdash; '+s.dropped+' ignores, carte incomplete':'')+(s.done?' &mdash; explore !':'');");
      L ("  if(s.count>PTS.length){const c=await(await fetch('/cloud.json?from='+(PTS.length+1))).json();appendPoints(c.points);}");
      L ("  if(s.done)clearInterval(timer);");
      L (" }catch(e){status.innerHTML='serveur arrete';clearInterval(timer);}finally{polling=false;}}");
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
      --  Distance et angles arrivent calcules du cote Ada : la page n'en
      --  recalcule aucun (R1).
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

   --  ----- Le scan (une colonne par pas, quelle que soit sa resolution) -----

   procedure Process_Column (Radar : in out Source'Class) is
      M  : Measurement;
      OK : Boolean;
   begin
      for I in 1 .. Per_Azimuth (Radar) loop
         if not Radar.Has_More then
            return;
         end if;
         Radar.Next (M, OK);
         if not OK then
            return;
         end if;
         Processed := Processed + 1;
         Stage_Processed := Stage_Processed + 1;

         declare
            D : constant Detection := Detect_Adaptive (M.Data);
         begin
            for K in 1 .. D.Count loop
               declare
                  P : constant Point_3D :=
                    To_Point (Float (Bin_Distance (D.Targets (K))),
                              M.Azimuth, M.Elevation);

               begin
                  Append (Cloud, P);
               end;
            end loop;
         end;
      end loop;
   end Process_Column;

   procedure Advance_Scan is
   begin
      case Stage is
         when Quick_Pass =>
            Process_Column (Quick_Src);
            if not Quick_Src.Has_More then
               Coarse_Count := Natural (Cloud.Count);
               Stage := Detail_Pass;
               Stage_Processed := 0;
            end if;
         when Detail_Pass =>
            Process_Column (Detail_Src);
            if not Detail_Src.Has_More then
               Stage := Complete;
               Stage_Processed := 0;
            end if;
         when Complete =>
            null;
      end case;
   end Advance_Scan;

   --  ----- Les routes HTTP -----

   procedure Route (Path : String; Sock : Socket_Type) is
   begin
      if Path = "/" then
         Send_Response (Sock, "text/html", Page);
      elsif Path = "/state.json" then
         Send_Response (Sock, "application/json", State_Json);
      elsif Path = "/cloud.json"
        or else (Path'Length >= 17
                 and then Path (Path'First .. Path'First + 16)
                   = "/cloud.json?from=")
      then
         Send_Response (Sock, "application/json", Cloud_Json (Cloud_Start (Path)));
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

   Put_Line ("Mode SCAN : carte rapide puis detaillee sur http://localhost:"
             & Img (Port) & " (Ctrl+C pour arreter).");

   Next_Step := Clock;
   loop
      if Stage /= Complete then
         Advance_Scan;
      end if;
      Next_Step := Next_Step + Milliseconds
        (if Stage = Quick_Pass then Quick_Step_Ms else Detail_Step_Ms);
      Serve_Until (Srv, Next_Step, Route'Access);
   end loop;
end Radar_Run_Scan;
