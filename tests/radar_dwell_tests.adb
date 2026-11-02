with AUnit.Assertions;  use AUnit.Assertions;
with Radar_Dwell;       use Radar_Dwell;
with Radar_Geometry;    use Radar_Geometry;
with Radar_Sim_Source;  use Radar_Sim_Source;
with Radar_Source;      use Radar_Source;
with Radar_Sweep;       use Radar_Sweep;
with Radar_Turret_Sim;  use Radar_Turret_Sim;
with Radar_World;       use Radar_World;

--  Corps de la suite 6. Chaque test affirme des totaux exacts ou des bornes
--  chiffrees : un plan qui ne fait rien doit echouer ici.

package body Radar_Dwell_Tests is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Balayage adaptatif (plan, moteur, mesures)");
   end Name;

   function Total (Plan : Sector_Times) return Natural is
      Sum : Natural := 0;
   begin
      for S in Sector loop
         Sum := Sum + Plan (S);
      end loop;
      return Sum;
   end Total;

   --  Le temps ajoute par le plan dans la fenetre d'une cible.
   function Bonus_In_Window (Plan : Sector_Times; Cue : Sector) return Natural
   is
      Sum : Natural := 0;
   begin
      for S in Window_First (Cue) .. Window_Last (Cue) loop
         Sum := Sum + Plan (S) - Min_Sector_Us;
      end loop;
      return Sum;
   end Bonus_In_Window;

   function Make_Plan (Cues : Cue_List; Count : Cue_Count) return Sector_Times
   is
      Plan : Sector_Times;
   begin
      Build (Cues, Count, Plan);
      return Plan;
   end Make_Plan;

   --  Sans cible, le balayage reste uniforme et la passe dure exactement
   --  sa duree nominale : l'option n'a aucun effet sans raison d'agir.
   procedure Test_No_Cue_Is_Uniform
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plan : constant Sector_Times := Make_Plan ((others => 1), 0);
   begin
      for S in Sector loop
         Assert (Plan (S) = Nominal_Sector_Us, "Sans cible : plan non uniforme");
      end loop;
      Assert (Total (Plan) = Pass_Us, "Sans cible : duree de passe fausse");
   end Test_No_Cue_Is_Uniform;

   --  Une cible seule recoit tout le temps libre ; le reste tourne au maximum.
   procedure Test_One_Cue_Takes_All
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cue  : constant Sector := 40;
      Plan : constant Sector_Times := Make_Plan ((others => Cue), 1);
   begin
      Assert (Bonus_In_Window (Plan, Cue) = Bonus_Us,
              "Une cible : part incomplete");
      for S in Sector loop
         if S not in Window_First (Cue) .. Window_Last (Cue) then
            Assert (Plan (S) = Min_Sector_Us, "Hors fenetre : pas au maximum");
         else
            Assert (Plan (S) > Nominal_Sector_Us,
                    "Dans la fenetre : la tete ne ralentit pas");
         end if;
      end loop;
   end Test_One_Cue_Takes_All;

   --  Fenetres disjointes : la meme part pour chacune, a la microseconde.
   procedure Test_Fair_Shares
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cues : constant Cue_List := (10, 25, 40, 55, 70, 1, 84, 84);
   begin
      for Count in 2 .. 5 loop
         declare
            Plan : constant Sector_Times := Make_Plan (Cues, Count);
         begin
            Assert (Share (Count) = Bonus_Us / Count, "Part mal calculee");
            for I in 1 .. Count loop
               Assert (Bonus_In_Window (Plan, Cues (I)) = Share (Count),
                       "Parts inegales entre cibles");
            end loop;
            Assert (Total (Plan)
                      = Sector_Count * Min_Sector_Us + Count * Share (Count),
                    "Duree de passe fausse");
         end;
      end loop;
   end Test_Fair_Shares;

   --  Deux cibles proches additionnent leurs parts dans la zone commune,
   --  sans que du temps se perde ni que la vitesse depasse le plafond.
   procedure Test_Overlapping_Cues
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Same : constant Sector_Times := Make_Plan ((40, 40, others => 1), 2);
      Near : constant Sector_Times := Make_Plan ((40, 43, others => 1), 2);
   begin
      Assert (Bonus_In_Window (Same, 40) = 2 * Share (2),
              "Meme secteur : parts non additionnees");
      Assert (Total (Near) = Total (Same),
              "Fenetres recouvertes : du temps se perd");
      Assert (Near (41) > Near (37) and then Near (41) > Near (46),
              "La zone commune doit etre la plus lente");
   end Test_Overlapping_Cues;

   --  Une cible au bord garde sa part sur une fenetre plus courte.
   procedure Test_Edge_Windows
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Cues : constant Cue_List := (1, 84, others => 1);
      Plan : constant Sector_Times := Make_Plan (Cues, 2);
   begin
      Assert (Window_First (1) = 1 and then Window_Last (1) = 6,
              "Fenetre du debut mal coupee");
      Assert (Window_First (84) = 78 and then Window_Last (84) = 84,
              "Fenetre de la fin mal coupee");
      Assert (Bonus_In_Window (Plan, 1) = Share (2)
                and then Bonus_In_Window (Plan, 84) = Share (2),
              "Une cible au bord perd sa part");
   end Test_Edge_Windows;

   --  Le moteur tient la duree de passe grace a la reserve : c'est la mesure
   --  qui fixe Ramp_Reserve_Us, pour les pires espacements essayes.
   procedure Test_Ramps_Fit_Reserve
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Budget : constant Float := Float (Pass_Us) * 1.0E-6;
   begin
      for Count in 1 .. Max_Cues loop
         for Spacing in 1 .. Sector_Count / Count loop
            declare
               Cues : Cue_List := (others => 1);
            begin
               for I in 1 .. Count loop
                  Cues (I) := I * Spacing;
               end loop;
               Assert
                 (Pass_Seconds (Realise (Make_Plan (Cues, Count))) <= Budget,
                  "Les rampes depassent la duree de passe");
            end;
         end loop;
      end loop;
   end Test_Ramps_Fit_Reserve;

   --  Le modele de moteur ne doit pas passer pour un moteur parfait, ni
   --  depasser son plafond.
   procedure Test_Motor_Limits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plan  : constant Sector_Times := Make_Plan ((others => 40), 1);
      Times : constant Realised_Times := Realise (Plan);
      Ideal : constant Float := Float (Total (Plan)) * 1.0E-6;
   begin
      Assert (Pass_Seconds (Times) > Ideal + 0.01,
              "Les rampes doivent couter du temps");
      for S in Sector loop
         Assert (Times (S) >= Float (Plan (S)) * 1.0E-6 * 0.999,
                 "Un secteur va plus vite que le plan");
      end loop;
      --  Entre deux milieux de secteur, l'ecart de v**2 ne depasse pas 2 a d.
      for S in 1 .. Sector_Count - 1 loop
         declare
            Deg : constant Float := Float (Sector_Degrees);
            V1  : constant Float := Deg / Times (S);
            V2  : constant Float := Deg / Times (S + 1);
         begin
            Assert (abs (V2 * V2 - V1 * V1) <= 2.0 * Accel_Deg_S2 * Deg * 1.1,
                    "Le moteur accelere au-dela de sa limite");
         end;
      end loop;
      Assert (abs (Angle_At (Times, 0.0)) < 0.01, "Angle de depart faux");
      Assert (Angle_At (Times, 100.0) = Float (Pass_Degrees),
              "Angle de fin faux");
   end Test_Motor_Limits;

   --  ----- Le gain mesure sur le simulateur -----

   type Scan_Result is record
      Columns_On_Target : Natural := 0;  --  colonnes visant pres de l'objet
      Measures          : Natural := 0;
   end record;

   function Run_Scan
     (Times  : Realised_Times;
      Target : Float;
      Margin : Float) return Scan_Result
   is
      Src    : Simulated_Source := Make_Planned_Scan (Times, 180, 4);
      M      : Measurement;
      OK     : Boolean;
      Result : Scan_Result;
   begin
      while Src.Has_More loop
         Src.Next (M, OK);
         Assert (OK, "Mesure attendue");
         Result.Measures := Result.Measures + 1;
         declare
            Gap : constant Float := abs (M.Azimuth - Target);
         begin
            if Float'Min (Gap, 360.0 - Gap) < Margin then
               Result.Columns_On_Target := Result.Columns_On_Target + 1;
            end if;
         end;
      end loop;
      return Result;
   end Run_Scan;

   --  A nombre de mesures egal, le plan en met davantage sur une cible, et
   --  d'autant moins qu'il y en a d'autres a servir.
   procedure Test_Gain_On_Target
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Target : constant Float := 120.0;
      Cue    : constant Sector := Sector_Of (150);
      Cues   : constant Cue_List := (Cue, 10, 70, 45, others => 1);

      function Gain_With (Count : Cue_Count) return Scan_Result is
        (Run_Scan (Realise (Make_Plan (Cues, Count)), Target, 25.0));

      Base : constant Scan_Result := Gain_With (0);
      One  : constant Scan_Result := Gain_With (1);
      Two  : constant Scan_Result := Gain_With (2);
      Four : constant Scan_Result := Gain_With (4);
   begin
      Assert (Base.Measures = 180 * 4 and then One.Measures = Base.Measures,
              "Le plan doit garder le nombre de mesures");
      Assert (One.Columns_On_Target >= 3 * Base.Columns_On_Target,
              "Une cible : gain inferieur a x3");
      Assert (Two.Columns_On_Target > Base.Columns_On_Target
                and then Two.Columns_On_Target < One.Columns_On_Target,
              "Deux cibles : la part doit baisser");
      Assert (Four.Columns_On_Target > Base.Columns_On_Target
                and then Four.Columns_On_Target < Two.Columns_On_Target,
              "Quatre cibles : la part doit baisser");
   end Test_Gain_On_Target;

   --  Les reperes viennent bien des objets de la scene.
   procedure Test_Scene_Cues
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Scene : constant World := Initial_World;
      Cues  : Cue_List;
      Count : Cue_Count;
   begin
      Scene_Cues (Cues, Count);
      Assert (Count = Natural'Min (Scene.Count, Max_Cues) and then Count > 0,
              "Nombre de reperes faux");
      for I in 1 .. Count loop
         declare
            O  : constant Object := Scene.Objects (I);
            Az : Float := To_Polar ((O.X, O.Y, O.Z)).Azimuth;
         begin
            if Az < 0.0 then
               Az := Az + 360.0;
            end if;
            Assert (abs (Float ((Cues (I) - 1) * Sector_Degrees)
                         - (Az + 30.0)) <= Float (Sector_Degrees),
                    "Repere loin de son objet");
         end;
      end loop;
   end Test_Scene_Cues;

   --  L'objet detecte par la chaine reelle (CFAR) l'est plus souvent avec le
   --  plan : c'est le gain en points, et non seulement en colonnes. Le niveau
   --  des echos est retire a chaque passe : le test cumule plusieurs passes, et
   --  ne compte que les detections a la position d'un objet.
   procedure Test_More_Echoes_On_Scene
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Scene : constant World := Initial_World;

      function Is_On_Object (Az : Float; Distance : Float) return Boolean is
      begin
         for I in 1 .. Scene.Count loop
            declare
               O   : constant Object := Scene.Objects (I);
               R   : constant Polar := To_Polar ((O.X, O.Y, O.Z));
               Gap : constant Float := abs (Az - R.Azimuth);
            begin
               if Float'Min (Gap, 360.0 - Gap) < 15.0
                 and then abs (Distance - R.Distance) < 400.0
               then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end Is_On_Object;

      function Detections (Times : Realised_Times) return Natural is
         Src   : Simulated_Source := Make_Planned_Scan (Times, 180, 24);
         M     : Measurement;
         OK    : Boolean;
         Found : Natural := 0;
      begin
         while Src.Has_More loop
            Src.Next (M, OK);
            declare
               D : constant Detection := Detect_Adaptive (M.Data);
            begin
               for K in 1 .. D.Count loop
                  if Is_On_Object
                       (M.Azimuth, Float (Bin_Distance (D.Targets (K))))
                  then
                     Found := Found + 1;
                  end if;
               end loop;
            end;
         end loop;
         return Found;
      end Detections;

      Passes  : constant := 6;
      Cues    : Cue_List;
      Count   : Cue_Count;
      Uniform : Natural := 0;
      Planned : Natural := 0;
   begin
      Scene_Cues (Cues, Count);
      for Pass in 1 .. Passes loop
         Uniform := Uniform + Detections (Realise (Make_Plan (Cues, 0)));
         Planned := Planned + Detections (Realise (Make_Plan (Cues, Count)));
      end loop;
      Assert (Uniform > 0, "Aucun objet detecte : le test ne mesure rien");
      Assert (2 * Planned > 3 * Uniform,
              "Le plan n'apporte pas 1,5 fois plus d'echos sur les objets");
   end Test_More_Echoes_On_Scene;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_No_Cue_Is_Uniform'Access, "Sans cible : plan uniforme");
      Register_Routine
        (T, Test_One_Cue_Takes_All'Access, "Une cible : tout le temps libre");
      Register_Routine
        (T, Test_Fair_Shares'Access, "Parts egales entre cibles");
      Register_Routine
        (T, Test_Overlapping_Cues'Access, "Fenetres qui se recouvrent");
      Register_Routine
        (T, Test_Edge_Windows'Access, "Cibles aux bords de la passe");
      Register_Routine
        (T, Test_Ramps_Fit_Reserve'Access, "Les rampes tiennent la reserve");
      Register_Routine
        (T, Test_Motor_Limits'Access, "Limites du modele de moteur");
      Register_Routine
        (T, Test_Gain_On_Target'Access, "Gain en mesures sur une cible");
      Register_Routine
        (T, Test_Scene_Cues'Access, "Reperes tires de la scene");
      Register_Routine
        (T, Test_More_Echoes_On_Scene'Access, "Plus d'echos sur la scene");
   end Register_Tests;

end Radar_Dwell_Tests;
