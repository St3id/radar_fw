with Radar_Ld2450_Log;
with Radar_Ld2450_Plausibility;
with Radar_Ld2450_Stream;
with Radar_Planar_Source;
with Radar_Source;

--  Radar_Ld2450_Replay : la premiere source concrete de Radar_Planar_Source.
--
--  Elle relit un fichier d'octets enregistres (Radar_Ld2450_Log) et les fait
--  passer par le MEME parseur et le MEME filtre de plausibilite qu'un flux
--  direct. C'est ainsi que tout essai materiel devient rejouable : une seule
--  capture sert ensuite autant de fois qu'il le faut, sans le module.
--
--  Le contrat distingue deja la fin du silence, sans etre elargi :
--     - Available = False et Has_More = True : le module s'est tu ici plus
--       de Silence_Gap_Ms ; la lecture peut continuer ;
--     - Available = False et Has_More = False : le fichier est fini.
--  Available = False n'est rendu qu'une fois par silence.
--
--  Le rapport ne porte que x, y et la vitesse : le LD2450 ne mesure pas
--  d'altitude. Stamp est l'heure de RECEPTION du bloc qui contient le
--  dernier octet de la trame : le contrat demande l'heure de capture, dont
--  c'est la meilleure approximation sans materiel pour mesurer l'ecart (1,2 ms
--  de ligne, plus la latence de l'adaptateur, inconnue). Min_Range_Mm reste a
--  0 : la zone aveugle du module n'est pas mesuree.
--
--  Une trame dont toutes les cibles sont rejetees donne un rapport vide : les
--  compteurs de Checks font la difference avec une piece vide.

package Radar_Ld2450_Replay is

   --  HYPOTHESE, a remesurer : trois periodes du module (10 trames/s) sans
   --  octet font un silence, et non un peu de gigue.
   Silence_Gap_Ms : constant := 300;

   type Replay_Source is new Radar_Planar_Source.Planar_Source with private;

   --  Ok = False si le fichier n'est pas lisible ou n'est pas au format :
   --  la source n'a alors rien a livrer (Has_More = False).
   procedure Open
     (Self   : in out Replay_Source;
      Path   : String;
      Sensor : Positive := 1;
      Ok     : out Boolean);

   overriding
   procedure Next_Report
     (Self      : in out Replay_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean);

   overriding
   function Has_More (Self : Replay_Source) return Boolean;

   --  Ce qui s'est passe jusqu'ici : les compteurs du parseur et du filtre,
   --  le nombre de silences signales, et pourquoi la lecture s'est arretee
   --  (Chunk_Ok tant qu'elle n'est pas finie).
   function Stream (Self : Replay_Source) return Radar_Ld2450_Stream.Parser;
   function Checks
     (Self : Replay_Source) return Radar_Ld2450_Plausibility.Validator;
   function Silences (Self : Replay_Source) return Natural;
   function Stop_Reason
     (Self : Replay_Source) return Radar_Ld2450_Log.Read_Status;

private

   type Replay_Source is new Radar_Planar_Source.Planar_Source with record
      Content       : Radar_Ld2450_Log.Byte_Vectors.Vector;
      Next_Block    : Positive := 1;
      Chunk_Next    : Positive := 1;      --  prochain octet du bloc courant
      Chunk_Last    : Natural  := 0;      --  dernier octet du bloc courant
      Chunk_Stamp   : Radar_Source.Time_Ms := 0;
      Last_Activity : Radar_Source.Time_Ms := 0;   --  dernier octet recu
      Last_Frame    : Radar_Source.Time_Ms := 0;   --  derniere trame livree
      Has_Frame     : Boolean  := False;
      In_Silence    : Boolean  := False;
      Finished      : Boolean  := True;
      Silence_Count : Natural  := 0;
      Stopped       : Radar_Ld2450_Log.Read_Status :=
        Radar_Ld2450_Log.Chunk_Ok;
      Sensor        : Positive := 1;
      Parser        : Radar_Ld2450_Stream.Parser;
      Filter        : Radar_Ld2450_Plausibility.Validator;
   end record;

end Radar_Ld2450_Replay;
