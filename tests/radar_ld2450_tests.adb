with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with AUnit.Assertions;                  use AUnit.Assertions;
with Radar_Ld2450;                      use Radar_Ld2450;
with Radar_Ld2450_Sim;                  use Radar_Ld2450_Sim;
with Radar_Source;
with Radar_World;                       use Radar_World;

--  "use type" : seulement les operateurs de Time_Ms (comparer deux
--  instants), sans importer tout Radar_Source.
use type Radar_Source.Time_Ms;

--  Corps de la suite 4. Les quatre cibles de reference sont recopiees du
--  manuel Hi-Link du LD2450 : l'exemple de la section protocole (repris
--  en ARCHITECTURE.md, section 2.6) et les trois captures de sa FAQ.
--  Les tests de l'emulateur, eux, verifient sa physique et ses defauts :
--  son format est deja couvert par ces trames du manuel.

package body Radar_Ld2450_Tests is

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

   --  Une cible dans les unites du module.
   function Target
     (X, Y, Speed : Signed_Value;
      Resolution  : Word) return Raw_Target
   is
     ((X_Mm          => X,
       Y_Mm          => Y,
       Speed_Cm_S    => Speed,
       Resolution_Mm => Resolution));

   --  Un rapport a une seule cible.
   function One_Target (T : Raw_Target) return Raw_Report is
     ((Targets => (1 => T, others => <>), Count => 1));

   --  Compare deux trames et nomme le premier octet different.
   procedure Assert_Frame (Got, Expected : Frame_Bytes; What : String) is
   begin
      for I in Got'Range loop
         Assert (Got (I) = Expected (I),
                 What & " : l'octet" & Positive'Image (I) & " vaut"
                 & Byte'Image (Got (I)) & " au lieu de"
                 & Byte'Image (Expected (I)));
      end loop;
   end Assert_Frame;

   --  ----- Outils des tests de l'emulateur -----

   Deg : constant := Pi / 180.0;

   --  Un objet du monde (X devant, Y a gauche, Z en haut, en mm), qui
   --  avance de Vx mm par periode le long de X.
   function Object_At (X, Y, Z : Float; Vx : Float := 0.0) return Object is
     ((Id => 1, X => X, Y => Y, Z => Z, Vx => Vx, Vy => 0.0, Vz => 0.0));

   procedure Add (W : in out World; O : Object) is
   begin
      W.Count := W.Count + 1;
      W.Objects (W.Count) := O;
   end Add;

   --  Une valeur codee, au millimetre (ou au cm/s) pres.
   function Close (V : Signed_Value; Expected : Float) return Boolean is
     (abs (Float (V) - Expected) <= 1.0);

   --  Quatre objets visibles et quatre qui ne le sont pas : derriere le
   --  capteur, hors de portee a 30 deg, trop haut (45 deg), hors champ
   --  (65 deg). Les trois plus proches des visibles, dans l'ordre :
   --  1 118 mm a droite, 2 000 mm dans l'axe, 2 500 mm a 40 deg a gauche.
   function Field_Scene return World is
      W : World := Empty_World;
   begin
      Add (W, Object_At (1_000.0, -500.0, 0.0));
      Add (W, Object_At (2_000.0, 0.0, 0.0));
      Add (W, Object_At (2_500.0 * Cos (40.0 * Deg),
                         2_500.0 * Sin (40.0 * Deg), 0.0));
      Add (W, Object_At (3_000.0 * Cos (20.0 * Deg),
                         -3_000.0 * Sin (20.0 * Deg), 0.0));
      Add (W, Object_At (7_000.0 * Cos (30.0 * Deg),
                         -7_000.0 * Sin (30.0 * Deg), 0.0));
      Add (W, Object_At (-2_000.0, 0.0, 0.0));
      Add (W, Object_At (1_500.0, 0.0, 1_500.0));
      Add (W, Object_At (1_000.0 * Cos (65.0 * Deg),
                         -1_000.0 * Sin (65.0 * Deg), 0.0));
      return W;
   end Field_Scene;

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Module LD2450 (trames et emulateur)");
   end Name;

   --  Test 1 : les quatre trames du manuel, octet pour octet. Ensemble,
   --  elles couvrent un X negatif et positif, une vitesse negative, nulle
   --  et positive, et les deux resolutions rencontrees (320 et 360).
   procedure Test_Manual_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Frame (Encode_Frame (One_Target (Target (-782, 1_713, -16, 320))),
                    Manual_Frame (Example_Bytes), "Exemple du protocole");
      Assert_Frame (Encode_Frame (One_Target (Target (-272, 850, 0, 360))),
                    Manual_Frame (Faq_1_Bytes), "FAQ 1 (vitesse nulle)");
      Assert_Frame (Encode_Frame (One_Target (Target (-228, 903, 17, 360))),
                    Manual_Frame (Faq_2_Bytes), "FAQ 2 (vitesse positive)");
      Assert_Frame
        (Encode_Frame (One_Target (Target (2_750, 3_655, -17, 360))),
         Manual_Frame (Faq_3_Bytes), "FAQ 3 (X positif)");
   end Test_Manual_Frames;

   --  Test 2 : le codage a bit de signe aux limites, et l'ordre des
   --  octets. L'aller-retour sur toutes les valeurs est prouve par SPARK
   --  (postcondition de Encode_Signed) ; ces cas le rendent lisible.
   procedure Test_Signed_Coding
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Encode_Signed (0) = 0,
              "Zero se code 00 00 : bit de signe a 0");
      Assert (Encode_Signed (1) = 16#8001#,
              "+1 porte le bit de signe");
      Assert (Encode_Signed (-1) = 1,
              "-1 se code par sa seule valeur absolue");
      Assert (Encode_Signed (Signed_Value'Last) = Word'Last,
              "+32767 : les seize bits a 1");
      Assert (Encode_Signed (Signed_Value'First) = 16#7FFF#,
              "-32767 : quinze bits a 1, signe a 0");
      Assert (Decode_Signed (0) = 0 and then Decode_Signed (Sign_Bit) = 0,
              "Les deux zeros, 00 00 et 00 80, se lisent 0");
      Assert (Low_Byte (16#86B1#) = 16#B1#
                and then High_Byte (16#86B1#) = 16#86#,
              "Poids faible en premier : 86B1 part en B1 puis 86");
      Assert (To_Word (16#B1#, 16#86#) = 16#86B1#,
              "B1 puis 86 se relisent 86B1");
   end Test_Signed_Coding;

   --  Test 3 : les emplacements. Sans cible, la trame ne contient que des
   --  zeros entre l'en-tete et la fin ; avec trois cibles, chacune occupe
   --  sa place ; et c'est Count qui decide, pas le contenu du tableau.
   procedure Test_Slots
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      None  : constant Raw_Report := (others => <>);
      Three : Raw_Report;
   begin
      Assert_Frame (Encode_Frame (None),
                    Header & Empty_Slot & Empty_Slot & Empty_Slot & Tail,
                    "Trame sans cible");

      Three.Targets :=
        (Target (-782, 1_713, -16, 320),
         Target (-272, 850, 0, 360),
         Target (2_750, 3_655, -17, 360));
      Three.Count := 3;
      Assert_Frame (Encode_Frame (Three),
                    Header & Example_Bytes & Faq_1_Bytes & Faq_3_Bytes
                    & Tail,
                    "Trois cibles, chacune a sa place");

      Three.Count := 1;
      Assert_Frame (Encode_Frame (Three), Manual_Frame (Example_Bytes),
                    "Au-dela de Count, les emplacements restent nuls");
   end Test_Slots;

   --  Test 4 : l'emulateur, sans defaut de ligne, emet une trame par
   --  periode, a la gigue pres, et ses octets sont ceux du format.
   procedure Test_Emulator_Cadence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E    : Emulator := Make;
      F    : Emitted_Frame;
      Sent : Boolean;
      Seen : Natural := 0;
   begin
      for K in 1 .. 50 loop
         Next_Frame (E, F, Sent);
         Assert (Sent, "Sans defaut, le module emet a chaque periode");
         Assert (abs (Integer (F.Stamp) - K * Period_Ms)
                   <= Default_Sensor.Jitter_Ms,
                 "Une trame toutes les 100 ms, a la gigue pres");
         Assert (F.Bytes = Encode_Frame (F.Intended)
                   and then F.Corrupted_Byte = 0,
                 "Sans defaut de ligne, les octets sont ceux du format");
         Seen := Seen + F.Intended.Count;
      end loop;
      Assert (Seen > 0, "La scene par defaut fournit des cibles");
   end Test_Emulator_Cadence;

   --  Test 5 : le champ de vision. Sur huit objets, quatre sont visibles ;
   --  le module n'en rapporte que trois, les plus proches, au millimetre
   --  avec le capteur ideal. X du capteur positif a droite (-Y du monde).
   procedure Test_Emulator_Field
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E    : Emulator := Make (Field_Scene, Ideal_Sensor);
      F    : Emitted_Frame;
      Sent : Boolean;
   begin
      Next_Frame (E, F, Sent);
      Assert (Sent and then F.Intended.Count = 3,
              "Quatre objets visibles : les trois plus proches seulement");
      Assert (Close (F.Intended.Targets (1).X_Mm, 500.0)
                and then Close (F.Intended.Targets (1).Y_Mm, 1_000.0),
              "La plus proche d'abord : 500 mm a droite, 1 000 mm devant");
      Assert (Close (F.Intended.Targets (2).X_Mm, 0.0)
                and then Close (F.Intended.Targets (2).Y_Mm, 2_000.0),
              "Puis celle de l'axe, a 2 000 mm");
      Assert (Close (F.Intended.Targets (3).X_Mm,
                     -2_500.0 * Sin (40.0 * Deg))
                and then Close (F.Intended.Targets (3).Y_Mm,
                                2_500.0 * Cos (40.0 * Deg)),
              "Puis celle a 40 deg a gauche, a 2 500 mm");
      Assert (Max_Range_Mm (30.0) = 6_000.0
                and then Max_Range_Mm (61.0) = 0.0,
              "Portee : 6 m a 30 deg, rien au-dela de 60 deg");
   end Test_Emulator_Field;

   --  Test 6 : la physique de la mesure. Une cible 0,6 m plus haute que
   --  le capteur, a 1 m devant, est rapportee a 1 166 mm : le module
   --  mesure la distance oblique. Une cible qui s'eloigne a 1 m/s donne
   --  +100 cm/s, une qui s'approche a 1 m/s, -100 cm/s.
   procedure Test_Emulator_Physics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W    : World := Empty_World;
      F    : Emitted_Frame;
      Sent : Boolean;
   begin
      Add (W, Object_At (1_000.0, 0.0, 600.0));
      Add (W, Object_At (1_200.0, 0.0, 0.0, Vx => 100.0));
      Add (W, Object_At (3_000.0, 0.0, 0.0, Vx => -100.0));
      declare
         E : Emulator := Make (W, Ideal_Sensor);
      begin
         --  Le monde avance d'un pas avant la premiere trame.
         Next_Frame (E, F, Sent);
      end;
      Assert (Sent and then F.Intended.Count = 3, "Trois cibles visibles");
      Assert (Close (F.Intended.Targets (1).Y_Mm, 1_166.2)
                and then Close (F.Intended.Targets (1).Speed_Cm_S, 0.0),
              "Distance oblique : 1 166 mm et non 1 000 ; immobile");
      Assert (Close (F.Intended.Targets (2).Y_Mm, 1_300.0)
                and then Close (F.Intended.Targets (2).Speed_Cm_S, 100.0),
              "Elle s'eloigne a 1 m/s : +100 cm/s");
      Assert (Close (F.Intended.Targets (3).Y_Mm, 2_900.0)
                and then Close (F.Intended.Targets (3).Speed_Cm_S, -100.0),
              "Elle s'approche a 1 m/s : -100 cm/s");
   end Test_Emulator_Physics;

   --  Test 7 : les defauts de l'analyse CEM. Un octet abime differe d'un
   --  seul bit ; une seconde de silence coute dix trames ; apres un
   --  redemarrage, le module reste en mono-cible jusqu'a la commande
   --  multi-cible de l'hote.
   procedure Test_Emulator_Faults
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      F    : Emitted_Frame;
      Sent : Boolean;
      Lost : Natural := 0;
   begin
      declare
         E : Emulator :=
           Make (Faults => (Corrupt_Probability => 1.0, others => <>));
      begin
         for K in 1 .. 20 loop
            Next_Frame (E, F, Sent);
            declare
               Clean : constant Frame_Bytes := Encode_Frame (F.Intended);
               Diffs : Natural := 0;
               Delta_Bits : Natural := 0;
            begin
               for I in Clean'Range loop
                  if F.Bytes (I) /= Clean (I) then
                     Diffs      := Diffs + 1;
                     Delta_Bits :=
                       abs (Integer (F.Bytes (I)) - Integer (Clean (I)));
                  end if;
               end loop;
               Assert (Sent and then Diffs = 1
                         and then F.Corrupted_Byte in Clean'Range
                         and then F.Bytes (F.Corrupted_Byte)
                                    /= Clean (F.Corrupted_Byte)
                         and then Delta_Bits in 1 | 2 | 4 | 8 | 16 | 32
                                                  | 64 | 128,
                       "Octet abime : un seul octet, un seul bit");
            end;
         end loop;
      end;

      declare
         E : Emulator := Make (Field_Scene, Ideal_Sensor);
      begin
         Next_Frame (E, F, Sent);
         Force_Silence (E, 1_000);
         for K in 1 .. 10 loop
            Next_Frame (E, F, Sent);
            if not Sent then
               Lost := Lost + 1;
            end if;
         end loop;
         Next_Frame (E, F, Sent);
         Assert (Lost = 10 and then Sent and then F.Stamp = 1_200,
                 "Une seconde de silence : dix trames perdues, puis la"
                 & " trame de 1 200 ms");

         Force_Restart (E);
         Lost := 0;
         loop
            Next_Frame (E, F, Sent);
            exit when Sent;
            Lost := Lost + 1;
         end loop;
         Assert (Lost = 5 and then F.Intended.Count = 1
                   and then not Multi_Target (E),
                 "Redemarrage : 500 ms muet, puis une seule cible");
         Request_Multi_Target (E);
         Next_Frame (E, F, Sent);
         Assert (Sent and then F.Intended.Count = 3,
                 "La commande multi-cible rend les trois cibles");
      end;
   end Test_Emulator_Faults;

   --  Test 8 : meme graine, memes octets (les tests du parseur en
   --  dependront) ; une autre graine donne une autre suite.
   procedure Test_Emulator_Seed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Faults : constant Fault_Model :=
        (Corrupt_Probability => 0.1, Silence_Probability => 0.02,
         others => <>);
      A      : Emulator := Make (Faults => Faults, Seed => 7);
      B      : Emulator := Make (Faults => Faults, Seed => 7);
      C      : Emulator := Make (Faults => Faults, Seed => 8);
      Fa     : Emitted_Frame;
      Fb     : Emitted_Frame;
      Fc     : Emitted_Frame;
      Sa     : Boolean;
      Sb     : Boolean;
      Sc     : Boolean;
      Same   : Boolean := True;
      Differ : Boolean := False;
   begin
      for K in 1 .. 100 loop
         Next_Frame (A, Fa, Sa);
         Next_Frame (B, Fb, Sb);
         Next_Frame (C, Fc, Sc);
         Same := Same and then Sa = Sb and then Fa.Bytes = Fb.Bytes
                   and then Fa.Stamp = Fb.Stamp;
         Differ := Differ or else Sa /= Sc or else Fa.Bytes /= Fc.Bytes
                     or else Fa.Stamp /= Fc.Stamp;
      end loop;
      Assert (Same, "Meme graine : memes trames, octet pour octet");
      Assert (Differ, "Autre graine : une autre suite");
   end Test_Emulator_Seed;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Manual_Frames'Access,
         "LD2450 : les quatre trames du manuel, octet pour octet");
      Register_Routine
        (T, Test_Signed_Coding'Access,
         "LD2450 : bit de signe aux limites, poids faible en premier");
      Register_Routine
        (T, Test_Slots'Access,
         "LD2450 : emplacements vides, trois cibles, Count fait foi");
      Register_Routine
        (T, Test_Emulator_Cadence'Access,
         "Emulateur : 10 trames/s, octets conformes au format");
      Register_Routine
        (T, Test_Emulator_Field'Access,
         "Emulateur : champ, portee selon l'angle, 3 plus proches");
      Register_Routine
        (T, Test_Emulator_Physics'Access,
         "Emulateur : distance oblique et vitesse radiale");
      Register_Routine
        (T, Test_Emulator_Faults'Access,
         "Emulateur : octet abime, silence, redemarrage mono-cible");
      Register_Routine
        (T, Test_Emulator_Seed'Access,
         "Emulateur : meme graine, memes octets");
   end Register_Tests;

end Radar_Ld2450_Tests;
