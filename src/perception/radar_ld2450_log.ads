with Ada.Containers.Vectors;
with Ada.Streams.Stream_IO;
with Radar_Ld2450;
with Radar_Source;

--  Radar_Ld2450_Log : le format de fichier d'un flux serie enregistre.
--
--  Le fichier garde les octets TELS QU'ILS SONT ARRIVES, parasites compris,
--  avec leur heure de reception : rien n'est interprete a l'enregistrement.
--  Un parseur corrige plus tard pourra ainsi relire les memes captures, et
--  une capture abimee reste une donnee d'essai.
--
--  Format, tous les entiers en petit-boutiste :
--
--     8 octets   "RFWLD2S1" (identifie le format et sa version)
--     puis des blocs, jusqu'a la fin du fichier :
--        4 octets   heure de reception, en ms depuis le debut (0 .. 2**31-1)
--        2 octets   nombre d'octets du bloc, L (0 .. 4 096)
--        L octets   les octets recus, dans l'ordre
--
--  Un bloc de longueur nulle dit "a cette heure, la liaison etait ouverte et
--  rien n'etait arrive" : c'est ce qui distingue un module muet d'une
--  capture interrompue.
--
--  L'heure est celle de la RECEPTION par le PC, pas celle de la capture par
--  le module : elle inclut la latence de l'adaptateur USB-serie, non
--  mesuree, et plusieurs trames arrivees ensemble partagent la meme heure.
--
--  Hors de src/core : fichiers et conteneurs n'existent pas sur la carte.

package Radar_Ld2450_Log is

   Magic : constant String := "RFWLD2S1";

   Max_Chunk_Bytes : constant := 4_096;

   --  ----- L'ecriture -----

   type Writer is limited private;

   --  Ok = False si le fichier ne peut pas etre cree.
   procedure Create (W : in out Writer; Path : String; Ok : out Boolean);

   --  Ajoute un bloc et force son ecriture : une capture interrompue perd
   --  au plus le bloc en cours. Peut lever les exceptions de Stream_IO
   --  (disque plein) : c'est a l'appelant de decider quoi en faire.
   procedure Append
     (W     : in out Writer;
      Stamp : Radar_Source.Time_Ms;
      Bytes : Radar_Ld2450.Byte_Array)
     with Pre => Bytes'Length <= Max_Chunk_Bytes;

   procedure Close (W : in out Writer);

   --  ----- La lecture -----

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Radar_Ld2450.Byte,
      "="          => Radar_Ld2450."=");

   --  Ce que dit la lecture d'un bloc. Une fin imprevue n'est pas une
   --  exception : un enregistreur coupe net laisse precisement ce fichier-la.
   type Read_Status is
     (Chunk_Ok,        --  un bloc complet
      End_Of_Log,      --  fin propre, entre deux blocs
      Truncated,       --  le fichier s'arrete au milieu d'un bloc
      Malformed);      --  heure ou longueur hors du format

   --  Charge tout le fichier en memoire. Ok = False si le fichier n'existe
   --  pas, ne peut pas etre lu, ou ne commence pas par Magic. Next rend alors
   --  la position du premier bloc.
   procedure Load
     (Path    : String;
      Content : out Byte_Vectors.Vector;
      Next    : out Positive;
      Ok      : out Boolean);

   --  Lit l'entete de bloc a la position Next. Si Status = Chunk_Ok, le bloc
   --  va de First a First + Length - 1, et Next pointe sur le bloc suivant.
   --  Sinon, Next ne bouge pas.
   procedure Next_Chunk
     (Content : Byte_Vectors.Vector;
      Next    : in out Positive;
      Stamp   : out Radar_Source.Time_Ms;
      First   : out Positive;
      Length  : out Natural;
      Status  : out Read_Status);

private

   type Writer is limited record
      File : Ada.Streams.Stream_IO.File_Type;
   end record;

end Radar_Ld2450_Log;
