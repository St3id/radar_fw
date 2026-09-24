with Radar_Sweep;  use Radar_Sweep;

--  Radar_Source : interface des profils de distance.
--  Elle n'est pas directement compatible avec tous les capteurs envisages :
--  ceux qui livrent deja des detections utilisent Radar_Target_Source.
--
--  Aucun mode ne parle au materiel en direct. Un adaptateur devra convertir
--  ou exposer les donnees sans perdre leur plage, leur pas, leur repere ou
--  leur horodatage. Le LD2450 necessitera un flux de detections distinct.

package Radar_Source is

   --  Base de temps du systeme : millisecondes ecoulees depuis le
   --  demarrage de la source.
   --
   --  Un entier borne, et pas Ada.Real_Time.Time : ce type doit
   --  survivre au portage sur carte, ou Calendar et Real_Time ne sont
   --  pas garantis (regle R7), et c est deja le format du champ
   --  TIMESTAMP du protocole de telemetrie.
   type Time_Ms is range 0 .. 2 ** 31 - 1;

   --  Une mesure du modele actuel : profil de 256 amplitudes simulees dans
   --  une direction. Sweep fixe la plage a 20 m ; ce n'est pas le format
   --  natif garanti d'un A121 ni des cibles serie du LD2450.
   type Measurement is record
      Azimuth   : Float;         --  direction horizontale, en degres
      Elevation : Float;         --  direction verticale, en degres
      Stamp     : Time_Ms;  --  QUAND la mesure a ete prise
      Data      : Sweep;         --  les amplitudes de cette ligne
   end record;

   --  ----- Le contrat -----
   --  "Radar_Source" est une interface de profils pour le pipeline simule.
   --  Une source reelle ne l'implemente que si son format a ete adapte sans
   --  inventer les donnees physiques absentes.
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

   --  Nombre de mesures d'elevation traitees avant de passer a l'azimut
   --  suivant. Le mode de cartographie cadence une colonne complete a la
   --  fois sans connaitre la grille concrete de la source ; c'est ce qui
   --  permet d'utiliser plusieurs resolutions avec le meme pipeline.
   function Per_Azimuth (Self : Source) return Positive is abstract;

end Radar_Source;
