with Radar_Ld2450; use Radar_Ld2450;

--  Radar_Ld2450_Plausibility : ce qu'une trame bien encadree dit, est-ce
--  croyable ?
--
--  Une trame LD2450 n'a pas de somme de controle : un bit inverse entre
--  l'en-tete et la fin passe le parseur (Radar_Ld2450_Stream). Ce paquet
--  rejette ce qu'un capteur en etat de marche ne devrait pas rapporter, et
--  COMPTE chaque rejet par motif : un compteur qui monte est une mesure de
--  la liaison ou le signe qu'un seuil est faux.
--
--  Il ne peut pas tout voir. Un bit de poids faible inverse deplace une
--  cible de quelques millimetres, sans rien de detectable : aucun filtre ne
--  remplace une somme de controle absente.
--
--  Separe du parseur : le format est un fait prouve, ces seuils sont des
--  suppositions. Tous sont des HYPOTHESES, posees sans module reel, a
--  remesurer sur le materiel avant d'en deduire quoi que ce soit.

package Radar_Ld2450_Plausibility
  with SPARK_Mode => On
is

   --  HYPOTHESE - distance maximale. Le manuel annonce ~6 m, des releves
   --  d'utilisateurs 8 m dans l'axe ; 10 m laisse une marge de bruit.
   Max_Range_Mm : constant := 10_000;

   --  HYPOTHESE - vitesse radiale maximale : 10 m/s, au-dela d'un humain qui
   --  court. Le manuel ne donne pas de borne du champ.
   Max_Speed_Cm_S : constant := 1_000;

   --  HYPOTHESE - champ de resolution. Le manuel le dit fixe mais imprime
   --  320 et 360 ; la fourchette couvre ces deux valeurs seulement, et une
   --  cible presente a resolution nulle est rejetee. Rien ne prouve que tous
   --  les microprogrammes respectent cette plage.
   Min_Resolution_Mm : constant := 200;
   Max_Resolution_Mm : constant := 500;

   --  HYPOTHESE - y > 0 : le module vise vers +Y, une cible derriere lui
   --  n'existe pas. Un module reel pourrait rapporter y = 0 au bord du
   --  champ : ce serait a corriger dans Static_Verdict.

   --  HYPOTHESE - porte de saut. D'une trame a l'autre, une cible d'un
   --  emplacement ne bouge pas de plus que Jump_Margin_Mm (bruit de mesure,
   --  grand au bord du champ selon les releves) plus Jump_Speed_Mm_S x dt.
   --  3 m/s : la vitesse maximale que retient deja le pistage.
   Jump_Margin_Mm  : constant := 1_500;
   Jump_Speed_Mm_S : constant := 3_000;

   --  HYPOTHESE - au-dela de ce silence, le passe ne dit plus rien : la
   --  memoire des emplacements est oubliee et la porte de saut ne joue plus.
   Jump_Forget_Ms : constant := 2_000;

   --  Le saut se juge sur le plus grand ecart, en x ou en y : une racine
   --  carree n'apporterait rien pour une porte aussi large.
   subtype Gate_Mm is Integer range
     0 .. Jump_Margin_Mm + Jump_Speed_Mm_S * Jump_Forget_Ms / 1_000;

   --  ----- Le verdict d'une cible, sans memoire -----

   type Verdict is
     (Plausible, Not_In_Front, Out_Of_Range, Too_Fast, Bad_Resolution);

   --  Les motifs qui rejettent : ceux du verdict, plus le saut.
   type Reject_Reason is
     (Reject_Not_In_Front, Reject_Out_Of_Range, Reject_Too_Fast,
      Reject_Bad_Resolution, Reject_Jump);

   --  Un emplacement tout a zeros est valide et ABSENT : c'est ainsi que le
   --  manuel note "pas de cible". Le test porte sur les valeurs decodees :
   --  00 80 se lit 0 comme 00 00.
   function Is_Absent (T : Raw_Target) return Boolean is
     (T.X_Mm = 0
      and then T.Y_Mm = 0
      and then T.Speed_Cm_S = 0
      and then T.Resolution_Mm = 0);

   --  Le carre de la distance tient dans un Integer : 2 x 32 767 ** 2 est
   --  inferieur a 2 ** 31. Pas de racine, donc pas de flottant dans le coeur.
   function Static_Verdict (T : Raw_Target) return Verdict is
     (if T.Y_Mm <= 0 then Not_In_Front
      elsif Integer (T.X_Mm) * Integer (T.X_Mm)
            + Integer (T.Y_Mm) * Integer (T.Y_Mm) > Max_Range_Mm ** 2
      then Out_Of_Range
      elsif abs T.Speed_Cm_S > Max_Speed_Cm_S then Too_Fast
      elsif T.Resolution_Mm not in Min_Resolution_Mm .. Max_Resolution_Mm
      then Bad_Resolution
      else Plausible);

   --  ----- Le filtre, avec sa memoire et ses compteurs -----

   type Counter is range 0 .. 2 ** 31 - 1;

   type Validator is private;

   function Accepted (V : Validator) return Counter;
   function Absent (V : Validator) return Counter;
   function Rejected (V : Validator; Why : Reject_Reason) return Counter;

   --  La largeur de la porte de saut pour un ecart de Elapsed_Ms.
   function Jump_Gate (Elapsed_Ms : Natural) return Gate_Mm is
     (Jump_Margin_Mm
      + Jump_Speed_Mm_S
        * Natural'Min (Elapsed_Ms, Jump_Forget_Ms) / 1_000);

   --  Juge les trois emplacements d'une trame et rend les cibles retenues,
   --  dans les premieres cases. Elapsed_Ms : le temps ecoule depuis la trame
   --  precedente, 0 si les horodatages reculent ou sont egaux (la porte est
   --  alors a son plus etroit).
   --
   --  Un saut isole est rejete : c'est la signature d'un octet abime. Si la
   --  trame suivante confirme la nouvelle position, elle est acceptee : un
   --  module qui change une cible d'emplacement ne perd qu'une trame.
   procedure Validate
     (V          : in out Validator;
      Slots      : Raw_Target_Array;
      Elapsed_Ms : Natural;
      Result     : out Raw_Report)
     with
       Post =>
         (for all I in 1 .. Result.Count =>
            Static_Verdict (Result.Targets (I)) = Plausible
            and then not Is_Absent (Result.Targets (I))
            and then
            (for some S in Target_Slot =>
               Result.Targets (I) = Slots (S)))
         and then
         (for all I in Result.Count + 1 .. Max_Targets =>
            Is_Absent (Result.Targets (I)))
         and then
         (if (for all S in Target_Slot => Is_Absent (Slots (S))) then
            Result.Count = 0
            and then
            (for all Why in Reject_Reason =>
               Rejected (V, Why) = Rejected (V'Old, Why)))
         and then Accepted (V) >= Accepted (V'Old)
         and then Absent (V) >= Absent (V'Old)
         and then
         (for all Why in Reject_Reason =>
            Rejected (V, Why) >= Rejected (V'Old, Why));

private

   --  Ce qu'on se rappelle d'un emplacement : la derniere position retenue,
   --  et une position rejetee pour saut, en attente de confirmation.
   type Slot_Memory is record
      Known       : Boolean      := False;
      X_Mm        : Signed_Value := 0;
      Y_Mm        : Signed_Value := 0;
      Has_Pending : Boolean      := False;
      Pending_X   : Signed_Value := 0;
      Pending_Y   : Signed_Value := 0;
   end record;

   type Slot_Memories is array (Target_Slot) of Slot_Memory;
   type Reject_Counts is array (Reject_Reason) of Counter;

   type Validator is record
      Slots    : Slot_Memories;
      Accepted : Counter       := 0;
      Absent   : Counter       := 0;
      Rejected : Reject_Counts := (others => 0);
   end record;

   function Accepted (V : Validator) return Counter is (V.Accepted);
   function Absent (V : Validator) return Counter is (V.Absent);
   function Rejected (V : Validator; Why : Reject_Reason) return Counter is
     (V.Rejected (Why));

end Radar_Ld2450_Plausibility;
