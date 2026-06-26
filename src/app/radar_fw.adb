with Ada.Text_IO;        use Ada.Text_IO;
with Radar_Source;       use Radar_Source;
with Radar_Sim_Source;   use Radar_Sim_Source;
with Radar_Detect;       use Radar_Detect;
with Radar_Track;        use Radar_Track;

--  Ce programme GENERE du HTML : certaines lignes (script Three.js embarque)
--  depassent volontairement la limite de 79 colonnes. On releve donc la
--  limite de longueur de ligne pour CE seul fichier, sans toucher aux autres
--  regles de style ni aux autres fichiers.
pragma Style_Checks ("M300");

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
      Put_Line (Out_F, "#info{position:absolute;top:12px;left:12px;font-size:13px;line-height:1.7;background:rgba(6,16,12,.6);padding:10px 12px;border:1px solid #1c3a2e;border-radius:6px;max-width:300px}");
      Put_Line (Out_F, "#info b{color:#34e29b}");
      Put_Line (Out_F, ".ctl{margin-top:8px}.ctl input[type=range]{vertical-align:middle;width:120px}");
      Put_Line (Out_F, ".note{margin-top:8px;color:#6f8c80;font-size:11px;line-height:1.4}</style></head><body>");
      --  Panneau : titre, statut (mis a jour a part), controles, legende.
      Put_Line (Out_F, "<div id=""info"">");
      Put_Line (Out_F, "<b>radar_fw - tracking percu</b>");
      Put_Line (Out_F, "<div id=""status""></div>");
      Put_Line (Out_F, "<label class=""ctl""><input type=""checkbox"" id=""smooth"" checked> Lissage (interpolation)</label>");
      Put_Line (Out_F, "<div class=""ctl"">Vitesse <input type=""range"" id=""speed"" min=""100"" max=""1500"" step=""50"" value=""800""> <span id=""speedval"">800</span> ms/tour</div>");
      Put_Line (Out_F, "<div class=""note"">Decoche = positions reellement mesurees, tour par tour (la verite de la perception, saccadee).<br>Coche = interpolation visuelle entre deux mesures (positions intermediaires inventees).</div>");
      Put_Line (Out_F, "</div>");
      Put_Line (Out_F, "<script src=""https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js""></script>");
      --  FRAMES : un tableau par tour ; chaque tour = la liste des pistes
      --  PERCUES (ce que le tracking a reellement suivi). Rien d'autre.
      Put (Out_F, "<script>const FRAMES=[");
   end Write_Head;

   --  ================= LE VISUALISEUR (rejeu du flux percu) =================
   procedure Write_Viewer is
   begin
      Put_Line (Out_F, "];");
      --  Recuperation des controles du panneau (case lissage + curseur).
      Put_Line (Out_F, "const status=document.getElementById('status');");
      Put_Line (Out_F, "const smoothBox=document.getElementById('smooth');");
      Put_Line (Out_F, "const speedRange=document.getElementById('speed');");
      Put_Line (Out_F, "const speedVal=document.getElementById('speedval');");
      Put_Line (Out_F, "let TURN_MS=+speedRange.value;");
      Put_Line (Out_F, "speedRange.addEventListener('input',()=>{TURN_MS=+speedRange.value;speedVal.textContent=TURN_MS;});");
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
      Put_Line (Out_F, "function lerp(a,b,k){return a+(b-a)*k;}");
      --  Dessine la scene a l'instant 'a' (0..1) DANS le tour courant :
      --  a=0 -> position du tour precedent ; a=1 -> position du tour courant.
      --  Les positions intermediaires (0<a<1) sont interpolees = inventees.
      Put_Line (Out_F, "function drawScene(a){");
      Put_Line (Out_F, " clearDyn();");
      Put_Line (Out_F, " const toF=FRAMES[turn],fromF=FRAMES[(turn===0)?0:turn-1];");
      Put_Line (Out_F, " for(const tk of toF){");
      Put_Line (Out_F, "  const prev=fromF.find(o=>o.id===tk.id);");
      Put_Line (Out_F, "  const ip=prev?{x:lerp(prev.x,tk.x,a),y:lerp(prev.y,tk.y,a),z:lerp(prev.z,tk.z,a)}:tk;");
      Put_Line (Out_F, "  const p=v3(ip);");
      Put_Line (Out_F, "  const s=new THREE.Mesh(new THREE.SphereGeometry(70,16,16),new THREE.MeshBasicMaterial({color:0x34e29b}));");
      Put_Line (Out_F, "  s.position.copy(p);dyn.add(s);");
      --  Fleche = direction du vecteur vitesse percu, longueur proportionnelle.
      Put_Line (Out_F, "  const vel=new THREE.Vector3(tk.vx,tk.vz,tk.vy),speed=vel.length();");
      Put_Line (Out_F, "  if(speed>1){const len=Math.min(2500,speed*5);dyn.add(new THREE.ArrowHelper(vel.clone().normalize(),p,len,0xffd23b,len*0.3,len*0.2));}");
      --  Label : identifiant + distance au radar (a la position affichee).
      Put_Line (Out_F, "  const lab=makeLabel('#'+tk.id+'  '+distOf(ip)+'mm');lab.position.copy(p).add(new THREE.Vector3(0,200,0));dyn.add(lab);");
      --  Trainee : positions REELLES passees (max 7) + la position courante.
      Put_Line (Out_F, "  const tp=[],start=Math.max(0,turn-7);");
      Put_Line (Out_F, "  for(let f=start;f<turn;f++){const o=FRAMES[f].find(x=>x.id===tk.id);if(o)tp.push(v3(o));}");
      Put_Line (Out_F, "  tp.push(p);");
      Put_Line (Out_F, "  if(tp.length>1){dyn.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(tp),new THREE.LineBasicMaterial({color:0x1f7a5a})));}");
      Put_Line (Out_F, " }");
      Put_Line (Out_F, " status.innerHTML='Tour '+(turn+1)+' / '+FRAMES.length+'<br>Cibles suivies : '+toF.length;}");
      --  Etat du rejeu + controles souris (rotation / zoom).
      Put_Line (Out_F, "let turn=0,acc=0,last=performance.now();");
      Put_Line (Out_F, "let rotY=0.6,rotX=0.4,down=false,px=0,py=0,camDist=7000;");
      Put_Line (Out_F, "addEventListener('mousedown',e=>{down=true;px=e.clientX;py=e.clientY;});");
      Put_Line (Out_F, "addEventListener('mouseup',()=>down=false);");
      Put_Line (Out_F, "addEventListener('mousemove',e=>{if(!down)return;rotY+=(e.clientX-px)*0.005;rotX+=(e.clientY-py)*0.005;px=e.clientX;py=e.clientY;});");
      Put_Line (Out_F, "addEventListener('wheel',e=>{camDist*=(1+e.deltaY*0.001);});");
      Put_Line (Out_F, "addEventListener('resize',()=>{cam.aspect=innerWidth/innerHeight;cam.updateProjectionMatrix();rnd.setSize(innerWidth,innerHeight);});");
      --  Boucle : on avance d'un tour toutes les TURN_MS ms (curseur Vitesse).
      --  'a' = progression dans le tour ; si lissage decoche, a=1 => saut net
      --  (positions brutes reellement mesurees, comportement saccade).
      Put_Line (Out_F, "function loop(now){");
      Put_Line (Out_F, " requestAnimationFrame(loop);");
      Put_Line (Out_F, " const dt=now-last;last=now;acc+=dt;");
      Put_Line (Out_F, " if(acc>=TURN_MS){acc-=TURN_MS;turn=(turn+1)%FRAMES.length;}");
      Put_Line (Out_F, " const a=smoothBox.checked?Math.min(1,acc/TURN_MS):1;");
      Put_Line (Out_F, " drawScene(a);");
      Put_Line (Out_F, " cam.position.x=Math.cos(rotY)*Math.cos(rotX)*camDist;");
      Put_Line (Out_F, " cam.position.z=Math.sin(rotY)*Math.cos(rotX)*camDist;");
      Put_Line (Out_F, " cam.position.y=Math.sin(rotX)*camDist;cam.lookAt(0,0,0);");
      Put_Line (Out_F, " rnd.render(scene,cam);}");
      Put_Line (Out_F, "requestAnimationFrame(loop);");
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
