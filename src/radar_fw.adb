with Ada.Text_IO;  use Ada.Text_IO;
with Radar_Sweep;  use Radar_Sweep;

procedure Radar_Fw is

   --  Un seul objet, mais son echo s'etale sur 3 cases voisines (100,101,102).
   S : Sweep := (others => 10);

   D : Detection;
begin
   S (100) := 1_200;
   S (101) := 2_500;   --  sommet de l'echo
   S (102) := 1_400;

   D := Detect_Clustered (S);

   Put_Line ("Avec Detect_Clustered (regroupement) :");
   Put_Line ("  Cibles detectees :" & D.Count'Image & "  (on en voudrait 1 !)");
   for I in 1 .. D.Count loop
      Put_Line ("    case" & D.Targets (I)'Image);
   end loop;
end Radar_Fw;