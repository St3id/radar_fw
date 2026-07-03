with Radar_Geometry;  use Radar_Geometry;

package Radar_Cloud is

   --  Conteneur de nuage de points 3D, rempli par le mode cartographie.
   --  (L'ancien Scan_Room calculait lui-meme la geometrie de la piece,
   --  en court-circuitant la source radar ; desormais les murs vivent
   --  dans Radar_World et les points arrivent par la MEME chaine de
   --  detection que le mode surveillance.)

   --  Taille maximale du nuage.
   Max_Points : constant := 8_192;

   subtype Point_Count is Natural range 0 .. Max_Points;

   --  D'abord on NOMME le type tableau (Ada interdit un tableau anonyme
   --  directement dans un record).
   type Point_Array is array (1 .. Max_Points) of Point_3D;

   --  Le nuage : un tableau de points + combien sont reellement utilises.
   type Point_Cloud is record
      Points : Point_Array;
      Count  : Point_Count;
   end record;

   --  Un nuage vide, pret a etre rempli.
   function Empty_Cloud return Point_Cloud;

   --  Ajoute un point au nuage. Si le nuage est plein, le point est
   --  ignore (saturation silencieuse, jamais de debordement).
   procedure Append (C : in out Point_Cloud; P : Point_3D);

end Radar_Cloud;
