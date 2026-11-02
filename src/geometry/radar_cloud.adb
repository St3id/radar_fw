--  Corps de Radar_Cloud. Deux operations seulement, sans etat cache :
--  le nuage est une donnee que l'appelant transporte.

package body Radar_Cloud is

   -----------------
   -- Empty_Cloud --
   -----------------

   function Empty_Cloud return Point_Cloud is
   begin
      return (Points => (others => (0.0, 0.0, 0.0)),
              Count  => 0,
              Dropped => 0);
   end Empty_Cloud;

   ------------
   -- Append --
   ------------

   procedure Append (C : in out Point_Cloud; P : Point_3D) is
   begin
      if C.Count < Max_Points then
         C.Count := C.Count + 1;
         C.Points (C.Count) := P;
      elsif C.Dropped < Natural'Last then
         C.Dropped := C.Dropped + 1;
      end if;
   end Append;

end Radar_Cloud;
