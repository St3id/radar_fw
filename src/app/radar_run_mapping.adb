with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Sweep;        use Radar_Sweep;
with Radar_Geometry;     use Radar_Geometry;
with Radar_Cloud;        use Radar_Cloud;
with Radar_Html;         use Radar_Html;

--  Ce programme GENERE du HTML : lignes longues assumees (script Three.js).
pragma Style_Checks ("M300");

--  MODE CARTOGRAPHIE : un tour de scan meticuleux d'un environnement
--  STATIQUE (les murs de la piece), accumule en nuage de points dense,
--  puis rendu 3D fige et explorable. La MEME source abstraite et la MEME
--  chaine de detection prouvee que le mode surveillance : seul le
--  traitement des balayages change (accumulation au lieu de pistage).
procedure Radar_Run_Mapping is

   File_Name : constant String := "radar_3d.html";
   Out_F     : File_Type;

   --  Un seul tour, grille fine (180 azimuts x 24 elevations).
   Src   : Simulated_Source := Make_Room_Scan;
   Cloud : Point_Cloud := Empty_Cloud;

   M  : Measurement;
   OK : Boolean;

begin
   --  ===== 1. Le scan : chaque balayage passe par Detect_Clustered =====
   --  (la fonction prouvee : zero fausse alarme), et chaque cible devient
   --  un point 3D du nuage via la geometrie et la distance de sa case.
   while Src.Has_More loop
      Src.Next (M, OK);
      exit when not OK;

      declare
         D : constant Detection := Detect_Clustered (M.Data);
      begin
         for K in 1 .. D.Count loop
            Append (Cloud,
                    To_Point (Float (Bin_Distance (D.Targets (K))),
                              M.Azimuth, M.Elevation));
         end loop;
      end;
   end loop;

   --  ===== 2. Le visualiseur (nuage de points Three.js autonome) =====
   Create (Out_F, Out_File, File_Name);

   Put_Line (Out_F, "<!DOCTYPE html><html lang=""fr""><head><meta charset=""UTF-8"">");
   Put_Line (Out_F, "<title>radar_fw - Cartographie 3D</title><style>");
   Put_Line (Out_F, "body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
   Put_Line (Out_F, "#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.6}");
   Put_Line (Out_F, "#info b{color:#34e29b}</style></head><body>");
   Put_Line (Out_F, "<div id=""info""><b>radar_fw</b> - cartographie d'une piece (scan simule)<br>");
   Put_Line (Out_F, "Glisse pour tourner &middot; molette pour zoomer</div>");
   Put_Line (Out_F, "<script src=""https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js""></script>");

   --  Les points accumules par le scan.
   Put (Out_F, "<script>const PTS=[");
   for I in 1 .. Cloud.Count loop
      Put (Out_F, "[");
      Put_Float (Out_F, Cloud.Points (I).X); Put (Out_F, ",");
      Put_Float (Out_F, Cloud.Points (I).Y); Put (Out_F, ",");
      Put_Float (Out_F, Cloud.Points (I).Z);
      Put (Out_F, "]");
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

   --  Nuage de points (monde Z vers le haut -> Three.js Y vers le haut).
   Put_Line (Out_F, "const geo=new THREE.BufferGeometry();");
   Put_Line (Out_F, "const pos=[];PTS.forEach(p=>pos.push(p[0],p[2],p[1]));");
   Put_Line (Out_F, "geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
   Put_Line (Out_F, "const mat=new THREE.PointsMaterial({color:0x34e29b,size:40});");
   Put_Line (Out_F, "scene.add(new THREE.Points(geo,mat));");

   --  Marqueur du radar (au centre) + grille de sol.
   Put_Line (Out_F, "const r=new THREE.Mesh(new THREE.SphereGeometry(80,16,16),");
   Put_Line (Out_F, "new THREE.MeshBasicMaterial({color:0xff5d3b}));scene.add(r);");
   Put_Line (Out_F, "scene.add(new THREE.GridHelper(6000,12,0x1c3a2e,0x1c3a2e));");

   --  Rotation a la souris (controle minimal maison).
   Put_Line (Out_F, "let rotY=0.6,rotX=0.4,down=false,px=0,py=0,dist=5000;");
   Put_Line (Out_F, "addEventListener('mousedown',e=>{down=true;px=e.clientX;py=e.clientY;});");
   Put_Line (Out_F, "addEventListener('mouseup',()=>down=false);");
   Put_Line (Out_F, "addEventListener('mousemove',e=>{if(!down)return;");
   Put_Line (Out_F, "rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;px=e.clientX;py=e.clientY;});");
   Put_Line (Out_F, "addEventListener('wheel',e=>{dist*=(1+e.deltaY*0.001);});");
   Put_Line (Out_F, "addEventListener('resize',()=>{cam.aspect=innerWidth/innerHeight;");
   Put_Line (Out_F, "cam.updateProjectionMatrix();rnd.setSize(innerWidth,innerHeight);});");

   --  Boucle d'animation.
   Put_Line (Out_F, "function loop(){requestAnimationFrame(loop);");
   Put_Line (Out_F, "cam.position.x=Math.cos(rotY)*Math.cos(rotX)*dist;");
   Put_Line (Out_F, "cam.position.z=Math.sin(rotY)*Math.cos(rotX)*dist;");
   Put_Line (Out_F, "cam.position.y=Math.sin(rotX)*dist;cam.lookAt(0,0,0);");
   Put_Line (Out_F, "rnd.render(scene,cam);}loop();");
   Put_Line (Out_F, "</script></body></html>");

   Close (Out_F);

   Put_Line ("Genere " & File_Name & " (" & Img (Cloud.Count) & " points).");
end Radar_Run_Mapping;
