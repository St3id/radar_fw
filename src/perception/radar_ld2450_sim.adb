with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

--  Corps de Radar_Ld2450_Sim. Le modele de mesure est celui d'un capteur a
--  deux antennes de reception horizontales : il mesure une distance
--  OBLIQUE et l'angle que font voir ces deux antennes, puis en deduit
--  X = R sin(angle) et Y = R cos(angle). Une cible plus haute ou plus
--  basse que lui parait donc plus loin qu'elle n'est a l'horizontale
--  (Radar_Planar_Source documente cet effet).

package body Radar_Ld2450_Sim is

   Deg : constant Float := Pi / 180.0;

   --  Pas du monde par seconde : un pas dure une periode.
   Steps_Per_Second : constant Float := 1_000.0 / Float (Period_Ms);

   --  ----- Le generateur pseudo-aleatoire -----

   --  Congruentiel lineaire, constantes de Numerical Recipes. Ici, le
   --  rebouclage silencieux du type modulaire EST l'algorithme : le calcul
   --  se fait modulo 2**32 par construction. Ada.Numerics.Float_Random
   --  n'est pas utilise : sa suite peut changer avec la version du
   --  compilateur, alors que la meme graine doit donner les memes octets
   --  partout, puisque ces octets servent de reference aux tests.
   procedure Draw (S : in out Random_State; U : out Float) is
   begin
      S := S * 1_664_525 + 1_013_904_223;
      --  Les 24 bits de poids fort : un Float les represente exactement,
      --  donc U reste strictement inferieur a 1.
      U := Float (S / 2 ** 8) / 2.0 ** 24;
   end Draw;

   --  Tirage uniforme dans [Low, High[.
   procedure Uniform
     (E         : in out Emulator;
      Low, High : Float;
      V         : out Float)
   is
      U : Float;
   begin
      Draw (E.Rng, U);
      V := Low + (High - Low) * U;
   end Uniform;

   --  Vrai avec la probabilite P. Le tirage a lieu meme si P vaut 0 : la
   --  suite aleatoire ne depend ainsi pas des reglages de defauts, et la
   --  meme scene reste bruitee de la meme facon avec ou sans eux.
   procedure Chance (E : in out Emulator; P : Float; Hit : out Boolean) is
      U : Float;
   begin
      Draw (E.Rng, U);
      Hit := U < P;
   end Chance;

   ------------------
   -- Max_Range_Mm --
   ------------------

   function Max_Range_Mm (Azimuth_Deg : Float) return Float is
      A : constant Float := abs Azimuth_Deg;
   begin
      if A <= 30.0 then
         return 8_000.0 - 2_000.0 * A / 30.0;
      elsif A <= 45.0 then
         return 6_000.0 - 1_000.0 * (A - 30.0) / 15.0;
      elsif A <= 60.0 then
         return 5_000.0 - 4_000.0 * (A - 45.0) / 15.0;
      else
         return 0.0;
      end if;
   end Max_Range_Mm;

   --  ----- L'observation de la scene -----

   --  Ce que le module mesurerait d'un objet, sans bruit.
   type Candidate is record
      Slant_Mm    : Float;   --  distance oblique
      Angle_Deg   : Float;   --  angle vu par les deux antennes
      Radial_Mm_S : Float;   --  vitesse radiale, positive s'il s'eloigne
   end record;

   type Candidate_Array is array (1 .. Max_Objects) of Candidate;

   --  Une valeur en mm ou en cm/s, arrondie et bornee a ce que la trame
   --  sait coder.
   function To_Value (F : Float) return Signed_Value is
     (Signed_Value (Float'Max (-Float (Max_Magnitude),
                               Float'Min (Float (Max_Magnitude), F))));

   --  Le bruit d'angle grandit du centre vers le bord du champ.
   function Angle_Noise_Deg (S : Sensor_Model; Angle : Float) return Float is
     (S.Angle_Noise_Axis_Deg
      + (S.Angle_Noise_Edge_Deg - S.Angle_Noise_Axis_Deg)
        * (Angle / S.Half_Azimuth_Deg) ** 2);

   --  La cible codee par le module pour une distance et un angle mesures.
   function Coded
     (S         : Sensor_Model;
      Range_Mm  : Float;
      Angle_Deg : Float;
      Speed     : Float) return Raw_Target
   is
     ((X_Mm          => To_Value (Range_Mm * Sin (Angle_Deg * Deg)),
       Y_Mm          => To_Value (Range_Mm * Cos (Angle_Deg * Deg)),
       Speed_Cm_S    => To_Value (Speed / 10.0),
       Resolution_Mm => S.Resolution_Mm));

   --  Les objets que le module voit : devant lui, dans son champ, a
   --  portee. Count dit combien de cases de C sont remplies.
   procedure Visible
     (E     : Emulator;
      C     : out Candidate_Array;
      Count : out Natural)
   is
   begin
      Count := 0;
      for I in 1 .. E.Scene.Count loop
         declare
            O          : Object renames E.Scene.Objects (I);
            Lateral    : constant Float := -O.Y;
            Forward    : constant Float := O.X;
            Horizontal : constant Float := Sqrt (O.X ** 2 + O.Y ** 2);
            Slant      : constant Float :=
              Sqrt (O.X ** 2 + O.Y ** 2 + O.Z ** 2);
         begin
            if Forward > 0.0 then
               declare
                  --  Borne a [-1, 1] : en flottant, le quotient peut en
                  --  sortir d'un epsilon et Arcsin leverait une exception.
                  Ratio : constant Float :=
                    Float'Max (-1.0, Float'Min (1.0, Lateral / Slant));
                  Angle     : constant Float := Arcsin (Ratio) / Deg;
                  Elevation : constant Float :=
                    Arctan (O.Z, Horizontal) / Deg;
               begin
                  if abs Angle <= E.Sensor.Half_Azimuth_Deg
                    and then abs Elevation <= E.Sensor.Half_Elevation_Deg
                    and then Slant <= Max_Range_Mm (Angle)
                  then
                     Count := Count + 1;
                     C (Count) :=
                       (Slant_Mm    => Slant,
                        Angle_Deg   => Angle,
                        Radial_Mm_S =>
                          (O.X * O.Vx + O.Y * O.Vy + O.Z * O.Vz) / Slant
                          * Steps_Per_Second);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Visible;

   --  Ce que le module envoie pour la scene courante : au plus trois
   --  cibles (une seule en mono-cible), les plus proches d'abord, avec
   --  bruit, pertes et fantome eventuel.
   procedure Observe (E : in out Emulator; R : out Raw_Report) is
      C     : Candidate_Array;
      Count : Natural;
      Limit : constant Target_Count := (if E.Multi then Max_Targets else 1);
      Hit   : Boolean;
      Dr    : Float;
      Da    : Float;
   begin
      R := (others => <>);
      Visible (E, C, Count);

      --  Tri par selection des Limit plus proches : au plus 8 objets, la
      --  simplicite l'emporte.
      for K in 1 .. Natural'Min (Count, Limit) loop
         for J in K + 1 .. Count loop
            if C (J).Slant_Mm < C (K).Slant_Mm then
               declare
                  Tmp : constant Candidate := C (K);
               begin
                  C (K) := C (J);
                  C (J) := Tmp;
               end;
            end if;
         end loop;

         Chance (E, E.Sensor.Miss_Probability, Hit);
         if not Hit then
            Uniform (E, -E.Sensor.Range_Noise_Mm, E.Sensor.Range_Noise_Mm,
                     Dr);
            declare
               A : constant Float :=
                 Angle_Noise_Deg (E.Sensor, C (K).Angle_Deg);
            begin
               Uniform (E, -A, A, Da);
            end;
            R.Count := R.Count + 1;
            R.Targets (R.Count) :=
              Coded (E.Sensor, C (K).Slant_Mm + Dr, C (K).Angle_Deg + Da,
                     C (K).Radial_Mm_S);
         end if;
      end loop;

      --  Un fantome (multitrajet) : n'importe ou dans le champ, immobile.
      Chance (E, E.Sensor.Ghost_Probability, Hit);
      if Hit and then R.Count < Limit then
         Uniform (E, -E.Sensor.Half_Azimuth_Deg, E.Sensor.Half_Azimuth_Deg,
                  Da);
         Uniform (E, 500.0, Float'Max (500.0, Max_Range_Mm (Da)), Dr);
         R.Count := R.Count + 1;
         R.Targets (R.Count) := Coded (E.Sensor, Dr, Da, 0.0);
      end if;
   end Observe;

   --  Inverse un bit d'un octet de la trame, tires au hasard. Byte est un
   --  type borne et non modulaire : on ajoute ou retire la puissance de
   --  deux au lieu d'un "xor".
   procedure Corrupt (E : in out Emulator; F : in out Emitted_Frame) is
      U     : Float;
      Index : Positive;
      Bit   : Byte;
   begin
      Uniform (E, 0.0, Float (Frame_Length), U);
      Index := Positive'Min (Frame_Length, 1 + Natural (Float'Floor (U)));
      Uniform (E, 0.0, 8.0, U);
      Bit := 2 ** Natural'Min (7, Natural (Float'Floor (U)));
      if (F.Bytes (Index) / Bit) mod 2 = 1 then
         F.Bytes (Index) := F.Bytes (Index) - Bit;
      else
         F.Bytes (Index) := F.Bytes (Index) + Bit;
      end if;
      F.Corrupted_Byte := Index;
   end Corrupt;

   ----------
   -- Make --
   ----------

   function Make
     (Scene  : World        := Initial_World;
      Sensor : Sensor_Model := Default_Sensor;
      Faults : Fault_Model  := No_Faults;
      Seed   : Natural      := 42) return Emulator
   is
   begin
      return (Scene        => Scene,
              Sensor       => Sensor,
              Faults       => Faults,
              Rng          => Random_State (Seed),
              Now          => 0,
              Silent_Until => 0,
              Multi        => True);
   end Make;

   ----------------
   -- Next_Frame --
   ----------------

   procedure Next_Frame
     (E    : in out Emulator;
      F    : out Emitted_Frame;
      Sent : out Boolean)
   is
      Hit    : Boolean;
      Jitter : Float;
   begin
      E.Now := E.Now + Period_Ms;
      Step (E.Scene);
      F    := (Stamp => E.Now, others => <>);
      Sent := False;

      if E.Now < E.Silent_Until then
         return;
      end if;

      Chance (E, E.Faults.Restart_Probability, Hit);
      if Hit then
         E.Silent_Until := E.Now + E.Faults.Restart_Ms;
         E.Multi        := False;
         return;
      end if;

      Chance (E, E.Faults.Silence_Probability, Hit);
      if Hit then
         E.Silent_Until := E.Now + E.Faults.Silence_Ms;
         return;
      end if;

      Observe (E, F.Intended);
      F.Bytes := Encode_Frame (F.Intended);

      Uniform (E, -Float (E.Sensor.Jitter_Ms), Float (E.Sensor.Jitter_Ms),
               Jitter);
      F.Stamp := Time_Ms (Float (E.Now) + Jitter);

      Chance (E, E.Faults.Corrupt_Probability, Hit);
      if Hit then
         Corrupt (E, F);
      end if;

      Sent := True;
   end Next_Frame;

   -------------------
   -- Force_Silence --
   -------------------

   procedure Force_Silence (E : in out Emulator; Duration_Ms : Time_Ms) is
   begin
      E.Silent_Until := E.Now + Period_Ms + Duration_Ms;
   end Force_Silence;

   -------------------
   -- Force_Restart --
   -------------------

   procedure Force_Restart (E : in out Emulator) is
   begin
      E.Silent_Until := E.Now + Period_Ms + E.Faults.Restart_Ms;
      E.Multi        := False;
   end Force_Restart;

   --------------------------
   -- Request_Multi_Target --
   --------------------------

   procedure Request_Multi_Target (E : in out Emulator) is
   begin
      E.Multi := True;
   end Request_Multi_Target;

end Radar_Ld2450_Sim;
