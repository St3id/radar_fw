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
   --
   --  8192 : la carte progressive cumule un passage grossier et un passage
   --  fin, soit environ 4800 points dans la scene simulee actuelle. La
   --  borne laisse une marge, et Dropped signale tout depassement.
   --
   --  Ce que ca coute : 8192 x 3 Float = 96 Ko. C est la raison pour
   --  laquelle ce paquet ne vit PAS dans src/core et ne part pas
   --  sur la carte - le STM32G474 n a que 128 Ko de RAM au total.
   --  L alternative ecartee est le tableau dynamique : interdit ici,
   --  la memoire doit etre connue a la compilation.
   Max_Points : constant := 8_192;

   subtype Point_Count is Natural range 0 .. Max_Points;

   --  Le type tableau est nomme : Ada interdit un tableau anonyme
   --  directement dans un record.
   type Point_Array is array (1 .. Max_Points) of Point_3D;

   --  Le nuage : les points conserves et le nombre de points rejetes
   --  une fois la capacite atteinte. Un nuage tronque doit etre visible.
   type Point_Cloud is record
      Points : Point_Array;
      Count  : Point_Count;
      Dropped : Natural := 0;
   end record;

   --  Un nuage vide, pret a etre rempli.
   function Empty_Cloud return Point_Cloud;

   --  Ajoute un point au nuage. Si la capacite est atteinte, le point
   --  est ignore et Dropped augmente : la memoire reste bornee et la
   --  perte devient detectable par l'appelant.
   procedure Append (C : in out Point_Cloud; P : Point_3D);

end Radar_Cloud;
