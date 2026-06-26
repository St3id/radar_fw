with Radar_Geometry;  use Radar_Geometry;
with Radar_Detect;    use Radar_Detect;

package Radar_Track is

   --  Une PISTE : un objet suivi dans le temps.
   type Track is record
      Id       : Natural := 0;        --  identifiant stable (0 = libre)
      Pos      : Point_3D;            --  position actuelle
      Velocity : Point_3D;           --  vecteur vitesse (deplacement/tour)
      Missing  : Natural := 0;        --  nb de tours sans re-detection
      Active   : Boolean := False;    --  cette piste est-elle utilisee ?
   end record;

   Max_Tracks : constant := 16;

   type Track_Array is array (1 .. Max_Tracks) of Track;

   --  L'ensemble des pistes suivies + le prochain ID a attribuer.
   type Tracker is record
      Tracks  : Track_Array;
      Next_Id : Positive := 1;
   end record;

   --  Met a jour les pistes avec les cibles d'un nouveau tour (frame
   --  deja regroupee). Associe par proximite, calcule les vitesses,
   --  cree les nouvelles pistes, retire celles perdues trop longtemps.
   procedure Update (T : in out Tracker; F : Frame);

end Radar_Track;