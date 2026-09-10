with Radar_Geometry;  use Radar_Geometry;

--  Radar_Cloud : le nuage de points 3D accumule par la cartographie.
--
--  Le nuage ne calcule aucune geometrie de piece pour son propre compte :
--  les murs appartiennent au monde simule (Radar_World) et les points
--  lui parviennent par la meme chaine de detection que le mode
--  surveillance. Court-circuiter la source pour dessiner une piece
--  connue d'avance donnerait une carte qui ne prouve rien.
--
--  Memoire statique bornee : jamais d'allocation, jamais de debordement.

package Radar_Cloud is

   --  Taille maximale du nuage.
   Max_Points : constant := 8_192;

   subtype Point_Count is Natural range 0 .. Max_Points;

   --  Le type tableau est nomme : Ada interdit un tableau anonyme
   --  directement dans un record.
   type Point_Array is array (1 .. Max_Points) of Point_3D;

   --  Le nuage : un tableau de points + combien sont reellement utilises.
   type Point_Cloud is record
      Points : Point_Array;
      Count  : Point_Count;
   end record;

   --  Un nuage vide, pret a etre rempli.
   function Empty_Cloud return Point_Cloud;

   --  Ajoute un point au nuage. Le nuage plein, le point est ignore :
   --  la borne protege la memoire, mais la perte n'est pas signalee, et
   --  un nuage tronque ressemble alors a une piece plus petite.
   procedure Append (C : in out Point_Cloud; P : Point_3D);

end Radar_Cloud;
