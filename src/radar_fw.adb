with Ada.Text_IO;  use Ada.Text_IO;
with Radar_Sweep;  use Radar_Sweep;

procedure Radar_Fw is

   --  Petite routine d'affichage pour un balayage donne.
   procedure Analyse (Label : String; S : Sweep) is
   begin
      Put_Line ("--- " & Label & " ---");
      if Has_Target (S) then
         Put_Line ("  Cible detectee.");
         Put_Line ("  Case  : " & Peak_Bin (S)'Image);
         Put_Line ("  Distance : " & Peak_Distance (S)'Image & " mm");
      else
         Put_Line ("  Aucune cible (bruit de fond seulement).");
      end if;
   end Analyse;

   --  Cas 1 : une vraie cible (pic net en case 64).
   With_Target    : Sweep := (others => 10);

   --  Cas 2 : que du bruit faible, sous le seuil de detection.
   Noise_Only     : constant Sweep := (others => 10);

begin
   With_Target (64) := 3_000;

   Analyse ("Cas 1 : avec cible", With_Target);
   Analyse ("Cas 2 : bruit seul", Noise_Only);
end Radar_Fw;