with Ada.Text_IO;   use Ada.Text_IO;
with Radar_Sweep;   use Radar_Sweep;
with Radar_Sim;     use Radar_Sim;

procedure Radar_Fw is

   Frames    : constant := 60;
   File_Name : constant String := "radar_view.html";

   Out_F : File_Type;
   S     : Sweep;

   --  Ecrit une valeur Amplitude sans l'espace de tete de 'Image.
   procedure Put_Amp (Data : Amplitude) is
      Img : constant String := Amplitude'Image (Data);
   begin
      Put (Out_F, Img (Img'First + 1 .. Img'Last));
   end Put_Amp;

   --  Ecrit un balayage en ligne JS : [v0,v1,...,v255]
   procedure Put_Sweep (Data : Sweep) is
   begin
      Put (Out_F, "[");
      for I in Bin_Index loop
         Put_Amp (Data (I));
         if I /= Bin_Index'Last then
            Put (Out_F, ",");
         end if;
      end loop;
      Put (Out_F, "]");
   end Put_Sweep;

begin
   Create (Out_F, Out_File, File_Name);

   --  ============ Partie 1 : en-tete HTML + CSS ============
   Put_Line (Out_F, "<!DOCTYPE html><html lang=""fr""><head><meta charset=""UTF-8"">");
   Put_Line (Out_F, "<title>radar_fw - Visualiseur</title><style>");
   Put_Line (Out_F, "body{margin:0;background:#0a0f0d;color:#b9d8cc;");
   Put_Line (Out_F, "font-family:Consolas,monospace;padding:24px}");
   Put_Line (Out_F, "h1{font-size:18px;margin:0 0 4px}.sub{color:#6f8c80;font-size:13px;margin-bottom:20px}");
   Put_Line (Out_F, ".wrap{display:flex;flex-wrap:wrap;gap:20px}");
   Put_Line (Out_F, ".panel{background:#0f1a16;border:1px solid #1c3a2e;border-radius:10px;padding:14px}");
   Put_Line (Out_F, ".panel h2{font-size:13px;margin:0 0 10px}");
   Put_Line (Out_F, "canvas{display:block;background:#06100c;border-radius:6px}");
   Put_Line (Out_F, ".controls{display:flex;align-items:center;gap:14px;margin:18px 0;flex-wrap:wrap}");
   Put_Line (Out_F, "button{background:#1d8f63;color:#04140d;border:none;padding:8px 16px;");
   Put_Line (Out_F, "border-radius:6px;font-weight:700;cursor:pointer;font-family:inherit}");
   Put_Line (Out_F, "button:hover{background:#34e29b}input[type=range]{accent-color:#34e29b}");
   Put_Line (Out_F, ".readout{font-size:13px}.readout b{color:#34e29b}.tv b{color:#ff5d3b}");
   Put_Line (Out_F, "</style></head><body>");
   Put_Line (Out_F, "<h1>radar_fw - Visualiseur de balayages</h1>");
   Put_Line (Out_F, "<div class=""sub"">A-scope &amp; cascade temporelle - donnees generees par le programme Ada</div>");
   Put_Line (Out_F, "<div class=""controls"">");
   Put_Line (Out_F, "<button id=""play"">Pause</button>");
   Put_Line (Out_F, "<label class=""readout"">Image <b id=""fn"">0</b> / <span id=""ft"">0</span></label>");
   Put_Line (Out_F, "<input type=""range"" id=""sc"" min=""0"" max=""0"" value=""0"" style=""width:260px"">");
   Put_Line (Out_F, "<label class=""readout tv"">Cible : <b id=""tg"">-</b></label></div>");
   Put_Line (Out_F, "<div class=""wrap"">");
   Put_Line (Out_F, "<div class=""panel""><h2>A-scope - balayage courant</h2>");
   Put_Line (Out_F, "<canvas id=""a"" width=""560"" height=""280""></canvas></div>");
   Put_Line (Out_F, "<div class=""panel""><h2>Cascade - temps (haut = recent)</h2>");
   Put_Line (Out_F, "<canvas id=""w"" width=""280"" height=""280""></canvas></div></div>");

   --  ============ Partie 2 : les donnees radar ============
   Put (Out_F, "<script>const FRAMES=[");
   for F in 1 .. Frames loop
      declare
         Moving_Pos : constant Bin_Index :=
           Bin_Index (Integer'Max (10, 250 - (F - 1) * 4));
         Scene : constant Target_List :=
           (1 => (Position => 180,        Strength => 2_200),
            2 => (Position => Moving_Pos, Strength => 3_500));
      begin
         S := Generate (Scene, Noise_Level => 500);
         Put_Sweep (S);
         if F /= Frames then
            Put (Out_F, ",");
         end if;
      end;
   end loop;
   Put_Line (Out_F, "];");

   --  ============ Partie 3 : le code d'affichage JS ============
   Put_Line (Out_F, "const BINS=256,MAX=4095,THR=100,MM=20000/BINS;");
   Put_Line (Out_F, "let cur=0,playing=true,last=0;");
   Put_Line (Out_F, "const a=document.getElementById('a'),ax=a.getContext('2d');");
   Put_Line (Out_F, "const w=document.getElementById('w'),wx=w.getContext('2d');");
   Put_Line (Out_F, "const pb=document.getElementById('play'),sc=document.getElementById('sc');");
   Put_Line (Out_F, "const fn=document.getElementById('fn'),ft=document.getElementById('ft'),tg=document.getElementById('tg');");
   Put_Line (Out_F, "ft.textContent=FRAMES.length;sc.max=FRAMES.length-1;");
   Put_Line (Out_F, "function peak(s){let b=0;for(let i=1;i<s.length;i++)if(s[i]>s[b])b=i;return b;}");
   Put_Line (Out_F, "function drawA(s){const W=a.width,H=a.height,p=24;ax.clearRect(0,0,W,H);");
   Put_Line (Out_F, "ax.strokeStyle='#1c3a2e';ax.lineWidth=1;ax.beginPath();");
   Put_Line (Out_F, "for(let g=0;g<=4;g++){const y=p+(H-2*p)*g/4;ax.moveTo(p,y);ax.lineTo(W-p,y);}ax.stroke();");
   Put_Line (Out_F, "const yt=p+(H-2*p)*(1-THR/MAX);ax.strokeStyle='#ff5d3b';ax.setLineDash([5,5]);");
   Put_Line (Out_F, "ax.beginPath();ax.moveTo(p,yt);ax.lineTo(W-p,yt);ax.stroke();ax.setLineDash([]);");
   Put_Line (Out_F, "const pk=peak(s);ax.strokeStyle='#34e29b';ax.lineWidth=1.5;ax.beginPath();");
   Put_Line (Out_F, "for(let i=0;i<s.length;i++){const x=p+(W-2*p)*i/(s.length-1),y=p+(H-2*p)*(1-s[i]/MAX);");
   Put_Line (Out_F, "if(i===0)ax.moveTo(x,y);else ax.lineTo(x,y);}ax.stroke();");
   Put_Line (Out_F, "const xp=p+(W-2*p)*pk/(s.length-1),yp=p+(H-2*p)*(1-s[pk]/MAX);");
   Put_Line (Out_F, "ax.fillStyle='#ff5d3b';ax.beginPath();ax.arc(xp,yp,4,0,6.28);ax.fill();");
   Put_Line (Out_F, "if(s[pk]>=THR){tg.textContent='case '+pk+' - '+Math.round(pk*MM)+' mm';}else{tg.textContent='aucune cible';}}");
   Put_Line (Out_F, "function drawW(up){const W=w.width,H=w.height;wx.clearRect(0,0,W,H);");
   Put_Line (Out_F, "const n=FRAMES.length,rh=H/n;for(let f=0;f<=up;f++){const s=FRAMES[f],y=H-(f+1)*rh;");
   Put_Line (Out_F, "for(let i=0;i<BINS;i++){const v=s[i]/MAX;if(v<0.02)continue;const x=W*i/BINS;");
   Put_Line (Out_F, "const g=Math.round(120+135*v),r=v>0.3?Math.round(255*v):0;");
   Put_Line (Out_F, "wx.fillStyle='rgb('+r+','+g+','+Math.round(80*(1-v))+')';");
   Put_Line (Out_F, "wx.fillRect(x,y,Math.max(1,W/BINS),Math.max(1,rh));}}}");
   Put_Line (Out_F, "function render(){drawA(FRAMES[cur]);drawW(cur);fn.textContent=cur+1;sc.value=cur;}");
   Put_Line (Out_F, "function loop(t){if(playing&&t-last>120){cur=(cur+1)%FRAMES.length;render();last=t;}requestAnimationFrame(loop);}");
   Put_Line (Out_F, "pb.onclick=()=>{playing=!playing;pb.textContent=playing?'Pause':'Lecture';};");
   Put_Line (Out_F, "sc.oninput=()=>{playing=false;pb.textContent='Lecture';cur=Number(sc.value);render();};");
   Put_Line (Out_F, "requestAnimationFrame(loop);</script></body></html>");

   Close (Out_F);
   Put_Line ("Genere " & File_Name & " (" & Frames'Image & " balayages). Double-clique-le !");
end Radar_Fw;
