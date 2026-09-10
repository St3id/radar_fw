with Radar_Sweep;  use Radar_Sweep;

--  Radar_Source : l'interface abstraite par laquelle toute source de
--  mesures entre dans le systeme, simulateur comme capteur reel.
--
--  Aucun mode d'exploitation ne parle a un materiel en direct : tous
--  passent par ce type, et c'est ce qui rend le remplacement de la source
--  possible sans toucher au reste du programme.

package Radar_Source is

   --  Une mesure brute : un balayage capte dans une direction donnee.
   --  (azimut + elevation = ou pointait le radar ; Data = les echos recus).
   type Measurement is record
      Azimuth   : Float;     --  direction horizontale, en degres
      Elevation : Float;     --  direction verticale, en degres
      Data      : Sweep;     --  les amplitudes recues le long de cette ligne
   end record;

   --  ----- Le contrat -----
   --  "Radar_Source" est une interface : un fournisseur de mesures radar.
   --  Toute source concrete (simulee ou materielle) devra implementer Next.
   type Source is interface;

   --  Fournit la prochaine mesure. Available = False si plus rien a lire.
   procedure Next
     (Self        : in out Source;
      Result      : out Measurement;
      Available   : out Boolean) is abstract;

   --  Indique si la source a encore des mesures a fournir.
   function Has_More (Self : Source) return Boolean is abstract;

   --  Combien de mesures composent un tour complet de balayage (tous
   --  les azimuts x toutes les elevations). Fait partie du contrat :
   --  les modes qui cadencent un balayage (surveillance, cartographie
   --  progressive) doivent pouvoir rythmer les tours et afficher une
   --  progression sans savoir quelle source ils pilotent. Sans cela,
   --  ils sont obliges de nommer le type concret - et l'interface ne
   --  sert plus a rien.
   function Per_Turn (Self : Source) return Positive is abstract;

end Radar_Source;
