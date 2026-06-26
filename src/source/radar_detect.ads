with Radar_Geometry;  use Radar_Geometry;
with Radar_Source;    use Radar_Source;

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
   type Frame is record
      Items : Detection_List;
      Count : Detection_Count;
   end record;

   --  Ajoute une detection a la frame (si une mesure contient une cible).
   --  Calcule la position 3D a partir de la direction et de la distance.
   procedure Add (F : in out Frame; M : Measurement);

   --  Remet la frame a zero (debut d'un nouveau tour).
   procedure Reset (F : in out Frame);

end Radar_Detect;