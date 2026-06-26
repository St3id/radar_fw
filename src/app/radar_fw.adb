with Ada.Text_IO;    use Ada.Text_IO;
with Radar_World;    use Radar_World;

procedure Radar_Fw is

   W : World := Initial_World;

   --  Affiche l'etat du monde a un instant donne.
   procedure Show (Step_No : Natural) is
   begin
      Put_Line ("=== Pas" & Step_No'Image & " ===");
      for I in 1 .. W.Count loop
         declare
            O : constant Object := W.Objects (I);
         begin
            Put_Line ("  Objet" & O.Id'Image
                      & " : X=" & Integer'Image (Integer (O.X))
                      & " Y=" & Integer'Image (Integer (O.Y))
                      & " Z=" & Integer'Image (Integer (O.Z)));
         end;
      end loop;
   end Show;

begin
   --  On affiche l'etat initial, puis on avance de 5 pas.
   Show (0);
   for N in 1 .. 5 loop
      Step (W);
      Show (N);
   end loop;
end Radar_Fw;