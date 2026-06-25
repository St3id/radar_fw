with Ada.Text_IO;  use Ada.Text_IO;
with Radar_Sweep;  use Radar_Sweep;

procedure Radar_Fw is

   --  On fabrique un faux balayage : du bruit faible partout,
   --  sauf un pic net dans une case choisie (la "cible").
   Test_Sweep   : Sweep := (others => 10);   --  bruit de fond
   Target_Bin   : constant Bin_Index := 64;  --  cible attendue ici

   Found_Bin    : Bin_Index;
   Found_Dist   : Millimeters;
begin
   --  On place le pic.
   Test_Sweep (Target_Bin) := 3_000;

   --  On interroge notre paquet.
   Found_Bin  := Peak_Bin (Test_Sweep);
   Found_Dist := Peak_Distance (Test_Sweep);

   --  On affiche les resultats.
   Put_Line ("Case attendue : " & Target_Bin'Image);
   Put_Line ("Case trouvee  : " & Found_Bin'Image);
   Put_Line ("Distance      : " & Found_Dist'Image & " mm");

   --  Verification automatique.
   if Found_Bin = Target_Bin then
      Put_Line ("==> OK : pic detecte au bon endroit.");
   else
      Put_Line ("==> ERREUR : mauvaise case.");
   end if;
end Radar_Fw;