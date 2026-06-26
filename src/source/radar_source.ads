with Radar_Sweep;  use Radar_Sweep;

package Radar_Source is

   --  Une mesure brute : un balayage capte dans une direction donnee.
   --  (azimut + elevation = ou pointait le radar ; Data = les echos recus).
   type Measurement is record
      Azimuth   : Float;     --  direction horizontale, en degres
      Elevation : Float;     --  direction verticale, en degres
      Data      : Sweep;     --  les amplitudes recues le long de cette ligne
   end record;

   --  ===== LE CONTRAT =====
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

end Radar_Source;