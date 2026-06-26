with Ada.Text_IO;  use Ada.Text_IO;
with Radar_Cloud;  use Radar_Cloud;

--  Ce fichier GENERE du HTML : certaines lignes (balises et script Three.js)
--  depassent volontairement la limite de 79 colonnes. On releve donc la
--  limite de longueur de ligne pour CE seul fichier, sans toucher aux autres
--  regles de style ni aux autres fichiers.
pragma Style_Checks ("M200");

procedure Radar_Fw is

   File_Name : constant String := "radar_3d.html";
   Out_F     : File_Type;

   Cloud : constant Point_Cloud := Scan_Room;

   --  Ecrit un Float avec un point decimal, sans espace de tete.
   procedure Put_Float (V : Float) is
      Img : constant String := Float'Image (V);
   begin
      if Img (Img'First) = ' ' then
         Put (Out_F, Img (Img'First + 1 .. Img'Last));
      else
         Put (Out_F, Img);
      end if;
   end Put_Float;

begin
   Create (Out_F, Out_File, File_Name);

   --  ===== En-tete HTML + chargement de Three.js =====
   Put_Line (Out_F, "<!DOCTYPE html><html lang=""fr""><head><meta charset=""UTF-8"">");
   Put_Line (Out_F, "<title>radar_fw - Nuage 3D</title><style>");
   Put_Line (Out_F, "body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
   Put_Line (Out_F, "#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.6}");
   Put_Line (Out_F, "#info b{color:#34e29b}</style></head><body>");
   Put_Line (Out_F, "<div id=""info""><b>radar_fw</b> - reconstruction 3D d'une piece<br>");
   Put_Line (Out_F, "Glisse pour tourner &middot; molette pour zoomer</div>");
   Put_Line (Out_F, "<script src=""https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js""></script>");

   --  ===== Les points generes par le scan Ada =====
   Put (Out_F, "<script>const PTS=[");
   for I in 1 .. Cloud.Count loop
      Put (Out_F, "[");
      Put_Float (Cloud.Points (I).X); Put (Out_F, ",");
      Put_Float (Cloud.Points (I).Y); Put (Out_F, ",");
      Put_Float (Cloud.Points (I).Z);
      Put (Out_F, "]");
      if I /= Cloud.Count then
         Put (Out_F, ",");
      end if;
   end loop;
   Put_Line (Out_F, "];");

   --  ===== Mise en scene 3D (Three.js) =====
   Put_Line (Out_F, "const scene=new THREE.Scene();");
   Put_Line (Out_F, "const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,50000);");
   Put_Line (Out_F, "cam.position.set(3000,2500,3000);cam.lookAt(0,0,0);");
   Put_Line (Out_F, "const rnd=new THREE.WebGLRenderer({antialias:true});");
   Put_Line (Out_F, "rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
   Put_Line (Out_F, "document.body.appendChild(rnd.domElement);");

   --  Nuage de points.
   Put_Line (Out_F, "const geo=new THREE.BufferGeometry();");
   Put_Line (Out_F, "const pos=[];PTS.forEach(p=>pos.push(p[0],p[2],p[1]));");
   Put_Line (Out_F, "geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));");
   Put_Line (Out_F, "const mat=new THREE.PointsMaterial({color:0x34e29b,size:40});");
   Put_Line (Out_F, "scene.add(new THREE.Points(geo,mat));");

   --  Marqueur du radar (au centre) + reperes.
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
   Put_Line ("Genere " & File_Name & " ("
             & Integer'Image (Cloud.Count) & " points). Double-clique-le !");
end Radar_Fw;
