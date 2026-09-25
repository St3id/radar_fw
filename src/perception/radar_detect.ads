with Radar_Geometry;  use Radar_Geometry;
with Radar_Source;    use Radar_Source;
with Radar_Sweep;
--  "use type" et non "use" : on veut seulement le "+" de Bin_Index pour
--  calculer Blind_Bins + 1, pas importer tout Radar_Sweep dans la
--  visibilite des clients (son type Detection y cotoierait Detection_3D).
use type Radar_Sweep.Bin_Index;

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
   --
   --  32 suffit pour la SURVEILLANCE : sur la grille de veille (120 x 7),
   --  le decor est soustrait par la carte de clutter et il ne reste que
   --  les mobiles - une poignee d echos par tour.
   --
   --  Ce n est en revanche PAS une structure de cartographie. Un tour fin
   --  (180 x 24) produit des milliers de points et deborderait cette
   --  borne cent fois. C est pourquoi les modes map et scan accumulent
   --  dans Radar_Cloud et ne passent pas par Frame.
   --
   --  Au-dela de la borne, les detections suivantes sont jetees sans
   --  aucun signalement.
   Max_Detections : constant := 32;

   subtype Detection_Count is Natural range 0 .. Max_Detections;

   type Detection_List is array (1 .. Max_Detections) of Detection_3D;

   --  Le resultat d un tour : les objets vus, leur nombre, et QUAND le
   --  tour s est acheve. L horodatage voyage avec la frame jusqu au
   --  pistage : c est lui qui donne le dt entre deux regards, et donc
   --  des vitesses en mm/s au lieu de mm/tour.
   --
   --  Min_Range dit jusqu ou le capteur etait AVEUGLE pendant ce tour :
   --  en deca de cette distance (mm), une absence d echo ne prouve pas
   --  qu il n y a rien. Le pistage en a besoin pour ne pas enterrer une
   --  piste qui traverse la zone aveugle. C est un champ de la frame et
   --  non une constante du pistage, parce que chaque capteur a la sienne.
   --  0.0 = le capteur voit tout (valeur sure : sans elle, le pistage
   --  se comporte exactement comme avant).
   type Frame is record
      Items     : Detection_List;
      Count     : Detection_Count;
      Stamp     : Time_Ms := 0;
      Min_Range : Float   := 0.0;
   end record;

   --  Zone aveugle de la chaine a profils : Detect_Adaptive ne rapporte
   --  jamais les Blind_Bins premieres cases, la premiere case visible
   --  commence donc a Bin_Distance (Blind_Bins + 1) = 625 mm. Derivee du
   --  coeur prouve plutot que recopiee : changer Blind_Bins la suit.
   Profile_Min_Range : constant Float :=
     Float (Radar_Sweep.Bin_Distance (Radar_Sweep.Blind_Bins + 1));

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
   --  moins de 600 mm fusionnent. Ce rayon regle le regroupement du
   --  simulateur ; il ne represente pas la resolution physique d'un radar.
   Cluster_Radius : constant Float := 600.0;

   --  Regroupe les detections proches d'une frame en cibles uniques.
   --  Renvoie une nouvelle frame ou chaque objet reel n'apparait qu'une fois
   --  (a la position moyenne de ses detections).
   function Cluster (F : Frame) return Frame;

end Radar_Detect;
