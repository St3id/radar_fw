with Radar_Geometry;  use Radar_Geometry;
with Radar_Source;    use Radar_Source;

--  Radar_Detect : le passage des cibles d'un balayage aux detections 3D
--  d'un tour complet, puis leur regroupement spatial.
--
--  Un meme objet reel est vu par plusieurs directions de balayage voisines
--  et produit donc plusieurs detections ; le regroupement les ramene a une
--  cible unique avant que le pistage n'entre en jeu.

package Radar_Detect is

   --  Une detection 3D : la position dans l'espace d'un objet vu ce tour.
   type Detection_3D is record
      Pos      : Point_3D;   --  position cartesienne (mm)
      Distance : Float;      --  distance radar -> objet (mm)
   end record;

   --  Nombre maximum de detections retenues par tour.
   Max_Detections : constant := 32;

   subtype Detection_Count is Natural range 0 .. Max_Detections;

   type Detection_List is array (1 .. Max_Detections) of Detection_3D;

   --  Le resultat d'un tour : les objets vus + leur nombre.
   --  Le resultat d un tour : les objets vus, leur nombre, et QUAND le
   --  tour s est acheve. L horodatage voyage avec la frame jusqu au
   --  pistage : c est lui qui donne le dt entre deux regards, et donc
   --  des vitesses en mm/s au lieu de mm/tour.
   type Frame is record
      Items : Detection_List;
      Count : Detection_Count;
      Stamp : Time_Ms := 0;
   end record;

   --  Ajoute une detection a la frame (si une mesure contient une cible).
   --  Calcule la position 3D a partir de la direction et de la distance.
   procedure Add (F : in out Frame; M : Measurement);

   --  Remet la frame a zero (debut d'un nouveau tour).
   procedure Reset (F : in out Frame);

   --  Rayon de regroupement : deux detections a moins de cette distance
   --  (en mm) sont considerees comme le meme objet reel.
   --
   --  600 mm et pas moins, parce qu'une cible etendue (reflecteurs a
   --  +/-150 mm) vue par une grille d'elevation a pas de 10 degres peut
   --  voir ses echos "claquer" sur deux lignes d'elevation voisines :
   --  a 3 m, cela ecarte deux detections du meme objet d'environ
   --  3000 x sin(10 deg) = 520 mm. Revers assume : deux objets reels a
   --  moins de 600 mm fusionnent - c'est la limite de resolution reelle
   --  du capteur simule.
   Cluster_Radius : constant Float := 600.0;

   --  Regroupe les detections proches d'une frame en cibles uniques.
   --  Renvoie une nouvelle frame ou chaque objet reel n'apparait qu'une fois
   --  (a la position moyenne de ses detections).
   function Cluster (F : Frame) return Frame;

end Radar_Detect;
