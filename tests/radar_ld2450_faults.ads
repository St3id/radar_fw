with Radar_Ld2450; use Radar_Ld2450;

--  Radar_Ld2450_Faults : les vecteurs du manuel et le generateur de flux
--  abimes. Cote tests seulement.
--
--  Les trames de reference sont recopiees du manuel Hi-Link : ce sont elles
--  qu'on abime, et non la sortie de notre encodeur, qui validerait son propre
--  decodeur s'il se trompait de la meme facon (ARCHITECTURE.md, section 2.6).

package Radar_Ld2450_Faults is

   --  ----- Les vecteurs du manuel -----

   --  Les 8 octets de chaque cible de reference, tels que le manuel les
   --  imprime.
   Example_Bytes : constant Byte_Array :=     --  -782, 1713, -16 cm/s, 320
     (16#0E#, 16#03#, 16#B1#, 16#86#, 16#10#, 16#00#, 16#40#, 16#01#);
   Faq_1_Bytes   : constant Byte_Array :=     --  -272, 850, 0 cm/s, 360
     (16#10#, 16#01#, 16#52#, 16#83#, 16#00#, 16#00#, 16#68#, 16#01#);
   Faq_2_Bytes   : constant Byte_Array :=     --  -228, 903, +17 cm/s, 360
     (16#E4#, 16#00#, 16#87#, 16#83#, 16#11#, 16#80#, 16#68#, 16#01#);
   Faq_3_Bytes   : constant Byte_Array :=     --  2750, 3655, -17 cm/s, 360
     (16#BE#, 16#8A#, 16#47#, 16#8E#, 16#11#, 16#00#, 16#68#, 16#01#);

   Empty_Slot : constant Byte_Array (1 .. Target_Length) := (others => 0);

   --  La trame attendue pour une seule cible : en-tete, ses 8 octets, deux
   --  emplacements vides, fin.
   function Manual_Frame (Slot_Bytes : Byte_Array) return Frame_Bytes is
     (Header & Slot_Bytes & Empty_Slot & Empty_Slot & Tail);

   subtype Manual_Index is Positive range 1 .. 4;

   --  Les quatre trames du manuel, et ce qu'elles veulent dire d'apres lui.
   function Frame_Of (K : Manual_Index) return Frame_Bytes;
   function Target_Of (K : Manual_Index) return Raw_Target;

   --  Les quatre a la suite : 120 octets.
   function Manual_Stream return Byte_Array;

   --  Une reponse de commande du module : FD FC FB FA, longueur, mot de
   --  commande, statut, 04 03 02 01. Ici la reponse a la commande multi-cible
   --  0x0090, d'apres les implementations tierces (section 2.6) ; aucune n'a
   --  ete captee sur un module. Elle partage la liaison avec les trames.
   Ack_Frame : constant Byte_Array :=
     (16#FD#, 16#FC#, 16#FB#, 16#FA#, 16#04#, 16#00#, 16#90#, 16#01#,
      16#00#, 16#00#, 16#04#, 16#03#, 16#02#, 16#01#);

   --  ----- Les degats, toujours rendus avec des indices a partir de 1 -----

   --  Le flux lu a partir d'un point quelconque : les Count premiers octets
   --  n'ont jamais ete vus.
   function Drop_Start (S : Byte_Array; Count : Natural) return Byte_Array
     with Pre => Count <= S'Length;

   --  Le flux coupe : les Count derniers octets ne sont jamais arrives.
   function Truncate (S : Byte_Array; Count : Natural) return Byte_Array
     with Pre => Count <= S'Length;

   --  Count octets perdus apres les Kept premiers.
   function Lose
     (S : Byte_Array; Kept : Natural; Count : Natural) return Byte_Array
     with Pre => Kept + Count <= S'Length;

   --  Des octets parasites inseres apres les Kept premiers.
   function Insert
     (S : Byte_Array; Kept : Natural; Extra : Byte_Array) return Byte_Array
     with Pre => Kept <= S'Length;

   --  Le bit Bit (0 .. 7) de l'octet de rang Rank (a partir de 1) inverse.
   function Flip_Bit
     (S : Byte_Array; Rank : Positive; Bit : Natural) return Byte_Array
     with Pre => Rank <= S'Length and then Bit <= 7;

   --  ----- Le hasard -----

   --  Generateur congruentiel local, constantes de Numerical Recipes. Pas de
   --  Float_Random : les memes octets doivent sortir avec tout compilateur,
   --  puisque les tests affirment des totaux exacts sur cette suite.
   type Random_State is mod 2 ** 32;

   procedure Next_Byte (S : in out Random_State; B : out Byte);

   function Random_Bytes (Seed : Random_State; Count : Natural)
     return Byte_Array;

end Radar_Ld2450_Faults;
