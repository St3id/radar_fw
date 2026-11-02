with Radar_Ld2450; use Radar_Ld2450;

--  Radar_Ld2450_Stream : retrouver les trames dans un flux d'octets du
--  LD2450, sans somme de controle pour s'aider et sans jamais supposer que
--  la lecture a commence au bon endroit.
--
--  Le parseur garde une fenetre glissante : les octets recus qui peuvent
--  encore etre le debut d'une trame. Quand un octet contredit son rang, il
--  n'abandonne que le PREMIER octet de la fenetre et reexamine le reste.
--  Jeter toute la fenetre serait plus simple et faux : une trame amputee
--  de ses derniers octets contient deja le debut de la suivante.
--
--  Ce paquet ne juge pas les valeurs : une trame bien encadree dont un
--  octet du milieu est abime passe ici. La plausibilite vit a part
--  (Radar_Ld2450_Plausibility) : ce que l'on sait du format est prouve,
--  ce que l'on suppose du capteur reste une hypothese a remesurer.
--
--  Aucune allocation, exception ni conversion non verifiee : radar_core.gpr
--  compile ce paquet sous core_restrictions.adc. Rien ici n'a vu de module
--  reel : seuls les vecteurs du manuel et l'emulateur l'ont eprouve.

package Radar_Ld2450_Stream
  with SPARK_Mode => On
is

   --  Un compteur qui s'arrete a sa borne au lieu de deborder : apres
   --  24 jours de flux continu, un total faux vaut mieux qu'un arret.
   type Counter is range 0 .. 2 ** 31 - 1;

   --  C + D, sature a la borne du type.
   function Plus (C : Counter; D : Natural) return Counter is
     (if C <= Counter'Last - Counter (D) then C + Counter (D)
      else Counter'Last);

   --  Une trame complete fait 30 octets ; la fenetre n'en garde donc jamais
   --  plus de 29 : au trentieme, la trame est livree ou le premier ecarte.
   subtype Pending_Count is Natural range 0 .. Frame_Length - 1;

   --  ----- Ce que le format impose -----

   --  Ce qu'un octet doit etre a un rang de la trame. Entre l'en-tete et la
   --  fin, tout est permis : le format ne dit rien de plus.
   function Fits_Rank (Rank : Positive; B : Byte) return Boolean is
     (if Rank <= Header_Length then B = Header (Rank)
      elsif Rank >= Tail_First then B = Tail (Rank - Tail_First + 1)
      else True)
     with Pre => Rank <= Frame_Length;

   --  Vrai si les N premiers octets de W peuvent etre le debut d'une trame.
   function Is_Candidate (W : Frame_Bytes; N : Natural) return Boolean is
     (for all I in 1 .. N => Fits_Rank (I, W (I)))
     with Pre => N <= Frame_Length;

   --  L'en-tete AA FF 03 00 et la fin 55 CC, chacun a son rang. Ecrit sans
   --  passer par Fits_Rank, pour que le contrat de Feed dise la propriete
   --  voulue plutot que de repeter le code qui l'etablit.
   function Has_Frame_Marks (F : Frame_Bytes) return Boolean is
     ((for all I in Header'Range => F (I) = Header (I))
      and then
      (for all I in Tail'Range => F (Tail_First + I - 1) = Tail (I)));

   --  ----- Le decodage d'une trame -----

   --  Le mot de deux octets qui commence au rang Rank.
   function Word_At (F : Frame_Bytes; Rank : Positive) return Word is
     (To_Word (F (Rank), F (Rank + 1)))
     with Pre => Rank < Frame_Length;

   --  Les quatre champs d'un emplacement. Tous sont signes par bit de signe
   --  sauf la resolution (ARCHITECTURE.md, section 2.6).
   function Decode_Slot (F : Frame_Bytes; S : Target_Slot) return Raw_Target is
     ((X_Mm          => Decode_Signed (Word_At (F, Slot_First (S))),
       Y_Mm          => Decode_Signed (Word_At (F, Slot_First (S) + 2)),
       Speed_Cm_S    => Decode_Signed (Word_At (F, Slot_First (S) + 4)),
       Resolution_Mm => Word_At (F, Slot_First (S) + 6)));

   --  Une trame livree : ses octets tels quels, et les trois emplacements
   --  decodes SANS tri ni filtre. Dire qu'un emplacement est vide ou
   --  implausible est le travail de Radar_Ld2450_Plausibility.
   type Decoded_Frame is record
      Bytes   : Frame_Bytes := (others => 0);
      Targets : Raw_Target_Array;
   end record;

   --  ----- Le parseur -----

   type Parser is private
     with Default_Initial_Condition => Is_Consistent (Parser);

   function Bytes_Read (P : Parser) return Counter;
   function Frames_Delivered (P : Parser) return Counter;
   function Bytes_Discarded (P : Parser) return Counter;

   --  Les octets encore dans la fenetre : ni livres, ni ecartes.
   function Pending (P : Parser) return Pending_Count;

   --  L'invariant : la fenetre est toujours un debut de trame possible, et
   --  tant que les compteurs n'ont pas sature, rien ne s'est perdu :
   --  octets lus = 30 x trames livrees + octets ecartes + en attente. Sature
   --  a Bytes_Read = Counter'Last, ce bilan n'est plus garanti.
   function Is_Consistent (P : Parser) return Boolean;

   --  L'octet de rang I de la suite "fenetre de P, puis Octet".
   function Joined_Byte
     (P : Parser; Octet : Byte; I : Positive) return Byte
     with Pre => I <= Pending (P) + 1;

   --  Vrai si, en sautant D octets de cette suite, le reste peut encore etre
   --  un debut de trame.
   function Suffix_Is_Candidate
     (P : Parser; Octet : Byte; D : Natural) return Boolean
     with Pre => D <= Pending (P);

   --  Ce que fait un octet qui ne complete pas de trame : Before devient
   --  After en n'ecartant que des debuts qui ne pouvaient PAS etre une trame,
   --  en commencant par le plus ancien, et le reste de la suite est garde
   --  intact, dans l'ordre. C'est ce qui interdit de sauter 30 octets :
   --  aucun candidat encore possible n'est jamais perdu.
   function Keeps_Longest_Candidate
     (Before : Parser; Octet : Byte; After : Parser) return Boolean
     with Ghost;

   --  Donne au parseur l'octet suivant du flux, quelle que soit sa valeur.
   --  Trame_Prete = True : Sortie porte une trame complete, dont le dernier
   --  octet est Octet, avec son en-tete et sa fin a leurs rangs, et dont les
   --  champs sont ceux que lisent ses octets. Trame_Prete = False : Sortie
   --  n'a aucun sens et rien n'est livre.
   procedure Feed
     (P           : in out Parser;
      Octet       : Byte;
      Sortie      : out Decoded_Frame;
      Trame_Prete : out Boolean)
     with
       Pre  => Is_Consistent (P),
       Post =>
         Is_Consistent (P)
         and then Bytes_Read (P) = Plus (Bytes_Read (P'Old), 1)
         and then
         (if Trame_Prete then
            Pending (P'Old) = Frame_Length - 1
            and then Pending (P) = 0
            and then Frames_Delivered (P) =
                       Plus (Frames_Delivered (P'Old), 1)
            and then Bytes_Discarded (P) = Bytes_Discarded (P'Old)
            and then Has_Frame_Marks (Sortie.Bytes)
            and then Sortie.Bytes (Frame_Length) = Octet
            and then
            (for all I in 1 .. Pending (P'Old) + 1 =>
               Sortie.Bytes (I) = Joined_Byte (P'Old, Octet, I))
            and then
            (for all S in Target_Slot =>
               Sortie.Targets (S) = Decode_Slot (Sortie.Bytes, S))
          else
            Frames_Delivered (P) = Frames_Delivered (P'Old)
            and then Keeps_Longest_Candidate (P'Old, Octet, P));

private

   type Parser is record
      Window    : Frame_Bytes   := (others => 0);
      Used      : Pending_Count := 0;
      Read      : Counter       := 0;
      Delivered : Counter       := 0;
      Discarded : Counter       := 0;
   end record;

   function Bytes_Read (P : Parser) return Counter is (P.Read);
   function Frames_Delivered (P : Parser) return Counter is (P.Delivered);
   function Bytes_Discarded (P : Parser) return Counter is (P.Discarded);
   function Pending (P : Parser) return Pending_Count is (P.Used);

   --  Le bilan des octets. Les gardes evitent un calcul sur 64 bits, qui
   --  n'aurait pas sa place sur la cible pour un simple controle.
   function Balanced
     (Read, Delivered, Discarded : Counter;
      Used                       : Natural) return Boolean
   is
     (Used <= Frame_Length
      and then Delivered <= Counter'Last / Frame_Length
      and then Discarded
                 <= Counter'Last - Counter (Used)
                    - Counter (Frame_Length) * Delivered
      and then Read = Counter (Frame_Length) * Delivered + Discarded
                      + Counter (Used));

   function Is_Consistent (P : Parser) return Boolean is
     (Is_Candidate (P.Window, P.Used)
      and then
      (P.Read = Counter'Last
       or else Balanced (P.Read, P.Delivered, P.Discarded, P.Used)));

   function Joined_Byte
     (P : Parser; Octet : Byte; I : Positive) return Byte
   is
     (if I <= P.Used then P.Window (I) else Octet);

   function Suffix_Is_Candidate
     (P : Parser; Octet : Byte; D : Natural) return Boolean
   is
     (for all I in 1 .. P.Used + 1 - D =>
        Fits_Rank (I, Joined_Byte (P, Octet, I + D)));

   function Keeps_Longest_Candidate
     (Before : Parser; Octet : Byte; After : Parser) return Boolean
   is
     (After.Used <= Before.Used + 1
      and then
      (for all I in 1 .. After.Used =>
         After.Window (I) =
           Joined_Byte (Before, Octet,
                        I + (Before.Used + 1 - After.Used)))
      and then
      (for all D in 0 .. Before.Used - After.Used =>
         not Suffix_Is_Candidate (Before, Octet, D))
      and then
      After.Discarded =
        Plus (Before.Discarded, Before.Used + 1 - After.Used));

end Radar_Ld2450_Stream;
