with Ada.Text_IO;     use Ada.Text_IO;
with Radar_Geometry;  use Radar_Geometry;

procedure Radar_Fw is

   procedure Test (Label : String; P : Point_3D) is
      R : constant Polar := To_Polar (P);
   begin
      Put_Line (Label
                & " -> distance=" & Integer'Image (Integer (R.Distance))
                & "  azimut=" & Integer'Image (Integer (R.Azimuth))
                & "  elevation=" & Integer'Image (Integer (R.Elevation)));
   end Test;

begin
   --  Point droit devant (sur l'axe X) : azimut 0, elevation 0.
   Test ("Droit devant (1000,0,0)   ", (1000.0, 0.0, 0.0));

   --  Point a gauche (sur l'axe Y) : azimut 90.
   Test ("A gauche     (0,1000,0)   ", (0.0, 1000.0, 0.0));

   --  Point droit en haut (sur l'axe Z) : elevation 90.
   Test ("En haut      (0,0,1000)   ", (0.0, 0.0, 1000.0));

   --  Point en diagonale a 45 : azimut 45, distance ~1414.
   Test ("Diagonale    (1000,1000,0)", (1000.0, 1000.0, 0.0));
end Radar_Fw;