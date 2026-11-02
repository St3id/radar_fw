with Ada.Directories;
with Ada.Streams.Stream_IO;
with AUnit.Assertions;          use AUnit.Assertions;
with Radar_Ld2450;              use Radar_Ld2450;
with Radar_Ld2450_Faults;       use Radar_Ld2450_Faults;
with Radar_Ld2450_Log;
with Radar_Ld2450_Plausibility; use Radar_Ld2450_Plausibility;
with Radar_Ld2450_Replay;       use Radar_Ld2450_Replay;
with Radar_Ld2450_Sim;          use Radar_Ld2450_Sim;
with Radar_Ld2450_Stream;       use Radar_Ld2450_Stream;
with Radar_Planar_Source;       use Radar_Planar_Source;
with Radar_Source;
with Radar_World;               use Radar_World;

--  Corps de la suite 5. Chaque test affirme un total ou une position exacte :
--  un parseur qui ne livre rien doit echouer ici, pas passer faute
--  d'assertion atteinte.

package body Radar_Ld2450_Stream_Tests is

   use type Radar_Ld2450_Log.Read_Status;
   use type Radar_Source.Time_Ms;

   --  ----- Faire passer un flux dans le parseur -----

   Max_Deliveries : constant := 64;

   type Delivery is record
      Position : Positive;      --  rang du dernier octet de la trame livree
      Frame    : Decoded_Frame;
   end record;

   type Delivery_List is array (1 .. Max_Deliveries) of Delivery;

   type Run_Result is record
      P     : Parser;
      Count : Natural := 0;
      Items : Delivery_List;
   end record;

   procedure Run (S : Byte_Array; R : in out Run_Result) is
      Frame : Decoded_Frame;
      Ready : Boolean;
   begin
      for I in S'Range loop
         Feed (R.P, S (I), Frame, Ready);
         if Ready then
            Assert (R.Count < Max_Deliveries, "Trop de trames pour ce test");
            R.Count := R.Count + 1;
            R.Items (R.Count) :=
              (Position => I - S'First + 1, Frame => Frame);
         end if;
      end loop;
   end Run;

   --  Le bilan que doit toujours tenir le parseur : aucun octet n'a disparu.
   procedure Assert_Balance (P : Parser; Read : Natural; What : String) is
   begin
      Assert (Bytes_Read (P) = Radar_Ld2450_Stream.Counter (Read),
              What & " : octets lus" & Bytes_Read (P)'Image
              & " au lieu de" & Read'Image);
      Assert (Bytes_Read (P)
                = 30 * Frames_Delivered (P) + Bytes_Discarded (P)
                  + Radar_Ld2450_Stream.Counter (Pending (P)),
              What & " : lus /= 30 x livrees + ecartes + en attente");
      Assert (Is_Consistent (P), What & " : invariant du parseur viole");
   end Assert_Balance;

   function Is_Manual (F : Frame_Bytes; K : Manual_Index) return Boolean is
     (F = Frame_Of (K));

   --  La trame livree dit bien ce que dit le manuel : la cible de reference
   --  dans le premier emplacement, les deux autres nuls.
   procedure Assert_Manual
     (D : Decoded_Frame; K : Manual_Index; What : String)
   is
      Nothing : constant Raw_Target := (others => <>);
   begin
      Assert (Is_Manual (D.Bytes, K),
              What & " : octets differents de la trame" & K'Image);
      Assert (D.Targets (1) = Target_Of (K)
                and then D.Targets (2) = Nothing
                and then D.Targets (3) = Nothing,
              What & " : champs differents du manuel, trame" & K'Image);
   end Assert_Manual;

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Flux LD2450 (parseur, plausibilite, rejeu)");
   end Name;

   --  ----- Le parseur -----

   --  Test 1 : la lecture commence n'importe ou. Depuis chacun des 30
   --  decalages, les quatre trames du manuel suivantes sont retrouvees, dans
   --  l'ordre et sans rien de plus ; un debut coupe n'est jamais livre.
   procedure Test_Start_Offsets
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : constant Byte_Array := Frame_Of (4) & Manual_Stream;
   begin
      for D in 1 .. 29 loop
         declare
            Cut : constant Byte_Array := Drop_Start (S, D);
            R   : Run_Result;
            Tag : constant String := "Decalage" & D'Image;
         begin
            Run (Cut, R);
            Assert (R.Count = 4, Tag & " : " & R.Count'Image & " trames");
            for K in Manual_Index loop
               Assert_Manual (R.Items (K).Frame, K, Tag);
               Assert (R.Items (K).Position = 30 - D + 30 * K,
                       Tag & " : trame livree trop tot ou trop tard");
            end loop;
            Assert_Balance (R.P, Cut'Length, Tag);
            Assert (Bytes_Discarded (R.P)
                      = Radar_Ld2450_Stream.Counter (30 - D),
                    Tag & " : tout le debut coupe doit etre ecarte");
            Assert (Pending (R.P) = 0, Tag & " : rien ne doit rester");
         end;
      end loop;

      declare
         R : Run_Result;
      begin
         Run (S, R);
         Assert (R.Count = 5 and then Bytes_Discarded (R.P) = 0,
                 "Decalage 0 : cinq trames et rien d'ecarte");
         Assert_Manual (R.Items (1).Frame, 4, "Decalage 0");
         for K in Manual_Index loop
            Assert_Manual (R.Items (K + 1).Frame, K, "Decalage 0");
         end loop;
      end;
   end Test_Start_Offsets;

   --  Verifie qu'une trame K est livree exactement a la position attendue, et
   --  pas plus de 59 octets apres la fin du defaut.
   procedure Assert_Resync
     (R          : Run_Result;
      Damage_End : Natural;
      Delay_Then : Positive;
      K          : Manual_Index;
      What       : String)
   is
   begin
      Assert (Delay_Then <= 59,
              What & " : le test attend plus de 59 octets");
      for I in 1 .. R.Count loop
         if R.Items (I).Position = Damage_End + Delay_Then then
            Assert_Manual (R.Items (I).Frame, K, What);
            return;
         end if;
      end loop;
      Assert (False,
              What & " : pas de resynchronisation en" & Delay_Then'Image
              & " octets (" & R.Count'Image & " trames livrees)");
   end Assert_Resync;

   --  Test 2 : 1 a 60 octets parasites inseres a l'un des 30 rangs d'une
   --  trame. La trame suivante intacte sort exactement au moment prevu, donc
   --  en au plus 59 octets. Les parasites sont choisis pour pieger un parseur
   --  qui saute : des en-tetes, des AA, le debut d'une vraie trame.
   procedure Test_Resync_Insertion
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      function Parasite
        (Class : Positive; Count : Positive; Seed : Natural) return Byte_Array
      is
         Headers : constant Byte_Array := Header & Header & Header & Header
           & Header & Header & Header & Header & Header & Header
           & Header & Header & Header & Header & Header;
      begin
         case Class is
            when 1 =>
               return Random_Bytes (Random_State (Seed), Count);
            when 2 =>
               return Headers (1 .. Count);
            when 3 =>
               return (1 .. Count => 16#AA#);
            when others =>
               return Truncate (Manual_Stream, 120 - Count);
         end case;
      end Parasite;

      Base : constant Byte_Array := Manual_Stream;
   begin
      for Class in 1 .. 4 loop
         for K in 0 .. 29 loop
            for N in 1 .. 60 loop
               declare
                  Extra : constant Byte_Array :=
                    Parasite (Class, N, 1_000 * K + N);
                  S     : constant Byte_Array := Insert (Base, K, Extra);
                  R     : Run_Result;
                  Tag   : constant String :=
                    "Insertion classe" & Class'Image & " rang" & K'Image
                    & " de" & N'Image & " octets";
               begin
                  Run (S, R);
                  if K = 0 then
                     Assert_Resync (R, N, 30, 1, Tag);
                  else
                     Assert_Resync (R, K + N, 30 - K + 30, 2, Tag);
                  end if;
                  Assert_Balance (R.P, S'Length, Tag);
                  Assert (Is_Manual (R.Items (R.Count).Frame.Bytes, 4),
                          Tag & " : la derniere trame est perdue");
               end;
            end loop;
         end loop;
      end loop;
   end Test_Resync_Insertion;

   --  Test 3 : 1 a 29 octets perdus a l'un des 30 rangs. Le cas qui tue un
   --  parseur qui vide sa fenetre : une trame amputee de sa fin contient deja
   --  l'en-tete de la suivante.
   procedure Test_Resync_Loss
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Base : constant Byte_Array := Manual_Stream;
   begin
      for K in 0 .. 29 loop
         for L in 1 .. 29 loop
            declare
               S    : constant Byte_Array := Lose (Base, K, L);
               R    : Run_Result;
               Tag  : constant String :=
                 "Perte rang" & K'Image & " de" & L'Image & " octets";
               --  Debut de la premiere trame epargnee, dans le flux d'origine.
               Next : constant Positive := 30 * ((K + L + 29) / 30);
            begin
               Run (S, R);
               Assert_Resync
                 (R, K, Next - (K + L) + 30, Next / 30 + 1, Tag);
               for I in 1 .. R.Count loop
                  Assert
                    ((for some M in Manual_Index =>
                        Is_Manual (R.Items (I).Frame.Bytes, M)),
                     Tag & " : une fausse trame a ete livree");
               end loop;
               Assert_Balance (R.P, S'Length, Tag);
            end;
         end loop;
      end loop;
   end Test_Resync_Loss;

   --  Test 4 : un seul bit faux dans l'en-tete ou la fin, sur chaque rang et
   --  chaque bit : la trame n'est PAS livree, ses 30 octets sont comptes comme
   --  ecartes, et la suivante arrive intacte.
   procedure Test_Marks_Are_Checked
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ranks : constant array (1 .. 6) of Positive := (1, 2, 3, 4, 29, 30);
   begin
      for K in Manual_Index loop
         for Rank of Ranks loop
            for Bit in 0 .. 7 loop
               declare
                  Bad : constant Byte_Array :=
                    Flip_Bit (Frame_Of (K), Rank, Bit);
                  R   : Run_Result;
                  Tag : constant String :=
                    "Trame" & K'Image & " rang" & Rank'Image & " bit"
                    & Bit'Image;
               begin
                  Run (Bad & Frame_Of (K), R);
                  Assert (R.Count = 1 and then R.Items (1).Position = 60,
                          Tag & " : seule la trame intacte doit sortir");
                  Assert_Manual (R.Items (1).Frame, K, Tag);
                  Assert (Bytes_Discarded (R.P) = 30,
                          Tag & " : 30 octets ecartes attendus");
               end;
            end loop;
         end loop;
      end loop;
   end Test_Marks_Are_Checked;

   --  Test 5 : la troncature. Une trame coupee n'est pas livree ; ce qui en
   --  reste attend en fenetre, puis laisse passer la trame suivante.
   procedure Test_Truncation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Cut in 1 .. 29 loop
         declare
            Part : constant Byte_Array := Truncate (Frame_Of (1), Cut);
            R    : Run_Result;
            Tag  : constant String := "Troncature de" & Cut'Image;
         begin
            Run (Part, R);
            Assert (R.Count = 0, Tag & " : aucune trame ne doit sortir");
            Assert (Pending (R.P) = 30 - Cut
                      and then Bytes_Discarded (R.P) = 0,
                    Tag & " : le debut valide doit rester en fenetre");
            Assert_Balance (R.P, Part'Length, Tag);

            Run (Frame_Of (2), R);
            Assert (R.Count = 1 and then Pending (R.P) = 0,
                    Tag & " : la trame suivante doit sortir");
            Assert_Manual (R.Items (1).Frame, 2, Tag);
            Assert (Bytes_Discarded (R.P)
                      = Radar_Ld2450_Stream.Counter (30 - Cut),
                    Tag & " : le debut coupe doit etre ecarte");
         end;
      end loop;
   end Test_Truncation;

   --  Test 6 : une reponse de commande (FD FC FB FA ... 04 03 02 01) entre
   --  deux trames, puis au milieu d'une trame : elle ne produit rien et ne
   --  casse que ce qu'elle coupe.
   procedure Test_Ack_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : Run_Result;
   begin
      Run (Frame_Of (1) & Ack_Frame & Frame_Of (2) & Ack_Frame & Ack_Frame
           & Frame_Of (3), R);
      Assert (R.Count = 3, "Trois trames autour des reponses de commande");
      Assert_Manual (R.Items (1).Frame, 1, "Avant la reponse");
      Assert_Manual (R.Items (2).Frame, 2, "Entre les reponses");
      Assert_Manual (R.Items (3).Frame, 3, "Apres les reponses");
      Assert (Bytes_Discarded (R.P) = 3 * Ack_Frame'Length,
              "Les octets des reponses sont comptes comme ecartes");

      declare
         S : constant Byte_Array :=
           Insert (Manual_Stream, 15, Ack_Frame);
         C : Run_Result;
      begin
         Run (S, C);
         Assert (C.Count = 3, "Une reponse au milieu coute une trame");
         for K in 2 .. 4 loop
            Assert_Manual (C.Items (K - 1).Frame, K, "Reponse au milieu");
         end loop;
         Assert_Balance (C.P, S'Length, "Reponse au milieu");
      end;
   end Test_Ack_Frames;

   --  Test 7 : un million d'octets pseudo-aleatoires. Aucune exception (les
   --  contrats sont actifs dans ce profil), le bilan tenu a chaque octet, et
   --  aucune trame : six octets imposes sur 2 ** 48 ne tombent pas ici.
   procedure Test_Random_Million
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Total : constant := 1_000_000;
      S     : Random_State := 20_261_102;
      B     : Byte;
      P     : Parser;
      Frame : Decoded_Frame;
      Ready : Boolean;
      Peak  : Natural := 0;
   begin
      for I in 1 .. Total loop
         Next_Byte (S, B);
         Feed (P, B, Frame, Ready);
         Assert (not Ready, "Une trame dans du hasard, octet" & I'Image);
         Assert (Bytes_Read (P)
                   = Bytes_Discarded (P)
                     + Radar_Ld2450_Stream.Counter (Pending (P)),
                 "Lus /= ecartes + en attente a l'octet" & I'Image);
         Peak := Natural'Max (Peak, Pending (P));
      end loop;
      Assert_Balance (P, Total, "Hasard");
      Assert (Frames_Delivered (P) = 0, "Hasard : aucune trame attendue");
      Assert (Bytes_Discarded (P) >= Total - 29,
              "Hasard : presque tout doit etre ecarte");
      Assert (Peak >= 1 and then Peak < 29,
              "Hasard : la fenetre doit s'ouvrir sur un AA, sans se remplir");
   end Test_Random_Million;

   --  Test 8 : des trames du manuel noyees dans le bruit. Avant chacune, de 0
   --  a 63 octets de hasard : toutes sortent, dans l'ordre, au bon octet.
   procedure Test_Frames_In_Noise
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S     : Random_State := 7;
      B     : Byte;
      P     : Parser;
      Frame : Decoded_Frame;
      Ready : Boolean;
      Read  : Natural := 0;
   begin
      for N in 1 .. 20_000 loop
         Next_Byte (S, B);
         for I in 1 .. Natural (B) / 4 loop
            Next_Byte (S, B);
            Feed (P, B, Frame, Ready);
            Read := Read + 1;
            Assert (not Ready, "Une trame sortie du bruit, tour" & N'Image);
         end loop;
         declare
            K : constant Manual_Index := (N - 1) mod 4 + 1;
            F : constant Frame_Bytes  := Frame_Of (K);
         begin
            for I in F'Range loop
               Feed (P, F (I), Frame, Ready);
               Read := Read + 1;
               Assert (Ready = (I = F'Last),
                       "Trame du tour" & N'Image & " livree a l'octet"
                       & I'Image);
            end loop;
            Assert_Manual (Frame, K, "Bruit, tour" & N'Image);
         end;
      end loop;
      Assert (Frames_Delivered (P) = 20_000,
              "Les 20 000 trames doivent sortir");
      Assert_Balance (P, Read, "Bruit");
   end Test_Frames_In_Noise;

   --  Test 9 : l'emulateur avec ses defauts de liaison. Trame intacte : livree
   --  et egale a Intended. Octet abime dans l'en-tete ou la fin : pas livree.
   --  Octet abime au milieu : livree telle quelle, car rien dans le format ne
   --  permet de le voir (voir la plausibilite).
   procedure Test_Emulator_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E : Emulator :=
        Make (Faults => (Corrupt_Probability => 0.2,
                         Silence_Probability => 0.02,
                         Silence_Ms          => 500,
                         Restart_Probability => 0.005,
                         Restart_Ms          => 500),
              Seed   => 2_026);
      P        : Parser;
      F        : Emitted_Frame;
      Sent     : Boolean;
      Frame    : Decoded_Frame;
      Ready    : Boolean;
      Read     : Natural := 0;
      Intact   : Natural := 0;
      Marks    : Natural := 0;
      Body_Hit : Natural := 0;
      Quiet    : Natural := 0;
   begin
      for N in 1 .. 3_000 loop
         Next_Frame (E, F, Sent);
         if Sent then
            for I in F.Bytes'Range loop
               Feed (P, F.Bytes (I), Frame, Ready);
               Read := Read + 1;
               Assert (I = F.Bytes'Last or else not Ready,
                       "Periode" & N'Image & " : trame livree au milieu");
            end loop;

            if F.Corrupted_Byte = 0 then
               Assert (Ready and then Frame.Bytes = F.Bytes
                         and then Frame.Targets = F.Intended.Targets,
                       "Periode" & N'Image & " : trame intacte /= Intended");
               Intact := Intact + 1;
            elsif F.Corrupted_Byte <= Header_Length
              or else F.Corrupted_Byte >= Tail_First
            then
               Assert (not Ready,
                       "Periode" & N'Image & " : marque abimee mais livree");
               Marks := Marks + 1;
            else
               Assert (Ready and then Frame.Bytes = F.Bytes,
                       "Periode" & N'Image & " : corps abime non livre");
               Body_Hit := Body_Hit + 1;
            end if;
         else
            Quiet := Quiet + 1;
         end if;
      end loop;

      Assert (Intact > 1_000 and then Marks > 20 and then Body_Hit > 100
                and then Quiet > 100,
              "Le scenario doit exercer chaque cas :" & Intact'Image
              & Marks'Image & Body_Hit'Image & Quiet'Image);
      Assert (Frames_Delivered (P)
                = Radar_Ld2450_Stream.Counter (Intact + Body_Hit),
              "Chaque trame livree doit etre comptee");
      Assert_Balance (P, Read, "Emulateur");
   end Test_Emulator_Stream;

   --  ----- La plausibilite -----

   function Slots_With (T : Raw_Target) return Raw_Target_Array is
     (1 => T, others => <>);

   Good : constant Raw_Target := (-782, 1_713, -16, 320);

   --  Test 10 : un emplacement tout a zeros est valide et absent : aucun
   --  rejet. Une trame sans cible donne un rapport vide, sans erreur.
   procedure Test_Empty_Is_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      V : Validator;
      R : Raw_Report;
   begin
      Validate (V, (others => <>), 100, R);
      Assert (R.Count = 0, "Tous zeros : aucune cible");
      Assert (Absent (V) = 3 and then Accepted (V) = 0,
              "Trois emplacements absents, rien d'accepte");
      for Why in Reject_Reason loop
         Assert (Rejected (V, Why) = 0,
                 "Tous zeros n'est pas un rejet : " & Why'Image);
      end loop;

      Validate (V, Slots_With (Good), 100, R);
      Assert (R.Count = 1 and then R.Targets (1) = Good,
              "Une cible et deux absents");
      Assert (Absent (V) = 5 and then Accepted (V) = 1,
              "Les compteurs cumulent");
   end Test_Empty_Is_Absent;

   --  Test 11 : chaque motif incremente SON compteur, et lui seul. Les valeurs
   --  du manuel passent toutes ; juste a la borne passe, juste au-dela non.
   procedure Test_Reject_Reasons
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Target : Raw_Target; Why : Reject_Reason; What : String)
      is
         V : Validator;
         R : Raw_Report;
      begin
         Validate (V, Slots_With (Target), 100, R);
         Assert (R.Count = 0, What & " : la cible aurait du etre rejetee");
         for Other in Reject_Reason loop
            Assert (Rejected (V, Other) = (if Other = Why then 1 else 0),
                    What & " : mauvais compteur " & Other'Image);
         end loop;
         Assert (Accepted (V) = 0, What & " : comptee comme acceptee");
      end Check;

      procedure Check_Passes (Target : Raw_Target; What : String) is
         V : Validator;
         R : Raw_Report;
      begin
         Validate (V, Slots_With (Target), 100, R);
         Assert (R.Count = 1 and then R.Targets (1) = Target,
                 What & " : la cible aurait du passer");
      end Check_Passes;
   begin
      for K in Manual_Index loop
         Check_Passes (Target_Of (K), "Trame du manuel" & K'Image);
      end loop;

      Check ((0, -1, 0, 360), Reject_Not_In_Front, "y negatif");
      Check ((500, 0, 0, 360), Reject_Not_In_Front, "y nul");
      Check ((0, 10_001, 0, 360), Reject_Out_Of_Range, "y hors de portee");
      Check ((8_000, 6_001, 0, 360), Reject_Out_Of_Range,
             "Diagonale hors de portee");
      Check_Passes ((6_000, 8_000, 0, 360), "Diagonale a 10 m pile");
      Check ((0, 1_000, 1_001, 360), Reject_Too_Fast, "Trop rapide");
      Check ((0, 1_000, -1_001, 360), Reject_Too_Fast, "Trop rapide, recule");
      Check_Passes ((0, 1_000, -1_000, 360), "Vitesse a la borne");
      Check ((0, 1_000, 0, 0), Reject_Bad_Resolution, "Resolution nulle");
      Check ((0, 1_000, 0, 199), Reject_Bad_Resolution, "Resolution basse");
      Check ((0, 1_000, 0, 501), Reject_Bad_Resolution, "Resolution haute");
      Check_Passes ((0, 1_000, 0, 200), "Resolution a la borne basse");
      Check_Passes ((0, 1_000, 0, 500), "Resolution a la borne haute");
   end Test_Reject_Reasons;

   --  Test 12 : la porte de saut. Un saut isole est rejete puis la position
   --  d'avant reprend sans rejet ; deux trames d'accord sur une nouvelle
   --  position la font accepter ; dt = 0 laisse la porte a son plus etroit ;
   --  apres un long silence, le passe est oublie.
   procedure Test_Jump_Gate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Here  : constant Raw_Target := (0, 2_000, 0, 360);
      Far   : constant Raw_Target := (4_000, 2_000, 0, 360);
      R     : Raw_Report;
   begin
      Assert (Jump_Gate (0) = Jump_Margin_Mm
                and then Jump_Gate (100) = 1_800
                and then Jump_Gate (1_000_000) = 7_500,
              "Largeur de la porte : marge + 3 m/s x dt, dt borne");

      declare
         V : Validator;
      begin
         Validate (V, Slots_With (Here), 0, R);
         Assert (R.Count = 1, "Premiere trame : rien a comparer");
         Validate (V, Slots_With (Far), 100, R);
         Assert (R.Count = 0 and then Rejected (V, Reject_Jump) = 1,
                 "Saut isole de 4 m en 100 ms : rejete");
         Validate (V, Slots_With (Here), 100, R);
         Assert (R.Count = 1 and then Rejected (V, Reject_Jump) = 1,
                 "Retour a la position d'avant : sans nouveau rejet");
      end;

      declare
         V : Validator;
      begin
         Validate (V, Slots_With (Here), 0, R);
         Validate (V, Slots_With (Far), 100, R);
         Validate (V, Slots_With (Far), 100, R);
         Assert (R.Count = 1 and then R.Targets (1) = Far
                   and then Rejected (V, Reject_Jump) = 1,
                 "Deux trames d'accord : la nouvelle position est acceptee");
      end;

      declare
         V    : Validator;
         Near : constant Raw_Target := (1_400, 2_000, 0, 360);
         Wide : constant Raw_Target := (1_600, 2_000, 0, 360);
      begin
         Validate (V, Slots_With (Here), 0, R);
         Validate (V, Slots_With (Near), 0, R);
         Assert (R.Count = 1, "dt = 0, dans la marge : accepte");
         Validate (V, Slots_With (Here), 0, R);
         Validate (V, Slots_With (Wide), 0, R);
         Assert (R.Count = 0, "dt = 0, au-dela de la marge : rejete");
      end;

      declare
         V : Validator;
      begin
         Validate (V, Slots_With (Here), 0, R);
         Validate (V, Slots_With (Far), Jump_Forget_Ms, R);
         Assert (R.Count = 1 and then Rejected (V, Reject_Jump) = 0,
                 "Apres un long silence, le passe est oublie");
      end;

      declare
         V : Validator;
      begin
         Validate (V, Slots_With (Here), 0, R);
         Validate (V, (others => <>), 100, R);
         Validate (V, Slots_With (Far), 100, R);
         Assert (R.Count = 1 and then Rejected (V, Reject_Jump) = 0,
                 "Emplacement vide entre-temps : une cible neuve n'est pas"
                 & " un saut");
      end;
   end Test_Jump_Gate;

   --  Test 13 : ce que le filtre voit d'un bit inverse dans le corps. Sur les
   --  4 trames du manuel, x 192 bits, le parseur livre toujours : c'est la
   --  limite du format. Le filtre en rejette 577 sur 768 avec ces seuils ;
   --  les autres ne deplacent la cible que dans la porte. Ce total n'est pas
   --  une performance : il depend d'hypotheses a remesurer.
   procedure Test_Body_Bit_Flips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Total    : Natural := 0;
      Caught   : Natural := 0;
      Gate     : constant Integer := Jump_Gate (100);
   begin
      for K in Manual_Index loop
         for Rank in Header_Length + 1 .. Tail_First - 1 loop
            for Bit in 0 .. 7 loop
               declare
                  V    : Validator;
                  R    : Raw_Report;
                  Run1 : Run_Result;
                  Good_F : constant Frame_Bytes := Frame_Of (K);
                  Bad  : constant Frame_Bytes :=
                    Flip_Bit (Good_F, Rank, Bit);
                  Tag  : constant String :=
                    "Trame" & K'Image & " rang" & Rank'Image & " bit"
                    & Bit'Image;
                  Before : Radar_Ld2450_Plausibility.Counter := 0;
                  After  : Radar_Ld2450_Plausibility.Counter := 0;
               begin
                  Run (Good_F & Bad, Run1);
                  Assert (Run1.Count = 2,
                          Tag & " : le format ne permet pas de la refuser");
                  Validate (V, Run1.Items (1).Frame.Targets, 100, R);
                  Assert (R.Count = 1 and then R.Targets (1) = Target_Of (K),
                          Tag & " : la trame saine doit passer");

                  for Why in Reject_Reason loop
                     Before := Before + Rejected (V, Why);
                  end loop;
                  Validate (V, Run1.Items (2).Frame.Targets, 100, R);
                  for Why in Reject_Reason loop
                     After := After + Rejected (V, Why);
                  end loop;

                  Total := Total + 1;
                  if After > Before then
                     Caught := Caught + 1;
                  end if;

                  for I in 1 .. R.Count loop
                     Assert
                       (Static_Verdict (R.Targets (I)) = Plausible,
                        Tag & " : une cible implausible a passe");
                     if I = 1 then
                        Assert
                          (abs (Integer (R.Targets (I).X_Mm)
                                - Integer (Target_Of (K).X_Mm)) <= Gate
                             and then
                           abs (Integer (R.Targets (I).Y_Mm)
                                - Integer (Target_Of (K).Y_Mm)) <= Gate,
                           Tag & " : un saut hors porte a passe");
                     end if;
                  end loop;
               end;
            end loop;
         end loop;
      end loop;
      Assert (Total = 768, "4 trames x 24 octets x 8 bits");
      Assert (Caught = 577,
              "Bits inverses rejetes :" & Caught'Image & " sur 768");
   end Test_Body_Bit_Flips;

   --  ----- Le fichier de capture et le rejeu -----

   Test_Dir : constant String := "out";

   function Test_Path (Name : String) return String is
     (Test_Dir & "/test_ld2450_" & Name & ".bin");

   procedure Remove (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove;

   procedure Start_Log (W : in out Radar_Ld2450_Log.Writer; Path : String) is
      Ok : Boolean;
   begin
      Ada.Directories.Create_Path (Test_Dir);
      Radar_Ld2450_Log.Create (W, Path, Ok);
      Assert (Ok, "Impossible de creer " & Path);
   end Start_Log;

   --  Ajoute des octets bruts a la fin d'un fichier : pour le fabriquer abime.
   procedure Append_Raw (Path : String; Bytes : Byte_Array) is
      use Ada.Streams;
      File : Stream_IO.File_Type;
   begin
      Stream_IO.Open (File, Stream_IO.Append_File, Path);
      for B of Bytes loop
         Stream_IO.Write (File, (1 => Stream_Element (B)));
      end loop;
      Stream_IO.Close (File);
   end Append_Raw;

   --  Une scene qui bouge doucement, trois cibles dans le champ. Le capteur
   --  ideal rend des valeurs exactes et plausibles.
   function Moving_Scene return World is
      W : World := Empty_World;
   begin
      W.Count := 3;
      W.Objects (1) :=
        (Id => 1, X => 1_000.0, Y => -500.0, Z => 0.0,
         Vx => 5.0, Vy => 0.0, Vz => 0.0);
      W.Objects (2) :=
        (Id => 2, X => 2_500.0, Y => 300.0, Z => 0.0,
         Vx => -4.0, Vy => 2.0, Vz => 0.0);
      W.Objects (3) :=
        (Id => 3, X => 4_000.0, Y => 0.0, Z => 0.0,
         Vx => 3.0, Vy => -1.0, Vz => 0.0);
      return W;
   end Moving_Scene;

   --  Test 14 : le rejeu rend les memes rapports que ce que le module a voulu
   --  envoyer, meme decoupe en blocs qui coupent les trames en deux. Valeurs,
   --  unite de vitesse, heure du bloc qui contient la fin de trame : tout est
   --  compare a Intended, et non a une seconde passe du meme code.
   procedure Test_Replay_Same_Reports
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path    : constant String := Test_Path ("same");
      Frames  : constant := 200;
      Sizes   : constant array (1 .. 5) of Positive := (1, 7, 30, 45, 13);
      All_Raw : Byte_Array (1 .. Frames * Frame_Length);
      Expected : array (1 .. Frames) of Raw_Report;
      Stamps   : array (1 .. Frames) of Radar_Source.Time_Ms;
      Tail_Stamp : array (1 .. Frames) of Radar_Source.Time_Ms;
   begin
      declare
         E    : Emulator := Make (Moving_Scene, Ideal_Sensor);
         F    : Emitted_Frame;
         Sent : Boolean;
      begin
         for N in 1 .. Frames loop
            Next_Frame (E, F, Sent);
            Assert (Sent, "Sans defaut, le module emet");
            All_Raw ((N - 1) * Frame_Length + 1 .. N * Frame_Length) :=
              F.Bytes;
            Expected (N) := F.Intended;
            Stamps (N)   := F.Stamp;
            Assert (F.Intended.Count = 3, "Trois cibles dans le champ");
         end loop;
      end;

      declare
         W     : Radar_Ld2450_Log.Writer;
         First : Positive := 1;
         Pick  : Positive := 1;
      begin
         Start_Log (W, Path);
         while First <= All_Raw'Last loop
            declare
               Last  : constant Positive :=
                 Positive'Min (First + Sizes (Pick) - 1, All_Raw'Last);
               --  Le bloc recoit l'heure de la trame de son dernier octet.
               Owner : constant Positive := (Last - 1) / Frame_Length + 1;
            begin
               Radar_Ld2450_Log.Append
                 (W, Stamps (Owner), All_Raw (First .. Last));
               --  Toute trame qui finit dans ce bloc sort a cette heure-la.
               for N in 1 .. Frames loop
                  if N * Frame_Length in First .. Last then
                     Tail_Stamp (N) := Stamps (Owner);
                  end if;
               end loop;
               First := Last + 1;
               Pick  := Pick mod Sizes'Last + 1;
            end;
         end loop;
         Radar_Ld2450_Log.Close (W);
      end;

      declare
         S         : Replay_Source;
         Ok        : Boolean;
         R         : Planar_Report;
         Available : Boolean;
      begin
         Open (S, Path, Sensor => 4, Ok => Ok);
         Assert (Ok and then Has_More (S), "Le fichier doit s'ouvrir");

         for N in 1 .. Frames loop
            Next_Report (S, R, Available);
            Assert (Available, "Rapport" & N'Image & " absent");
            Assert (R.Stamp = Tail_Stamp (N),
                    "Rapport" & N'Image & " : mauvaise heure");
            Assert (R.Sensor = 4, "Le rapport nomme son capteur");
            Assert (R.Count = Expected (N).Count,
                    "Rapport" & N'Image & " : nombre de cibles");
            for I in 1 .. R.Count loop
               Assert
                 (R.Items (I).X_Mm = Float (Expected (N).Targets (I).X_Mm)
                    and then
                  R.Items (I).Y_Mm = Float (Expected (N).Targets (I).Y_Mm)
                    and then
                  R.Items (I).Speed_Mm_S =
                    10.0 * Float (Expected (N).Targets (I).Speed_Cm_S),
                  "Rapport" & N'Image & " cible" & I'Image & " differente");
            end loop;
         end loop;

         Next_Report (S, R, Available);
         Assert (not Available and then not Has_More (S),
                 "Apres 200 rapports : fin du fichier");
         Assert (Stop_Reason (S) = Radar_Ld2450_Log.End_Of_Log,
                 "Arret propre attendu");
         Assert (Silences (S) = 0, "Aucun silence dans ce flux");
         Assert (Frames_Delivered (Stream (S)) = Frames
                   and then Bytes_Discarded (Stream (S)) = 0,
                 "Le parseur a tout livre, rien ecarte");
         Assert (Accepted (Checks (S)) = 3 * Frames,
                 "Le filtre a tout accepte");
      end;
      Remove (Path);
   end Test_Replay_Same_Reports;

   --  Test 15 : silence et fin ne se confondent pas. Un trou dans les heures
   --  donne Available = False et Has_More = True, une seule fois ; un module
   --  devenu muet (blocs vides) aussi ; seule la fin du fichier met Has_More
   --  a False.
   procedure Test_Replay_Silence_Or_End
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant String := Test_Path ("silence");
      Last_Stamp : Radar_Source.Time_Ms := 0;
      Sent_Count : Natural := 0;
   begin
      declare
         W    : Radar_Ld2450_Log.Writer;
         E    : Emulator := Make (Moving_Scene, Ideal_Sensor);
         F    : Emitted_Frame;
         Sent : Boolean;
      begin
         Start_Log (W, Path);
         for N in 1 .. 30 loop
            if N = 11 then
               Force_Silence (E, 1_000);
            end if;
            Next_Frame (E, F, Sent);
            if Sent then
               Radar_Ld2450_Log.Append (W, F.Stamp, F.Bytes);
               Last_Stamp := F.Stamp;
               Sent_Count := Sent_Count + 1;
            end if;
         end loop;
         --  Le module se tait : l'enregistreur ecrit des blocs vides.
         Radar_Ld2450_Log.Append
           (W, Last_Stamp + 200, (1 .. 0 => 0));
         Radar_Ld2450_Log.Append
           (W, Last_Stamp + 1_000, (1 .. 0 => 0));
         Radar_Ld2450_Log.Append
           (W, Last_Stamp + 2_000, (1 .. 0 => 0));
         Radar_Ld2450_Log.Close (W);
      end;
      Assert (Sent_Count = 20, "Dix periodes de silence");

      declare
         S         : Replay_Source;
         Ok        : Boolean;
         R         : Planar_Report;
         Available : Boolean;
         Reports   : Natural := 0;
         Holes     : Natural := 0;
         Finals    : Natural := 0;
      begin
         Open (S, Path, Ok => Ok);
         Assert (Ok, "Le fichier doit s'ouvrir");
         while Has_More (S) loop
            Next_Report (S, R, Available);
            if Available then
               Reports := Reports + 1;
            elsif Has_More (S) then
               Holes := Holes + 1;
               Assert (Reports = 10 or else Reports = 20,
                       "Silence au mauvais endroit, apres"
                       & Reports'Image & " rapports");
            else
               Finals := Finals + 1;
            end if;
            Assert (Holes + Reports + Finals <= 23, "Lecture sans fin");
         end loop;
         Assert (Reports = 20, "Tous les rapports, malgre les silences");
         Assert (Holes = 2 and then Silences (S) = 2,
                 "Deux silences : le trou et le module muet");
         Assert (Finals = 1, "Une seule fin");
         Assert (Stop_Reason (S) = Radar_Ld2450_Log.End_Of_Log,
                 "Fin propre");

         Next_Report (S, R, Available);
         Assert (not Available and then not Has_More (S),
                 "Apres la fin, plus rien");
      end;
      Remove (Path);
   end Test_Replay_Silence_Or_End;

   --  Test 16 : des fichiers abimes ne levent aucune exception. Absent,
   --  mauvais en-tete, coupe en plein bloc, longueur ou heure hors format,
   --  heures qui reculent : chaque cas dit pourquoi il s'arrete, et ce qui
   --  precede reste livre.
   procedure Test_Replay_Bad_Files
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Path : constant String := Test_Path ("bad");

      procedure Good_Start is
         W : Radar_Ld2450_Log.Writer;
      begin
         Start_Log (W, Path);
         Radar_Ld2450_Log.Append (W, 100, Frame_Of (1));
         Radar_Ld2450_Log.Close (W);
      end Good_Start;

      procedure Expect_Stop
        (Why : Radar_Ld2450_Log.Read_Status; What : String)
      is
         S         : Replay_Source;
         Ok        : Boolean;
         R         : Planar_Report;
         Available : Boolean;
      begin
         Open (S, Path, Ok => Ok);
         Assert (Ok, What & " : l'en-tete est bon");
         Next_Report (S, R, Available);
         Assert (Available and then R.Count = 1 and then R.Stamp = 100,
                 What & " : la trame intacte doit sortir");
         Next_Report (S, R, Available);
         Assert (not Available and then not Has_More (S),
                 What & " : la lecture doit s'arreter");
         Assert (Stop_Reason (S) = Why, What & " : mauvais motif d'arret");
      end Expect_Stop;
   begin
      declare
         S         : Replay_Source;
         Ok        : Boolean;
         R         : Planar_Report;
         Available : Boolean;
      begin
         Remove (Path);
         Open (S, Path, Ok => Ok);
         Assert (not Ok and then not Has_More (S), "Fichier absent");
         Next_Report (S, R, Available);
         Assert (not Available, "Fichier absent : rien a livrer");

         Ada.Directories.Create_Path (Test_Dir);
         declare
            use Ada.Streams;
            File : Stream_IO.File_Type;
         begin
            Stream_IO.Create (File, Stream_IO.Out_File, Path);
            Stream_IO.Write (File, (1 .. 12 => 16#41#));
            Stream_IO.Close (File);
         end;
         Open (S, Path, Ok => Ok);
         Assert (not Ok and then not Has_More (S), "Mauvais en-tete");
      end;

      Good_Start;
      Append_Raw (Path, (16#C8#, 0, 0));
      Expect_Stop (Radar_Ld2450_Log.Truncated, "Coupe dans l'entete de bloc");

      Good_Start;
      Append_Raw (Path, (16#C8#, 0, 0, 0, 30, 0, 16#AA#, 16#FF#));
      Expect_Stop (Radar_Ld2450_Log.Truncated, "Coupe dans le bloc");

      Good_Start;
      Append_Raw (Path, (16#C8#, 0, 0, 0, 16#01#, 16#10#));
      Expect_Stop (Radar_Ld2450_Log.Malformed, "Longueur de 4 097 octets");

      Good_Start;
      Append_Raw (Path, (0, 0, 0, 16#80#, 1, 0, 16#AA#));
      Expect_Stop (Radar_Ld2450_Log.Malformed, "Heure au-dela de 2 ** 31 - 1");

      --  Des heures qui reculent : pas d'exception, et dt = 0 pour le filtre.
      declare
         W         : Radar_Ld2450_Log.Writer;
         S         : Replay_Source;
         Ok        : Boolean;
         R         : Planar_Report;
         Available : Boolean;
      begin
         Start_Log (W, Path);
         Radar_Ld2450_Log.Append (W, 250, Frame_Of (1));
         Radar_Ld2450_Log.Append (W, 100, Frame_Of (1));
         Radar_Ld2450_Log.Close (W);
         Open (S, Path, Ok => Ok);
         Next_Report (S, R, Available);
         Assert (Available and then R.Stamp = 250, "Premiere heure");
         Next_Report (S, R, Available);
         Assert (Available and then R.Stamp = 100 and then R.Count = 1,
                 "L'heure recule : le rapport sort, avec son heure");
      end;
      Remove (Path);
   end Test_Replay_Bad_Files;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Start_Offsets'Access,
         "Parseur : 4 trames du manuel depuis chacun des 30 decalages");
      Register_Routine
        (T, Test_Resync_Insertion'Access,
         "Parseur : resynchro en 59 octets apres insertion de 1 a 60");
      Register_Routine
        (T, Test_Resync_Loss'Access,
         "Parseur : resynchro en 59 octets apres perte de 1 a 29");
      Register_Routine
        (T, Test_Marks_Are_Checked'Access,
         "Parseur : un bit faux dans l'en-tete ou la fin, trame refusee");
      Register_Routine
        (T, Test_Truncation'Access,
         "Parseur : trame tronquee non livree, suivante intacte");
      Register_Routine
        (T, Test_Ack_Frames'Access,
         "Parseur : reponses de commande ecartees et comptees");
      Register_Routine
        (T, Test_Random_Million'Access,
         "Parseur : 1 000 000 d'octets aleatoires, bilan tenu");
      Register_Routine
        (T, Test_Frames_In_Noise'Access,
         "Parseur : 20 000 trames noyees dans le bruit, toutes livrees");
      Register_Routine
        (T, Test_Emulator_Stream'Access,
         "Parseur : emulateur avec defauts, trame intacte = Intended");
      Register_Routine
        (T, Test_Empty_Is_Absent'Access,
         "Plausibilite : tous zeros valide et absent");
      Register_Routine
        (T, Test_Reject_Reasons'Access,
         "Plausibilite : un compteur par motif, bornes exactes");
      Register_Routine
        (T, Test_Jump_Gate'Access,
         "Plausibilite : porte de saut, confirmation, dt = 0, oubli");
      Register_Routine
        (T, Test_Body_Bit_Flips'Access,
         "Plausibilite : 768 bits inverses, limite du format mesuree");
      Register_Routine
        (T, Test_Replay_Same_Reports'Access,
         "Rejeu : memes rapports que Intended, blocs coupant les trames");
      Register_Routine
        (T, Test_Replay_Silence_Or_End'Access,
         "Rejeu : silence et fin de fichier distingues");
      Register_Routine
        (T, Test_Replay_Bad_Files'Access,
         "Rejeu : fichiers abimes, sans exception, motif d'arret");
   end Register_Tests;

end Radar_Ld2450_Stream_Tests;
