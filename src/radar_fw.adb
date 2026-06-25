with Ada.Text_IO;       use Ada.Text_IO;
with Radar_Geometry;    use Radar_Geometry;

procedure Radar_Fw is

   --  Petit affichage d'un point 3D.
   procedure Show (Label : String; P : Point_3D) is
   begin
      Put_Line (Label & " -> X=" & Integer'Image (Integer (P.X))
                & "  Y=" & Integer'Image (Integer (P.Y))
                & "  Z=" & Integer'Image (Integer (P.Z)));
   end Show;

begin
   --  Cas 1 : 1000 mm droit devant (azimut 0, elevation 0).
   --  Attendu : X=1000, Y=0, Z=0.
   Show ("Droit devant   ", To_Point (1000.0, 0.0, 0.0));

   --  Cas 2 : 1000 mm a gauche (azimut 90).
   --  Attendu : X=0, Y=1000, Z=0.
   Show ("A gauche (90)  ", To_Point (1000.0, 90.0, 0.0));

   --  Cas 3 : 1000 mm droit en haut (elevation 90).
   --  Attendu : X=0, Y=0, Z=1000.
   Show ("En haut (90)   ", To_Point (1000.0, 0.0, 90.0));

   --  Cas 4 : 1000 mm a 45 d'azimut (elevation 0).
   --  Attendu : X~707, Y~707, Z=0.
   Show ("Diagonale (45) ", To_Point (1000.0, 45.0, 0.0));
end Radar_Fw;