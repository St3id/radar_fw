with Ada.Text_IO;  use Ada.Text_IO;
with Radar_Sweep;  use Radar_Sweep;

procedure Radar_Fw is

   --  On fabrique un balayage avec TROIS cibles a des positions connues.
   S : Sweep := (others => 10);   --  bruit faible partout

   D : Detection;
begin
   --  Trois echos au-dessus du seuil (100).
   S (40)  := 1_500;
   S (128) := 2_800;
   S (200) := 900;

   D := Detect_All (S);

   Put_Line ("Nombre de cibles detectees :" & D.Count'Image);
   for I in 1 .. D.Count loop
      declare
         Pos  : constant Bin_Index := D.Targets (I);
         Dist : constant Millimeters :=
           Millimeters ((Integer (Pos) - 1) * (Max_Range_Mm / Sweep_Length));
      begin
         Put_Line ("  Cible" & I'Image & " : case" & Pos'Image
                   & " a" & Dist'Image & " mm");
      end;
   end loop;
end Radar_Fw;