with Radar_Geometry;  use Radar_Geometry;

package Radar_Cloud is

   --  Nombre de directions balayees.
   Azimuth_Steps   : constant := 60;   --  60 pas horizontaux
   Elevation_Steps : constant := 20;   --  20 pas verticaux

   --  Taille maximale du nuage : un point par direction.
   Max_Points : constant := Azimuth_Steps * Elevation_Steps;

   subtype Point_Count is Natural range 0 .. Max_Points;

--  D'abord on NOMME le type tableau (Ada interdit un tableau anonyme
   --  directement dans un record).
   type Point_Array is array (1 .. Max_Points) of Point_3D;

   --  Le nuage : un tableau de points + combien sont reellement utilises.
   type Point_Cloud is record
      Points : Point_Array;
      Count  : Point_Count;
   end record;

   --  Simule un scan complet d'une "piece" et renvoie le nuage de points.
   function Scan_Room return Point_Cloud;

end Radar_Cloud;