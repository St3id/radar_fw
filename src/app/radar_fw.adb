with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Detect;       use Radar_Detect;
with Radar_Track;        use Radar_Track;

--  Ce programme GENERE du HTML : certaines lignes (script Three.js embarque)
--  depassent volontairement la limite de 79 colonnes. On releve donc la
--  limite de longueur de ligne pour CE seul fichier, sans toucher aux autres
--  regles de style ni aux autres fichiers.
pragma Style_Checks ("M200");

procedure Radar_Fw is

   File_Name : constant String := "radar_tracking_3d.html";
   Out_F     : File_Type;

   --  La simulation : on balaie le monde sur 60 tours.
   Src : Simulated_Source := Make (Sweeps => 60);
   Trk : Tracker;

   --  Combien de tours on a reellement enregistres (pour le message final).
   Turn_Count : Natural := 0;

   --  Image d'un entier sans l'espace de tete que met Ada (ex. " 5" -> "5").
   function Img (N : Natural) return String is
      S : constant String := N'Image;
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   --  Ecrit un Float comme nombre JS (point decimal, pas d'espace de tete).
   --  Float'Image donne par ex. "-1.20000E+02" : JS sait lire ce format.
   procedure Put_Float (V : Float) is
      Img_F : constant String := Float'Image (V);
   begin
      if Img_F (Img_F'First) = ' ' then
         Put (Out_F, Img_F (Img_F'First + 1 .. Img_F'Last));
      else
         Put (Out_F, Img_F);
      end if;
   end Put_Float;

   --  ================= EN-TETE HTML + tableau de donnees =================
   procedure Write_Head is
   begin
      Put_Line (Out_F, "<!DOCTYPE html><html lang=""fr""><head><meta charset=""UTF-8"">");
      Put_Line (Out_F, "<title>radar_fw - Tracking 3D</title><style>");
      Put_Line (Out_F, "body{margin:0;background:#0a0f0d;color:#b9d8cc;font-family:monospace;overflow:hidden}");
      Put_Line (Out_F, "#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.7}");
      Put_Line (Out_F, "#info b{color:#34e29b}</style></head><body>");
      Put_Line (Out_F, "<div id=""info""></div>");
      Put_Line (Out_F, "<script src=""https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js""></script>");
      --  FRAMES : un tableau par tour ; chaque tour = la liste des pistes
      --  PERCUES (ce que le tracking a reellement suivi). Rien d'autre.
      Put (Out_F, "<script>const FRAMES=[");
   end Write_Head;

   --  ================= LE VISUALISEUR (rejeu du flux percu) =================
   procedure Write_Viewer is
   begin
      Put_Line (Out_F, "];");
      Put_Line (Out_F, "const info=document.getElementById('info');");
      Put_Line (Out_F, "const scene=new THREE.Scene();");
      Put_Line (Out_F, "const cam=new THREE.PerspectiveCamera(60,innerWidth/innerHeight,1,100000);");
      Put_Line (Out_F, "const rnd=new THREE.WebGLRenderer({antialias:true});");
      Put_Line (Out_F, "rnd.setSize(innerWidth,innerHeight);rnd.setClearColor(0x06100c);");
      Put_Line (Out_F, "document.body.appendChild(rnd.domElement);");
      --  Decor fixe : grille de sol (echelle) + marqueur du radar au centre.
      Put_Line (Out_F, "scene.add(new THREE.GridHelper(8000,16,0x1c3a2e,0x1c3a2e));");
      Put_Line (Out_F, "const radar=new THREE.Mesh(new THREE.SphereGeometry(90,16,16),new THREE.MeshBasicMaterial({color:0xff5d3b}));");
      Put_Line (Out_F, "scene.add(radar);");
      --  Groupe redessine a chaque tour (cibles, fleches, labels, trainees).
      Put_Line (Out_F, "const dyn=new THREE.Group();scene.add(dyn);");
      --  Monde (Z vers le haut) -> Three.js (Y vers le haut) : on echange Y/Z.
      Put_Line (Out_F, "function v3(p){return new THREE.Vector3(p.x,p.z,p.y);}");
      Put_Line (Out_F, "function distOf(p){return Math.round(Math.sqrt(p.x*p.x+p.y*p.y+p.z*p.z));}");
      --  Label texte = petit canvas transforme en sprite (reste autonome).
      Put_Line (Out_F, "function makeLabel(t){");
      Put_Line (Out_F, " const c=document.createElement('canvas');c.width=256;c.height=64;");
      Put_Line (Out_F, " const g=c.getContext('2d');g.font='26px monospace';g.fillStyle='#d8f5e8';g.textAlign='center';");
      Put_Line (Out_F, " g.fillText(t,128,40);");
      Put_Line (Out_F, " const s=new THREE.Sprite(new THREE.SpriteMaterial({map:new THREE.CanvasTexture(c),depthTest:false}));");
      Put_Line (Out_F, " s.scale.set(1000,250,1);return s;}");
      --  Vide le groupe dynamique et libere la memoire entre deux tours.
      Put_Line (Out_F, "function clearDyn(){");
      Put_Line (Out_F, " dyn.traverse(o=>{if(o!==dyn){if(o.geometry)o.geometry.dispose();if(o.material){if(o.material.map)o.material.map.dispose();o.material.dispose();}}});");
      Put_Line (Out_F, " while(dyn.children.length)dyn.remove(dyn.children[0]);}");
      --  Trainee : positions d'un meme ID sur les 8 derniers tours (max).
      Put_Line (Out_F, "function trailFor(id,t){");
      Put_Line (Out_F, " const pts=[],start=Math.max(0,t-7);");
      Put_Line (Out_F, " for(let f=start;f<=t;f++){const tk=FRAMES[f].find(o=>o.id===id);if(tk)pts.push(v3(tk));}");
      Put_Line (Out_F, " return pts;}");
      --  Dessine un tour : pour chaque piste percue, sphere + fleche + label.
      Put_Line (Out_F, "function showTurn(t){");
      Put_Line (Out_F, " clearDyn();const frame=FRAMES[t];");
      Put_Line (Out_F, " for(const tk of frame){");
      Put_Line (Out_F, "  const p=v3(tk);");
      Put_Line (Out_F, "  const s=new THREE.Mesh(new THREE.SphereGeometry(70,16,16),new THREE.MeshBasicMaterial({color:0x34e29b}));");
      Put_Line (Out_F, "  s.position.copy(p);dyn.add(s);");
      --  Fleche = direction du vecteur vitesse, longueur proportionnelle.
      Put_Line (Out_F, "  const vel=new THREE.Vector3(tk.vx,tk.vz,tk.vy),speed=vel.length();");
      Put_Line (Out_F, "  if(speed>1){const len=Math.min(2500,speed*5);dyn.add(new THREE.ArrowHelper(vel.clone().normalize(),p,len,0xffd23b,len*0.3,len*0.2));}");
      --  Label : identifiant de la piste + distance au radar.
      Put_Line (Out_F, "  const lab=makeLabel('#'+tk.id+'  '+distOf(tk)+'mm');lab.position.copy(p).add(new THREE.Vector3(0,200,0));dyn.add(lab);");
      Put_Line (Out_F, "  const tp=trailFor(tk.id,t);");
      Put_Line (Out_F, "  if(tp.length>1){dyn.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(tp),new THREE.LineBasicMaterial({color:0x1f7a5a})));}");
      Put_Line (Out_F, " }");
      Put_Line (Out_F, " info.innerHTML='<b>radar_fw - tracking percu</b><br>Tour '+(t+1)+' / '+FRAMES.length+'<br>Cibles suivies : '+frame.length;}");
      --  Etat du rejeu + controles souris (rotation / zoom).
      Put_Line (Out_F, "let turn=0,acc=0,last=performance.now();");
      Put_Line (Out_F, "let rotY=0.6,rotX=0.4,down=false,px=0,py=0,camDist=7000;");
      Put_Line (Out_F, "addEventListener('mousedown',e=>{down=true;px=e.clientX;py=e.clientY;});");
      Put_Line (Out_F, "addEventListener('mouseup',()=>down=false);");
      Put_Line (Out_F, "addEventListener('mousemove',e=>{if(!down)return;rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;px=e.clientX;py=e.clientY;});");
      Put_Line (Out_F, "addEventListener('wheel',e=>{camDist*=(1+e.deltaY*0.001);});");
      Put_Line (Out_F, "addEventListener('resize',()=>{cam.aspect=innerWidth/innerHeight;cam.updateProjectionMatrix();rnd.setSize(innerWidth,innerHeight);});");
      --  Boucle : rendu fluide chaque image, avancee d'un tour toutes les 800ms.
      Put_Line (Out_F, "function loop(now){");
      Put_Line (Out_F, " requestAnimationFrame(loop);");
      Put_Line (Out_F, " const dt=now-last;last=now;acc+=dt;");
      Put_Line (Out_F, " if(acc>800){acc=0;turn=(turn+1)%FRAMES.length;showTurn(turn);}");
      Put_Line (Out_F, " cam.position.x=Math.cos(rotY)*Math.cos(rotX)*camDist;");
      Put_Line (Out_F, " cam.position.z=Math.sin(rotY)*Math.cos(rotX)*camDist;");
      Put_Line (Out_F, " cam.position.y=Math.sin(rotX)*camDist;cam.lookAt(0,0,0);");
      Put_Line (Out_F, " rnd.render(scene,cam);}");
      Put_Line (Out_F, "showTurn(0);requestAnimationFrame(loop);");
      Put_Line (Out_F, "</script></body></html>");
   end Write_Viewer;

   --  ================= LE PIPELINE DE PERCEPTION =================
   procedure Process (Radar : in out Source'Class) is
      M       : Measurement;
      OK      : Boolean;
      F       : Frame;
      Last_Az : Float := 0.0;

      --  Fin d'un tour : regroupement -> tracking -> ecriture d'une frame.
      procedure End_Of_Turn is
         C : constant Frame := Cluster (F);
      begin
         Update (Trk, C);

         --  On serialise UNIQUEMENT les pistes percues (Id, pos, vitesse).
         Put (Out_F, "[");
         for I in Trk.Tracks'Range loop
            if Trk.Tracks (I).Active then
               declare
                  Tk : constant Track := Trk.Tracks (I);
               begin
                  Put (Out_F, "{id:");  Put (Out_F, Img (Tk.Id));
                  Put (Out_F, ",x:");   Put_Float (Tk.Pos.X);
                  Put (Out_F, ",y:");   Put_Float (Tk.Pos.Y);
                  Put (Out_F, ",z:");   Put_Float (Tk.Pos.Z);
                  Put (Out_F, ",vx:");  Put_Float (Tk.Velocity.X);
                  Put (Out_F, ",vy:");  Put_Float (Tk.Velocity.Y);
                  Put (Out_F, ",vz:");  Put_Float (Tk.Velocity.Z);
                  Put (Out_F, "},");
               end;
            end if;
         end loop;
         Put_Line (Out_F, "],");

         Turn_Count := Turn_Count + 1;
      end End_Of_Turn;

   begin
      Reset (F);
      while Radar.Has_More loop
         Radar.Next (M, OK);
         exit when not OK;

         --  L'azimut "recule" => le balayage a boucle => nouveau tour.
         if M.Azimuth < Last_Az - 1.0 then
            End_Of_Turn;
            Reset (F);
         end if;
         Last_Az := M.Azimuth;

         Add (F, M);
      end loop;

      End_Of_Turn;  --  dernier tour
   end Process;

begin
   Create (Out_F, Out_File, File_Name);
   Write_Head;
   Process (Src);
   Write_Viewer;
   Close (Out_F);

   Put_Line ("Genere " & File_Name & " (" & Img (Turn_Count) & " tours).");
end Radar_Fw;
