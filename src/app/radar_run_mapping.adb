with Ada.Directories;
with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Geometry;     use Radar_Geometry;
with Radar_Cloud;        use Radar_Cloud;
with Radar_Html;         use Radar_Html;

--  Ce programme genere du HTML : lignes longues assumees (script Three.js).
pragma Style_Checks ("M300");

--  Mode cartographie : un tour de scan meticuleux d'un environnement
--  statique (les murs de la piece), accumule en nuage de points dense,
--  puis rendu 3D fige et explorable. La meme source abstraite et la meme
--  chaine de detection prouvee que le mode surveillance : seul le
--  traitement des balayages change (accumulation au lieu de pistage).
procedure Radar_Run_Mapping is

   --  Les fichiers generes vont dans out/ : la racine du depot reste
   --  lisible. Le dossier est cree au besoin (Create ne le fait pas).
   Out_Dir   : constant String := "out";
   File_Name : constant String := Out_Dir & "/radar_3d.html";
   Out_F     : File_Type;

   --  Un seul tour, grille fine (180 azimuts x 24 elevations).
   --
   --  Declaree en Source'Class et non en Simulated_Source : tous les
   --  appels ci-dessous (Has_More, Next) sont alors dispatchants, et une
   --  autre source de profils se brancherait ici sans toucher au reste du
   --  mode. Un pilote reel devra respecter ce contrat de profil de
   --  distance, adapte a ses donnees et a ses metadonnees.
   Src   : Source'Class := Make_Room_Scan;
   Cloud : Point_Cloud := Empty_Cloud;

   M  : Measurement;
   OK : Boolean;

begin
   --  ----- 1. Le scan simule : chaque balayage passe par Detect_Adaptive -----
   --  (preuve de seuil logiciel, pas de validation de fausse alarme physique)
   --  et chaque cible simulee devient un point 3D du nuage.
   while Src.Has_More loop
      Src.Next (M, OK);
      exit when not OK;

      declare
         D : constant Detection := Detect_Adaptive (M.Data);
      begin
         for K in 1 .. D.Count loop
            Append (Cloud,
                    To_Point (Float (Bin_Distance (D.Targets (K))),
                              M.Azimuth, M.Elevation));
         end loop;
      end;
   end loop;

   --  ----- 2. Le visualiseur (nuage de points Three.js autonome) -----
   Ada.Directories.Create_Path (Out_Dir);
   Create (Out_F, Out_File, File_Name);

   Put_Line (Out_F, "<!DOCTYPE html><html lang=""fr""><head><meta charset=""UTF-8"">");
   Put_Line (Out_F, "<title>radar_fw - Cartographie 3D</title><style>");
   Put_Line (Out_F, "body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
   Put_Line (Out_F, "#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.6;background:rgba(6,16,12,.6);padding:10px 12px;border:1px solid #1c3a2e;border-radius:6px;max-width:320px}");
   Put_Line (Out_F, "#info b{color:#34e29b}");
   Put_Line (Out_F, "#sel{margin-top:8px;color:#ffd23b;line-height:1.5}");
   Put_Line (Out_F, ".hint{color:#6f8c80;font-size:11px;margin-top:6px;line-height:1.4}</style></head><body>");
   Put_Line (Out_F, "<div id=""info""><b>radar_fw</b> - cartographie d'une piece (scan simule)");
   if Cloud.Dropped > 0 then
      Put_Line (Out_F, "<div class=""hint"" style=""color:#ff8b72"">Attention : " &
                Img (Cloud.Dropped) & " points ignores, carte incomplete.</div>");
   end if;
   Put_Line (Out_F, "<div class=""hint"">Glisser : tourner &middot; molette : zoom<br>ZQSD/WASD : se deplacer &middot; R/F : monter/descendre<br>Clic sur un point : details</div>");
   Put_Line (Out_F, "<div id=""sel""></div></div>");
   Put_Line (Out_F, "<script src=""https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js""></script>");

   --  Les points accumules par le scan, chacun accompagne de sa
   --  position polaire (distance, azimut, elevation) calculee ici par
   --  To_Polar - la fonction Ada couverte par les tests. La page se
   --  contente de l'afficher : elle ne refait aucune geometrie (R1).
   Put (Out_F, "<script>const PTS=[");
   for I in 1 .. Cloud.Count loop
      declare
         Pt : constant Point_3D := Cloud.Points (I);
         Pl : constant Polar    := To_Polar (Pt);
      begin
         Put (Out_F, "[");
         Put_Float (Out_F, Pt.X);        Put (Out_F, ",");
         Put_Float (Out_F, Pt.Y);        Put (Out_F, ",");
         Put_Float (Out_F, Pt.Z);        Put (Out_F, ",");
         Put_Float (Out_F, Pl.Distance); Put (Out_F, ",");
         Put_Float (Out_F, Pl.Azimuth);  Put (Out_F, ",");
         Put_Float (Out_F, Pl.Elevation);
         Put (Out_F, "]");
      end;
      if I /= Cloud.Count then
         Put (Out_F, ",");
      end if;
   end loop;
   Put_Line (Out_F, "];");

   --  Mise en scene 3D.
   Put_Line (Out_F, "const scene=new THREE.Scene();");
   Put_Line (Out_F, "const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,50000);");
   Put_Line (Out_F, "const rnd=new THREE.WebGLRenderer({antialias:true});");
   Put_Line (Out_F, "rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
   Put_Line (Out_F, "document.body.appendChild(rnd.domElement);");

   --  Nuage de points (monde Z vers le haut -> Three.js Y vers le haut),
   --  colore par hauteur pour la lisibilite (sombre en bas, clair en haut).
   Put_Line (Out_F, "const geo=new THREE.BufferGeometry();");
   Put_Line (Out_F, "const pos=[],col=[];let zmin=1e9,zmax=-1e9;");
   Put_Line (Out_F, "PTS.forEach(p=>{if(p[2]<zmin)zmin=p[2];if(p[2]>zmax)zmax=p[2];});");
   Put_Line (Out_F, "const c0=new THREE.Color(0x14523c),c1=new THREE.Color(0x8ef5c8);");
   Put_Line (Out_F, "PTS.forEach(p=>{pos.push(p[0],p[2],p[1]);const t=(p[2]-zmin)/Math.max(1,zmax-zmin);const c=c0.clone().lerp(c1,t);col.push(c.r,c.g,c.b);});");
   Put_Line (Out_F, "geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
   Put_Line (Out_F, "geo.setAttribute('color',new THREE.Float32BufferAttribute(col,3));");
   Put_Line (Out_F, "const mat=new THREE.PointsMaterial({vertexColors:true,size:45});");
   Put_Line (Out_F, "const cloud=new THREE.Points(geo,mat);scene.add(cloud);");

   --  Marqueur du radar (au centre) + grille de sol.
   Put_Line (Out_F, "const r=new THREE.Mesh(new THREE.SphereGeometry(80,16,16),");
   Put_Line (Out_F, "new THREE.MeshBasicMaterial({color:0xff5d3b}));scene.add(r);");
   Put_Line (Out_F, "scene.add(new THREE.GridHelper(6000,12,0x1c3a2e,0x1c3a2e));");

   --  Marqueur du point selectionne (sphere jaune en fil de fer).
   Put_Line (Out_F, "const selM=new THREE.Mesh(new THREE.SphereGeometry(70,12,12),new THREE.MeshBasicMaterial({color:0xffd23b,wireframe:true}));");
   Put_Line (Out_F, "selM.visible=false;scene.add(selM);");
   Put_Line (Out_F, "const selDiv=document.getElementById('sel');");

   --  Camera : orbite autour d'un centre deplacable (ctr). Glisser =
   --  tourner autour de ctr ; ZQSD/WASD = deplacer ctr ; molette = zoom.
   Put_Line (Out_F, "let rotY=0.6,rotX=0.4,dist=5000;");
   Put_Line (Out_F, "const ctr=new THREE.Vector3(0,0,0);");
   Put_Line (Out_F, "let down=false,px=0,py=0,moved=0;");
   Put_Line (Out_F, "addEventListener('mousedown',e=>{down=true;moved=0;px=e.clientX;py=e.clientY;});");
   Put_Line (Out_F, "addEventListener('mouseup',e=>{down=false;if(moved<5)pick(e);});");
   Put_Line (Out_F, "addEventListener('mousemove',e=>{if(!down)return;moved+=Math.abs(e.clientX-px)+Math.abs(e.clientY-py);");
   Put_Line (Out_F, "rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;rotX=Math.max(-1.5,Math.min(1.5,rotX));px=e.clientX;py=e.clientY;});");
   Put_Line (Out_F, "addEventListener('wheel',e=>{dist*=(1+e.deltaY*0.001);dist=Math.max(200,Math.min(30000,dist));});");

   --  Clavier (ZQSD azerty, WASD qwerty, R/F vertical). Le deplacement
   --  suit l'orientation de la camera, vitesse proportionnelle au zoom.
   Put_Line (Out_F, "const keys={};");
   Put_Line (Out_F, "addEventListener('keydown',e=>keys[e.key.toLowerCase()]=true);");
   Put_Line (Out_F, "addEventListener('keyup',e=>keys[e.key.toLowerCase()]=false);");
   Put_Line (Out_F, "function moveCtr(){const sp=dist*0.02;");
   Put_Line (Out_F, " const fwd=new THREE.Vector3(ctr.x-cam.position.x,0,ctr.z-cam.position.z).normalize();");
   Put_Line (Out_F, " const rgt=new THREE.Vector3(-fwd.z,0,fwd.x);");
   Put_Line (Out_F, " if(keys['z']||keys['w'])ctr.addScaledVector(fwd,sp);");
   Put_Line (Out_F, " if(keys['s'])ctr.addScaledVector(fwd,-sp);");
   Put_Line (Out_F, " if(keys['q']||keys['a'])ctr.addScaledVector(rgt,-sp);");
   Put_Line (Out_F, " if(keys['d'])ctr.addScaledVector(rgt,sp);");
   Put_Line (Out_F, " if(keys['r'])ctr.y+=sp;");
   Put_Line (Out_F, " if(keys['f'])ctr.y-=sp;}");

   --  Clic sur un point : details (position, distance, angles). Le clic
   --  est distingue du glisser par le mouvement cumule (<5 px).
   Put_Line (Out_F, "const ray=new THREE.Raycaster();ray.params.Points.threshold=80;");
   Put_Line (Out_F, "function pick(e){");
   Put_Line (Out_F, " const m=new THREE.Vector2(e.clientX/innerWidth*2-1,-(e.clientY/innerHeight)*2+1);");
   Put_Line (Out_F, " ray.setFromCamera(m,cam);");
   Put_Line (Out_F, " const hits=ray.intersectObject(cloud);");
   Put_Line (Out_F, " if(!hits.length){selM.visible=false;selDiv.innerHTML='';return;}");
   Put_Line (Out_F, " const i=hits[0].index,p=PTS[i];");
   Put_Line (Out_F, " selM.visible=true;selM.position.set(p[0],p[2],p[1]);");
   --  Distance et angles arrivent calcules du cote Ada : la page n'en
   --  recalcule aucun (R1).
   Put_Line (Out_F, " const d=p[3],az=p[4],el=p[5];");
   Put_Line (Out_F, " selDiv.innerHTML='Point #'+i+'<br>x '+Math.round(p[0])+'  y '+Math.round(p[1])+'  z '+Math.round(p[2])+' mm'+");
   Put_Line (Out_F, "  '<br>distance '+Math.round(d)+' mm<br>azimut '+az.toFixed(1)+' deg &middot; elevation '+el.toFixed(1)+' deg';}");

   Put_Line (Out_F, "addEventListener('resize',()=>{cam.aspect=innerWidth/innerHeight;");
   Put_Line (Out_F, "cam.updateProjectionMatrix();rnd.setSize(innerWidth,innerHeight);});");

   --  Boucle d'animation.
   Put_Line (Out_F, "function loop(){requestAnimationFrame(loop);moveCtr();");
   Put_Line (Out_F, "cam.position.x=ctr.x+Math.cos(rotY)*Math.cos(rotX)*dist;");
   Put_Line (Out_F, "cam.position.z=ctr.z+Math.sin(rotY)*Math.cos(rotX)*dist;");
   Put_Line (Out_F, "cam.position.y=ctr.y+Math.sin(rotX)*dist;cam.lookAt(ctr);");
   Put_Line (Out_F, "rnd.render(scene,cam);}loop();");
   Put_Line (Out_F, "</script></body></html>");

   Close (Out_F);

   Put_Line ("Genere " & File_Name & " (" & Img (Cloud.Count) & " points).");
   if Cloud.Dropped > 0 then
      Put_Line ("ATTENTION : " & Img (Cloud.Dropped) &
                " points ignores ; la carte est incomplete.");
   end if;
end Radar_Run_Mapping;
