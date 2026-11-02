with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;
with AUnit.Assertions;  use AUnit.Assertions;
with Radar_Geometry;    use Radar_Geometry;
with Radar_Detect;      use Radar_Detect;
with Radar_Html;        use Radar_Html;
with Radar_Track;       use Radar_Track;
with Radar_Sim_Source;  use Radar_Sim_Source;
with Radar_Source;      use Radar_Source;
with Radar_World;       use Radar_World;
with Radar_Sweep;       use Radar_Sweep;
with Radar_Clutter;     use Radar_Clutter;

--  Corps de la suite 2. Les scenarios sont deroules tour par tour, comme
--  le ferait un mode d'exploitation, afin que ce qui est teste soit bien
--  la chaine reelle et non une version simplifiee pour les besoins du
--  test.

package body Radar_Pipeline_Tests is

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format
        ("Pipeline 3D : geometrie, regroupement, pistage");
   end Name;

   --  Cadence des tours dans les tests : une seconde. Le pistage
   --  raisonne desormais en TEMPS et non en tours, donc chaque frame
   --  doit porter son heure ; sans cela le dt vaudrait zero et la
   --  vitesse n aurait aucun sens.
   Turn_Ms : constant Time_Ms := 1_000;

   --  Avance l horloge d un tour, puis passe la frame au pistage.
   procedure Tick
     (Trk : in out Tracker; F : in out Frame; Now : in out Time_Ms) is
   begin
      Now     := Now + Turn_Ms;
      F.Stamp := Now;
      Update (Trk, F);
   end Tick;

   --  Test 1 : aller-retour geometrie. (distance, angles) -> point 3D ->
   --  (distance, angles) doit redonner la mesure de depart (a un epsilon
   --  pres : calcul flottant).
   procedure Test_Geometry_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : constant Point_3D := To_Point (2000.0, 120.0, 15.0);
      R : constant Polar    := To_Polar (P);
   begin
      Assert (abs (R.Distance - 2000.0) < 0.5,
              "La distance devrait etre retrouvee (2000 mm)");
      Assert (abs (R.Azimuth - 120.0) < 0.01,
              "L'azimut devrait etre retrouve (120 deg)");
      Assert (abs (R.Elevation - 15.0) < 0.01,
              "L'elevation devrait etre retrouvee (15 deg)");
   end Test_Geometry_Roundtrip;

   --  Test 2 : normalisation d'azimut. -90 degres et +270 degres sont la
   --  meme direction ; To_Polar doit rendre la forme normalisee 0..360.
   procedure Test_Azimuth_Normalization
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      P : constant Point_3D := To_Point (1000.0, -90.0, 0.0);
      R : constant Polar    := To_Polar (P);
   begin
      Assert (abs (R.Azimuth - 270.0) < 0.01,
              "Un azimut de -90 devrait etre normalise en 270");
   end Test_Azimuth_Normalization;

   --  Test 3 : point au zenith (X = Y = 0). Le quotient Z/Dist vaut
   --  exactement 1 : sans le bornage dans To_Polar, un epsilon d'arrondi
   --  au-dessus de 1.0 ferait lever Argument_Error par Arcsin.
   procedure Test_Zenith
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      R : constant Polar := To_Polar ((0.0, 0.0, 1234.5));
   begin
      Assert (abs (R.Distance - 1234.5) < 0.001,
              "La distance au zenith devrait etre |Z|");
      Assert (abs (R.Elevation - 90.0) < 0.01,
              "L'elevation au zenith devrait etre 90 deg");
   end Test_Zenith;

   --  Test 4 : regroupement. Deux echos d'une meme cible etendue
   --  (500 mm d'ecart : reflecteurs + quantification en elevation)
   --  fusionnent ; un objet a 2 m reste une cible distincte.
   procedure Test_Cluster
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      F : Frame;
   begin
      Reset (F);
      F.Count := 3;
      F.Items (1) := (Pos => (0.0, 0.0, 0.0),    Distance => 0.0);
      F.Items (2) := (Pos => (500.0, 0.0, 0.0),  Distance => 500.0);
      F.Items (3) := (Pos => (2000.0, 0.0, 0.0), Distance => 2000.0);

      declare
         C : constant Frame := Cluster (F);
      begin
         Assert (C.Count = 2,
                 "3 detections dont 2 proches devraient donner 2 cibles");
         Assert (abs (C.Items (1).Pos.X - 250.0) < 0.001,
                 "La cible fusionnee devrait etre a la position moyenne");
         Assert (abs (C.Items (2).Pos.X - 2000.0) < 0.001,
                 "La detection isolee devrait rester en place");
      end;
   end Test_Cluster;

   --  La premiere piste active du tracker (pour les tests).
   function First_Active (Trk : Tracker) return Track is
   begin
      for Tk of Trk.Tracks loop
         if Tk.Active then
            return Tk;
         end if;
      end loop;
      return (Id => 0, Pos => (0.0, 0.0, 0.0), Velocity => (0.0, 0.0, 0.0),
              Missing => 0, Last_Seen => 0, Hits => 0,
              Confirmed => False, Active => False,
              Vel_Stamp => 0, Vel_Anchor => (0.0, 0.0, 0.0));
   end First_Active;

   --  Test 5 : cycle de vie et filtre de piste. Une cible qui avance de
   --  100 mm/tour : la piste nait tentative (non confirmee), se
   --  confirme apres 3 detections, sa vitesse filtree (alpha-beta)
   --  converge vers 100 mm/s, et elle roule sur son erre pendant
   --  une occultation (coasting).
   procedure Test_Track_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      Now   : Time_Ms := 0;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);
      F.Count := 1;

      --  Tour 1 : premiere detection -> tentative, pas confirmee.
      F.Items (1) := (Pos => (0.0, 0.0, 0.0), Distance => 0.0);
      Tick (Trk, F, Now);
      Assert (not First_Active (Trk).Confirmed,
              "Une seule detection ne devrait pas confirmer la piste");

      --  Tours 2 a 10 : la cible avance de 100 mm par tour.
      for N in 1 .. 9 loop
         F.Items (1) := (Pos => (Float (N) * 100.0, 0.0, 0.0),
                         Distance => Float (N) * 100.0);
         Tick (Trk, F, Now);
      end loop;

      Assert (First_Active (Trk).Confirmed,
              "La piste devrait etre confirmee (M-sur-N)");
      Assert (First_Active (Trk).Id = 1,
              "L'ID d'origine devrait etre conserve");
      Assert (abs (First_Active (Trk).Velocity.X - 100.0) < 20.0,
              "La vitesse filtree devrait converger vers 100 mm/s");

      --  Occultation de 2 tours : la piste confirmee survit et sa
      --  position continue d'avancer sur son erre.
      declare
         Before : constant Float := First_Active (Trk).Pos.X;
      begin
         Tick (Trk, Empty, Now);
         Tick (Trk, Empty, Now);
         Assert (First_Active (Trk).Active
                 and then First_Active (Trk).Confirmed,
                 "La piste confirmee devrait survivre a l'occultation");
         Assert (First_Active (Trk).Pos.X > Before + 100.0,
                 "Coasting : la position devrait continuer d'avancer");
      end;
   end Test_Track_Filter;

   --  Test : le cycle de vie se compte en TEMPS, pas en mises a jour.
   --
   --  Scenario multi-source, celui qui a motive le changement : une
   --  couronne rapide et une tourelle lente alimentent le MEME pistage,
   --  donc Update est appele bien plus souvent qu avant. Une piste vue
   --  par une seule des deux sources encaissait, en comptant les tours,
   --  un "manque" a chaque passage de l autre source et mourait au bout
   --  de trois appels. En comptant le temps, elle survit tant que le
   --  delai de coasting n est pas ecoule.
   procedure Test_Coast_Is_Time_Based
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      Now   : Time_Ms := 0;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);
      F.Count := 1;

      --  Trois detections espacees de 300 ms : la piste se confirme.
      for N in 1 .. 3 loop
         Now := Now + 300;
         F.Stamp := Now;
         F.Items (1) := (Pos      => (Float (N) * 30.0, 0.0, 0.0),
                         Distance => Float (N) * 30.0);
         Update (Trk, F);
      end loop;
      Assert (First_Active (Trk).Confirmed,
              "La piste devrait etre confirmee apres 3 detections");

      --  Cinq mises a jour vides espacees de 200 ms : 1000 ms au total,
      --  bien en deca du delai de coasting. En comptant les tours, cinq
      --  manques auraient tue la piste des le quatrieme.
      for N in 1 .. 5 loop
         Now := Now + 200;
         Empty.Stamp := Now;
         Update (Trk, Empty);
      end loop;
      Assert (First_Active (Trk).Active,
              "5 mises a jour rapprochees ne font que 1 s : la piste vit");

      --  On laisse maintenant passer largement le delai.
      Now := Now + 3_000;
      Empty.Stamp := Now;
      Update (Trk, Empty);
      Assert (not First_Active (Trk).Active,
              "Passe le delai de coasting, la piste doit mourir");
   end Test_Coast_Is_Time_Based;

   --  Test 5bis : zone aveugle. Une cible qui passe au pied du radar
   --  devient invisible (Frame.Min_Range) ; ne rien voir y est normal,
   --  la piste doit donc survivre et garder son identifiant.
   --
   --  Scenario calcule a la main (Alpha 0,5, Beta 0,3, dt 1 s) : la
   --  cible avance de 200 mm/s vers le radar, detectee a 1300, 1100,
   --  900 puis 700 mm. Position filtree finale 794 mm, vitesse
   --  -188 mm/s : la prediction est sous 625 + 200 mm, donc "aveugle".
   --  Apres 6 s sans echo, la cible ressort de l autre cote a -700 mm ;
   --  la prediction dit -525 mm : 175 mm d ecart, dans la fenetre.
   --
   --  La contre-epreuve (Min_Range = 0) rejoue le meme scenario et doit
   --  tuer la piste : c est elle qui prouve que le champ fait la
   --  difference, et non un delai de survie trop genereux.
   procedure Test_Blind_Zone_Coast
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Joue les deux premieres phases avec une portee minimale donnee
      --  et rend le pistage obtenu.
      function Run (Min_Range : Float) return Tracker is
         Trk   : Tracker;
         Now   : Time_Ms := 0;
         F     : Frame;
         Empty : Frame;
      begin
         Reset (F);
         Reset (Empty);
         F.Min_Range     := Min_Range;
         Empty.Min_Range := Min_Range;
         F.Count := 1;

         for N in 0 .. 3 loop
            F.Items (1) := (Pos      => (1300.0 - Float (N) * 200.0,
                                         0.0, 0.0),
                            Distance => 1300.0 - Float (N) * 200.0);
            Tick (Trk, F, Now);
         end loop;

         for N in 1 .. 6 loop
            Tick (Trk, Empty, Now);
         end loop;
         return Trk;
      end Run;

      Blind   : Tracker := Run (Profile_Min_Range);
      Sighted : constant Tracker := Run (0.0);
      Id      : constant Natural := First_Active (Blind).Id;
      Back    : Frame;
      Now     : Time_Ms := 10 * Turn_Ms;
      Active  : Natural := 0;
   begin
      Assert (First_Active (Blind).Confirmed,
              "Apres 6 s dans la zone aveugle, la piste doit survivre");
      Assert (not First_Active (Sighted).Active,
              "Sans zone aveugle, 6 s sans echo doivent tuer la piste");

      --  La cible ressort de la zone : meme identifiant, pas de piste
      --  neuve.
      Reset (Back);
      Back.Min_Range := Profile_Min_Range;
      Back.Count     := 1;
      Back.Items (1) := (Pos => (-700.0, 0.0, 0.0), Distance => 700.0);
      Tick (Blind, Back, Now);

      for Tk of Blind.Tracks loop
         if Tk.Active then
            Active := Active + 1;
         end if;
      end loop;
      Assert (First_Active (Blind).Id = Id and then Active = 1,
              "La cible ressortie doit garder son identifiant, obtenu"
              & First_Active (Blind).Id'Image & " pour" & Id'Image);
   end Test_Blind_Zone_Coast;

   --  Test 5ter : association globale. Deux pistes etablies en x=0 et
   --  x=500 ; nouvelles detections en 480 et 950. En glouton (ordre des
   --  pistes), la piste 1 volerait la detection 480 (distance 480 < 600)
   --  alors qu'elle appartient clairement a la piste 2 (distance 20).
   --  En association globale, la piste 2 prend 480, la piste 1 ne prend
   --  rien (950 est hors rayon pour elle).
   procedure Test_Global_Association
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
      Now : Time_Ms := 0;
      F   : Frame;
   begin
      Reset (F);
      F.Count := 2;

      --  3 tours : deux pistes immobiles en 0 et 500, confirmees.
      for N in 1 .. 3 loop
         F.Items (1) := (Pos => (0.0, 0.0, 0.0),   Distance => 0.0);
         F.Items (2) := (Pos => (500.0, 0.0, 0.0), Distance => 500.0);
         Tick (Trk, F, Now);
      end loop;

      --  Le tour litigieux.
      F.Items (1) := (Pos => (480.0, 0.0, 0.0), Distance => 480.0);
      F.Items (2) := (Pos => (950.0, 0.0, 0.0), Distance => 950.0);
      Tick (Trk, F, Now);

      for Tk of Trk.Tracks loop
         if Tk.Active and then Tk.Confirmed then
            if Tk.Id = 1 then
               Assert (Tk.Pos.X < 100.0,
                       "La piste 1 ne devrait PAS avoir vole 480");
               Assert (Tk.Missing = 1,
                       "La piste 1 devrait etre en coasting");
            elsif Tk.Id = 2 then
               Assert (Tk.Pos.X > 400.0 and then Tk.Pos.X < 500.0,
                       "La piste 2 devrait avoir pris la detection 480");
            end if;
         end if;
      end loop;
   end Test_Global_Association;

   --  ----- Politique de temps du pistage (P3) -----

   --  Nombre de pistes confirmees actives.
   function Confirmed_Count (Trk : Tracker) return Natural is
      N : Natural := 0;
   begin
      for Tk of Trk.Tracks loop
         if Tk.Active and then Tk.Confirmed then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Confirmed_Count;

   --  La premiere piste confirmee (appelee apres Confirmed_Count >= 1).
   function First_Confirmed (Trk : Tracker) return Track is
   begin
      for Tk of Trk.Tracks loop
         if Tk.Active and then Tk.Confirmed then
            return Tk;
         end if;
      end loop;
      raise Program_Error with "aucune piste confirmee";
   end First_Confirmed;

   --  Une frame d'une seule detection en (X, 2000, 0), datee S.
   function One_At (S : Time_Ms; X : Float) return Frame is
      F : Frame;
   begin
      Reset (F);
      F.Count := 1;
      F.Items (1) := (Pos => (X, 2000.0, 0.0), Distance => 0.0);
      F.Stamp := S;
      return F;
   end One_At;

   --  Piste etablie : cible a 1 m/s vue a 10 Hz pendant 2 s ; x = 0 a 2 s.
   procedure Establish (Trk : in out Tracker) is
   begin
      for K in 1 .. 20 loop
         Update (Trk, One_At (Time_Ms (K * 100),
                              -2000.0 + 100.0 * Float (K)));
      end loop;
   end Establish;

   --  Bruit uniforme +/- 50 mm, deterministe et independant de GNAT
   --  (congruentiel, a = 1103515245, c = 12345, modulo 2**31).
   type Lcg is record
      S : Long_Long_Integer := 1;
   end record;

   function Next_Noise (G : in out Lcg) return Float is
   begin
      G.S := (G.S * 1103515245 + 12345) mod 2 ** 31;
      return (Float (G.S) / Float (2 ** 31) - 0.5) * 100.0;
   end Next_Noise;

   --  Test : une frame au meme instant n'infere aucune vitesse et ne fait
   --  pas reculer l'horloge. Mesure sur l'ancien code : 29 m/s.
   procedure Test_Same_Stamp_Keeps_Velocity
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
   begin
      Establish (Trk);
      Assert (Confirmed_Count (Trk) = 1, "Une piste confirmee attendue");
      declare
         Before : constant Track := First_Confirmed (Trk);
      begin
         Update (Trk, One_At (2000, 100.0));   --  meme instant, 100 mm
         Assert (Confirmed_Count (Trk) = 1
                 and then First_Confirmed (Trk).Id = Before.Id,
                 "La meme piste devrait rester seule confirmee");
         Assert (First_Confirmed (Trk).Last_Seen = 2000,
                 "La frame simultanee devrait etre associee");
         Assert (First_Confirmed (Trk).Velocity = Before.Velocity,
                 "Aucune vitesse ne s'infere d'une observation simultanee");
         Assert (Trk.Last_Stamp = 2000, "L'horloge ne doit pas bouger");
      end;
   end Test_Same_Stamp_Keeps_Velocity;

   --  Test : une frame tardive est rejetee entiere et comptee, Owners ne
   --  la revendique pas, et le pistage reprend ensuite normalement.
   procedure Test_Late_Frame_Rejected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
      Late : constant Frame := One_At (1950, -50.0);
   begin
      Establish (Trk);
      Assert (Confirmed_Count (Trk) = 1, "Une piste confirmee attendue");
      declare
         Saved : constant Track_Array := Trk.Tracks;
         Id0   : constant Natural := First_Confirmed (Trk).Id;
      begin
         Assert (Owners (Trk, Late) = No_Owner,
                 "Owners ne doit pas revendiquer une frame tardive");
         Update (Trk, Late);
         Assert (Trk.Late_Frames = 1, "La frame tardive devrait etre comptee");
         Assert (Trk.Last_Stamp = 2000, "L'horloge ne doit pas reculer");
         Assert (Trk.Tracks = Saved, "Les pistes devraient etre intactes");
         Update (Trk, One_At (2100, 100.0));
         Assert (Confirmed_Count (Trk) = 1
                 and then First_Confirmed (Trk).Id = Id0
                 and then First_Confirmed (Trk).Last_Seen = 2100,
                 "La frame suivante devrait s'associer a la meme piste");
      end;
   end Test_Late_Frame_Rejected;

   --  Test : apres 0,7 s sans detection, une cible reapparue a 0,5 m/s
   --  garde le signe de sa vitesse. Mesure sur l'ancien code : -51 mm/s
   --  (l'ecart accumule sur 0,7 s etait divise par 0,1 s). Ne dit rien de
   --  la porte d'association d'une cible ARRETEE, sujet distinct.
   procedure Test_Velocity_After_Gap
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk  : Tracker;
      Id0  : Natural;
      F    : Frame;
   begin
      Establish (Trk);
      Assert (Confirmed_Count (Trk) = 1, "Une piste confirmee attendue");
      Id0 := First_Confirmed (Trk).Id;
      for K in 21 .. 26 loop
         Reset (F);
         F.Stamp := Time_Ms (K * 100);
         Update (Trk, F);
      end loop;
      Update (Trk, One_At (2700, 350.0));
      Assert (Confirmed_Count (Trk) = 1
              and then First_Confirmed (Trk).Id = Id0
              and then First_Confirmed (Trk).Last_Seen = 2700,
              "La piste devrait etre reassociee");
      Assert (First_Confirmed (Trk).Velocity.X >= 400.0
              and then First_Confirmed (Trk).Velocity.X <= 1000.0,
              "Vitesse apres l'absence hors de [400, 1000] :"
              & Integer'Image (Integer (First_Confirmed (Trk).Velocity.X)));
   end Test_Velocity_After_Gap;

   --  Garde : a cadence reguliere (10 Hz), le pistage reste exactement le
   --  filtre alpha-beta de reference, recalcule ici (alpha 0,5, beta 0,3 :
   --  a mettre a jour si ces gains changent).
   procedure Test_Regular_Cadence_Unchanged
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
      G   : Lcg := (S => 4242);
      Xr, Vr : Float := 0.0;
      Dt  : constant Float := Float (Time_Ms'(100)) / 1000.0;
   begin
      for K in 1 .. 40 loop
         declare
            Z : constant Float :=
              -2000.0 + 100.0 * Float (K) + Next_Noise (G);
         begin
            Update (Trk, One_At (Time_Ms (K * 100), Z));
            if K = 1 then
               Xr := Z;
               Vr := 0.0;
            else
               declare
                  Xp : constant Float := Xr + Vr * Dt;
                  R  : constant Float := Z - Xp;
               begin
                  Xr := Xp + 0.5 * R;
                  Vr := Vr + (0.3 / Dt) * R;
               end;
            end if;
            Assert (abs (First_Active (Trk).Pos.X - Xr) < 1.0E-3
                    and then abs (First_Active (Trk).Velocity.X - Vr) < 1.0E-3,
                    "Ecart au filtre de reference a la frame" & K'Img);
         end;
      end loop;
   end Test_Regular_Cadence_Unchanged;

   --  Garde-fou DETERMINISTE, ni caracterisation statistique ni critere
   --  d'acceptation materiel : sources entrelacees (2 a 10 ms, 3 a 33 ms)
   --  sur 3 graines fixes. Le bruit de vitesse doit rester sous 2 fois
   --  l'ecart-type THEORIQUE d'une source seule a 10 Hz :
   --  sigma_v**2 = sigma**2 2 beta**2 / (T**2 alpha (4 - 2 alpha - beta))
   --  = 105,4 mm/s pour un bruit uniforme de +/- 50 mm. Trois graines ne
   --  permettent pas d'estimer le bruit reel : le test detecte seulement
   --  le retour de l'ancien defaut (1 121 a 1 464 mm/s a 2 sources, 270 a
   --  336 mm/s a 3 sources). Le bruit du LD2450 reel reste a mesurer.
   procedure Test_Interleaved_Velocity_Guard
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Limit : constant Float := 2.0 * 105.4;
      type Offs is array (Positive range <>) of Time_Ms;

      procedure Scenario (O : Offs; Seed : Long_Long_Integer;
                          Label : String) is
         Trk : Tracker;
         G   : Lcg := (S => Seed);
         Sum : Float := 0.0;
         N   : Natural := 0;
         Id0 : Natural := 0;
      begin
         for K in 1 .. 60 loop
            for J in O'Range loop
               declare
                  S : constant Time_Ms := Time_Ms (K * 100) + O (J);
               begin
                  Update (Trk, One_At (S, -3000.0 + Float (S)
                                          + Next_Noise (G)));
                  if S >= 2000 then
                     Assert (Confirmed_Count (Trk) = 1,
                             Label & " : une seule piste confirmee attendue");
                     if Id0 = 0 then
                        Id0 := First_Confirmed (Trk).Id;
                     end if;
                     Assert (First_Confirmed (Trk).Id = Id0,
                             Label & " : identifiant change");
                     Sum := Sum
                       + (First_Confirmed (Trk).Velocity.X - 1000.0) ** 2;
                     N := N + 1;
                  end if;
               end;
            end loop;
         end loop;
         Assert (N >= 30, Label & " : trop peu d'echantillons");
         Assert (Sqrt (Sum / Float (N)) <= Limit,
                 Label & " : bruit de vitesse"
                 & Integer'Image (Integer (Sqrt (Sum / Float (N))))
                 & " mm/s");
      end Scenario;
   begin
      for Seed in 1 .. 3 loop
         Scenario ((0, 10), Long_Long_Integer (Seed) * 7919,
                   "2 sources a 10 ms, graine" & Seed'Img);
         Scenario ((0, 33, 66), Long_Long_Integer (Seed) * 7919,
                   "3 sources a 33 ms, graine" & Seed'Img);
      end loop;
   end Test_Interleaved_Velocity_Guard;

   --  Test 5quater : fusion anti-fragmentation. Deux echos persistants
   --  a 350 mm l'un de l'autre (cible etendue scindee) ne doivent
   --  produire qu'une piste - pas de piste "ombre".
   procedure Test_Track_Merge
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
      Now : Time_Ms := 0;
      F   : Frame;
   begin
      Reset (F);
      F.Count := 2;
      for N in 1 .. 5 loop
         F.Items (1) := (Pos => (0.0, 0.0, 0.0),   Distance => 0.0);
         F.Items (2) := (Pos => (350.0, 0.0, 0.0), Distance => 350.0);
         Tick (Trk, F, Now);
      end loop;

      declare
         Actives : Natural := 0;
      begin
         for Tk of Trk.Tracks loop
            if Tk.Active then
               Actives := Actives + 1;
            end if;
         end loop;
         Assert (Actives = 1,
                 "Deux echos a 350 mm devraient fusionner en UNE piste");
      end;
   end Test_Track_Merge;

   --  Test : deux cibles qui se croisent gardent chacune leur identifiant
   --  (CAP dette 16, la moitie des changements d'ID du mode live). A part
   --  de x = -3000, B de x = +3000 a 100 mm de lui, chacun a 500 mm/s en
   --  sens oppose ; chaque cible etendue renvoie deux echos a +/-80 mm. Au
   --  croisement (6e seconde), les quatre echos tiennent dans le rayon de
   --  regroupement : sans regroupement guide par les pistes, ils ne
   --  faisaient qu'UNE detection, et la fusion de pistes (400 mm) tuait
   --  ensuite l'une des deux. Le test verifie aussi que les pistes ne se
   --  sont pas ECHANGE les objets : celle de A doit finir a droite.
   procedure Test_Crossing_Keeps_Ids
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk  : Tracker;
      Now  : Time_Ms := 0;
      F    : Frame;
      Id_A : Natural := 0;
      Id_B : Natural := 0;

      --  Un tour : les deux cibles a l'instant K (secondes), regroupement
      --  guide par les pistes, puis pistage.
      procedure Step (K : Natural) is
         Xa : constant Float := -3000.0 + 500.0 * Float (K);
         Xb : constant Float :=  3000.0 - 500.0 * Float (K);
      begin
         Reset (F);
         F.Count := 4;
         F.Items (1) := (Pos => (Xa, -80.0, 0.0), Distance => abs Xa);
         F.Items (2) := (Pos => (Xa, 80.0, 0.0), Distance => abs Xa);
         F.Items (3) := (Pos => (Xb, 20.0, 0.0), Distance => abs Xb);
         F.Items (4) := (Pos => (Xb, 180.0, 0.0), Distance => abs Xb);
         Now     := Now + Turn_Ms;
         F.Stamp := Now;
         Update (Trk, Cluster (F, Owners (Trk, F)));
      end Step;
   begin
      --  Avant le croisement : les deux pistes se confirment.
      for K in 0 .. 3 loop
         Step (K);
      end loop;
      for Tk of Trk.Tracks loop
         if Tk.Active and then Tk.Confirmed then
            if Tk.Pos.X < 0.0 then
               Id_A := Tk.Id;
            else
               Id_B := Tk.Id;
            end if;
         end if;
      end loop;
      Assert (Id_A /= 0 and then Id_B /= 0,
              "Les deux pistes devraient etre confirmees avant le croisement");

      --  Le croisement (K = 6) et la suite.
      for K in 4 .. 11 loop
         Step (K);
      end loop;

      declare
         Confirmed : Natural := 0;
      begin
         for Tk of Trk.Tracks loop
            if Tk.Active and then Tk.Confirmed then
               Confirmed := Confirmed + 1;
               Assert (Tk.Id = Id_A or else Tk.Id = Id_B,
                       "Nouvel identifiant apres le croisement :"
                       & Tk.Id'Image);
               if Tk.Id = Id_A then
                  Assert (Tk.Pos.X > 1000.0,
                          "La piste de A devrait finir a droite (echange ?)");
               else
                  Assert (Tk.Pos.X < -1000.0,
                          "La piste de B devrait finir a gauche (echange ?)");
               end if;
            end if;
         end loop;
         Assert (Confirmed = 2,
                 "Deux pistes confirmees attendues apres le croisement, obtenu"
                 & Confirmed'Image);
      end;
   end Test_Crossing_Keeps_Ids;

   --  Test : recollage des pistes. Une cible a 500 mm/s disparait 4 s,
   --  plus longtemps que la roue libre d'une piste confirmee (2,5 s) : sa
   --  piste meurt. Quand l'objet reapparait la ou il devait etre, la
   --  nouvelle piste doit reprendre l'ANCIEN identifiant a sa
   --  confirmation. Contre-epreuve : un objet qui apparait a 3 m de cette
   --  trajectoire n'herite de rien.
   procedure Test_Stitching_Keeps_Id
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Rejoue le scenario ; Offset_Y decale l'objet qui reapparait.
      --  Rend l'identifiant initial et celui de la piste finale.
      procedure Scenario (Offset_Y : Float; Before, After : out Natural) is
         Trk : Tracker;
         Now : Time_Ms := 0;
         F   : Frame;
      begin
         Before := 0;
         After  := 0;
         for K in 0 .. 10 loop
            Reset (F);
            if K <= 3 then
               F.Count := 1;
               F.Items (1) := (Pos => (-2000.0 + 500.0 * Float (K), 0.0, 0.0),
                               Distance => 0.0);
            elsif K >= 8 then
               F.Count := 1;
               F.Items (1) := (Pos => (-2000.0 + 500.0 * Float (K),
                                       Offset_Y, 0.0),
                               Distance => 0.0);
            end if;
            Tick (Trk, F, Now);
            if K = 3 then
               Before := First_Active (Trk).Id;
            end if;
         end loop;
         for Tk of Trk.Tracks loop
            if Tk.Active and then Tk.Confirmed then
               After := Tk.Id;
            end if;
         end loop;
      end Scenario;

      Before, After : Natural;
   begin
      Scenario (0.0, Before, After);
      Assert (Before /= 0 and then After /= 0,
              "Pistes confirmees attendues avant et apres la disparition");
      Assert (After = Before,
              "L'objet revenu sur sa trajectoire devrait garder l'ID"
              & Before'Image & ", obtenu" & After'Image);

      Scenario (3000.0, Before, After);
      Assert (After /= 0 and then After /= Before,
              "Un objet apparu a 3 m de la trajectoire ne doit pas heriter"
              & " de l'ID" & Before'Image);
   end Test_Stitching_Keeps_Id;

   --  Test 5bis : une tentative non re-detectee meurt vite. C'est le
   --  filtre anti-fantomes : un echo de multitrajet, intermittent,
   --  ne survit pas assez longtemps pour etre confirme.
   procedure Test_Tentative_Dies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      Now   : Time_Ms := 0;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);
      F.Count := 1;
      F.Items (1) := (Pos => (1000.0, 0.0, 0.0), Distance => 1000.0);

      Tick (Trk, F, Now);       --  un echo isole -> tentative
      Tick (Trk, Empty, Now);   --  plus rien...
      Tick (Trk, Empty, Now);

      Assert (not First_Active (Trk).Active,
              "Une tentative jamais revue devrait mourir sans trace");
   end Test_Tentative_Dies;

   --  Test 6 : deux echos sur le meme rayon (deux objets alignes) =
   --  deux detections (regression : avant, seul le pic etait garde et
   --  le second objet etait invisible).
   procedure Test_Two_Echoes_Same_Ray
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Measurement := (Azimuth => 0.0, Elevation => 0.0,
                          Stamp   => 0,
                          Data    => (others => 5));
      F : Frame;
   begin
      M.Data (50)  := 3_000;
      M.Data (150) := 2_000;

      Reset (F);
      Add (F, M);

      Assert (F.Count = 2,
              "Deux objets alignes devraient donner deux detections");
      Assert (F.Items (1).Distance < F.Items (2).Distance,
              "Les detections devraient etre ordonnees par case");
   end Test_Two_Echoes_Same_Ray;

   --  Test 7 : distance aux murs de la piece (mode cartographie).
   --  Piece 4000 x 3000 mm centree sur le radar : mur de face a 2000,
   --  mur lateral a 1500 ; viser a 60 degres d'elevation double le
   --  trajet (1 / cos 60 = 2).
   procedure Test_Wall_Distance
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (abs (Wall_Distance (0.0, 0.0) - 2000.0) < 0.01,
              "Le mur de face devrait etre a 2000 mm");
      Assert (abs (Wall_Distance (90.0, 0.0) - 1500.0) < 0.01,
              "Le mur lateral devrait etre a 1500 mm");
      Assert (abs (Wall_Distance (0.0, 60.0) - 4000.0) < 0.1,
              "A 60 deg d'elevation le trajet devrait doubler");
   end Test_Wall_Distance;

   --  Test : angle d'incidence sur les murs (realisme point 9). Le piege
   --  est le choix du mur : a 60 degres d'azimut, le rayon touche le mur
   --  LATERAL (y = 1500) avant le mur de face ; son incidence vaut donc
   --  30 degres, pas 60. Une erreur de mur placerait un echo diffus la
   --  ou il devrait etre speculaire, et inversement.
   procedure Test_Wall_Incidence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Wall_Incidence (0.0, 0.0) < 0.01,
              "Mur de face vise de face : incidence nulle");
      Assert (Wall_Incidence (90.0, 0.0) < 0.01,
              "Mur lateral vise de face : incidence nulle");
      Assert (abs (Wall_Incidence (30.0, 0.0) - 30.0) < 0.01,
              "A 30 deg d'azimut, mur de face : incidence 30");
      Assert (abs (Wall_Incidence (60.0, 0.0) - 30.0) < 0.01,
              "A 60 deg d'azimut, le rayon touche le mur lateral :"
              & " incidence 30, pas 60");
      Assert (abs (Wall_Incidence (0.0, 20.0) - 20.0) < 0.01,
              "Viser 20 deg plus haut incline d'autant sur le mur");
   end Test_Wall_Incidence;

   --  Test : un mur lisse est un miroir (realisme point 9). Vu de face,
   --  il renvoie l'echo speculaire complet ; vu sous 30 degres (ici en
   --  visant 30 degres plus haut ou plus bas), il ne renvoie qu'une part
   --  diffuse, au moins dix fois plus faible. La grille 4 x 3 vise les
   --  normales des quatre murs (azimuts 0, 90, 180, 270) aux elevations
   --  -30, 0 et +30 : aucun coin (ils sont a 36,9 degres), aucun objet.
   procedure Test_Specular_Wall
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Src     : Simulated_Source :=
        Make_Room_Scan (Az_Steps => 4, El_Steps => 3);
      M       : Measurement;
      OK      : Boolean;
      Peak    : Amplitude;
      Facing  : Amplitude := Amplitude'Last;  --  plus faible vu de face
      Oblique : Amplitude := 0;               --  plus fort vu de biais
   begin
      while Src.Has_More loop
         Src.Next (M, OK);
         Peak := M.Data (Peak_Bin (M.Data));
         if abs M.Elevation < 1.0 then
            Facing := Amplitude'Min (Facing, Peak);
         else
            Oblique := Amplitude'Max (Oblique, Peak);
         end if;
      end loop;

      Assert (Facing >= 2_000,
              "Un mur vu de face devrait renvoyer l'echo speculaire, obtenu"
              & Facing'Image);
      --  En Natural : un echo oblique anormalement fort ferait deborder
      --  Amplitude (0 .. 4095) en le multipliant, et le test planterait
      --  au lieu d'echouer proprement.
      Assert (Natural (Oblique) * 10 <= Natural (Facing),
              "Un mur vu sous 30 deg devrait renvoyer dix fois moins, obtenu"
              & Oblique'Image & " contre" & Facing'Image);
   end Test_Specular_Wall;

   --  Test 8 : carte de clutter (MTI). Un echo appris comme decor est
   --  supprime (meme a une case pres : marge de garde) ; un echo a une
   --  autre distance ou dans une autre direction passe.
   procedure Test_Clutter_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Clutter_Map;

      --  Une detection d'une seule cible, a la case demandee.
      function One (B : Bin_Index) return Detection is
      begin
         return (Targets => (1 => B, others => Bin_Index'First),
                 Count   => 1);
      end One;

   begin
      Clear (C);

      --  1re observation d'un echo en case 100 : pas encore du decor
      --  (un mobile qui passe ne doit pas empoisonner la carte).
      Learn (C, 9.0, 0.0, One (100));
      Assert (Filter (C, 9.0, 0.0, One (100)).Count = 1,
              "Une seule observation ne devrait pas faire du clutter");

      --  2e observation : la case est confirmee comme decor.
      Learn (C, 9.0, 0.0, One (100));
      Assert (Filter (C, 9.0, 0.0, One (100)).Count = 0,
              "L'echo du mur confirme devrait etre supprime");
      Assert (Filter (C, 9.0, 0.0, One (101)).Count = 0,
              "Un echo dans la marge de garde devrait etre supprime");
      Assert (Filter (C, 9.0, 0.0, One (150)).Count = 1,
              "Un echo a une autre distance devrait passer (mobile)");
      Assert (Filter (C, 90.0, 0.0, One (100)).Count = 1,
              "La meme case dans une AUTRE direction devrait passer");

      --  Oubli lent : deux vieillissements plus tard, le decor disparu
      --  est oublie et la case redevient libre.
      Age (C);
      Age (C);
      Assert (Filter (C, 9.0, 0.0, One (100)).Count = 1,
              "Le decor disparu devrait finir par etre oublie");
   end Test_Clutter_Filter;

   --  Test 8bis : la carte de clutter accepte tout angle FINI, sans
   --  boucler ni lever d'exception (code embarque). Mesure sur l'ancien
   --  To_Cell : l'elevation de 1E30 levait Constraint_Error ("overflow
   --  check failed") a sa conversion en entier, et un azimut de 1E30
   --  bouclait sans fin (toujours en cours apres 10 s) - il etait ramene
   --  dans [0, 360[ en retranchant 360, et a 1E30, Az - 360.0 vaut Az.
   procedure Test_Clutter_Any_Angle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C   : Clutter_Map;
      One : constant Detection :=
        (Targets => (1 => 100, others => Bin_Index'First), Count => 1);
   begin
      Clear (C);
      Learn (C, 9.0, 0.0, One);
      Learn (C, 9.0, 0.0, One);

      --  La meme direction, ecrite autrement : la meme case.
      Assert (Filter (C, 369.0, 0.0, One).Count = 0,
              "369 deg devrait designer la meme case que 9 deg");
      Assert (Filter (C, -351.0, 0.0, One).Count = 0,
              "-351 deg devrait designer la meme case que 9 deg");

      --  Elevation demesuree : bornee au bord haut de la grille (+30).
      Learn (C, 90.0, 1.0E30, One);
      Learn (C, 90.0, 1.0E30, One);
      Assert (Filter (C, 90.0, 30.0, One).Count = 0,
              "Une elevation de 1E30 devrait tomber sur le bord haut");

      --  Azimut demesure : une case, toujours la meme d'un appel a
      --  l'autre, et un retour (pas de boucle sans fin).
      Learn (C, 1.0E30, 0.0, One);
      Learn (C, 1.0E30, 0.0, One);
      Assert (Filter (C, 1.0E30, 0.0, One).Count = 0,
              "Un azimut de 1E30 devrait designer une case stable");
   end Test_Clutter_Any_Angle;

   --  Test 9 : CFAR. Un pic net au-dessus du bruit local est detecte ;
   --  un champ uniformement fort n'est pas une cible (chaque case vaut
   --  son bruit voisin) - un seuil fixe est incapable de faire ca.
   procedure Test_CFAR
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      S : Sweep;
   begin
      for I in Bin_Index loop
         S (I) := 50;
      end loop;
      S (100) := 1_000;

      declare
         D : constant Detection := Detect_Adaptive (S);
      begin
         Assert (D.Count = 1,
                 "Un pic net sur bruit uniforme = une cible");
         Assert (D.Targets (1) = 100,
                 "La cible devrait etre en case 100");
      end;

      for I in Bin_Index loop
         S (I) := 1_000;
      end loop;
      Assert (Detect_Adaptive (S).Count = 0,
              "Un champ uniformement fort n'est pas une cible");
   end Test_CFAR;

   --  Test : la source doit etre pilotable A travers L'interface.
   --  C'est le garde-fou de la regle R3. Les quatre modes declarent
   --  desormais Source'Class : si une operation dont ils ont besoin
   --  quittait l'interface, ce test cesserait de compiler - et on le
   --  saurait avant de decouvrir, au branchement du vrai capteur,
   --  qu'un mode etait colle au simulateur.
   procedure Test_Source_Dispatching
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Volontairement declaree en Source'Class : tous les appels
      --  ci-dessous sont dispatchants, aucun ne nomme le type concret.
      Src  : Source'Class := Make_Room_Scan (Az_Steps => 4, El_Steps => 3);
      M    : Measurement;
      OK   : Boolean;
      Seen : Natural := 0;
   begin
      Assert (Per_Turn (Src) = 12,
              "Un tour de 4 azimuts x 3 elevations fait 12 mesures");

      while Src.Has_More loop
         Src.Next (M, OK);
         Seen := Seen + 1;
      end loop;

      Assert (Seen = 12,
              "Le tour complet devrait livrer 12 mesures, obtenu "
              & Seen'Image);
   end Test_Source_Dispatching;

   --  Test : format compact des flottants envoyes a la page.
   --  Le piege est le nombre strictement entre -1 et 0 : sa partie
   --  entiere vaut zero, donc le signe se perd si on ne le porte pas
   --  separement ("-0.5" deviendrait "0.-5"). Les valeurs choisies
   --  evitent les fins en .x5, ou l'arrondi depend de la
   --  representation binaire exacte du Float.
   procedure Test_Float_Format
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (F_Img (0.0) = "0.0",
              "Zero devrait s'ecrire 0.0, obtenu " & F_Img (0.0));
      Assert (F_Img (2265.0) = "2265.0",
              "Une distance ronde, obtenu " & F_Img (2265.0));
      Assert (F_Img (-30.0) = "-30.0",
              "Une elevation negative, obtenu " & F_Img (-30.0));
      Assert (F_Img (-0.5) = "-0.5",
              "Le signe doit survivre a une partie entiere nulle, "
              & "obtenu " & F_Img (-0.5));
      Assert (F_Img (12.34) = "12.3",
              "Arrondi au dixieme, obtenu " & F_Img (12.34));
   end Test_Float_Format;

   --  Test : la vitesse ne doit PAS dependre de la cadence de balayage.
   --  C est tout l objet de la base de temps.
   --
   --  Une meme cible physique avance a 100 mm/s. Elle est vue par deux
   --  radars : l un fait un tour par seconde (elle avance de 100 mm
   --  entre deux regards), l autre deux tours par seconde (50 mm).
   --  AVANT la base de temps, le premier aurait rapporte "100" et le
   --  second "50" - deux nombres pour la meme realite. Desormais les
   --  deux doivent converger vers la meme valeur en mm/s.
   procedure Test_Speed_Rate_Independent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  Fait avancer une cible a 100 mm/s, vue tous les Period_Ms.
      function Measured_Speed (Period_Ms : Time_Ms) return Float is
         Trk  : Tracker;
         F    : Frame;
         Now  : Time_Ms := 0;
         Step : constant Float := 100.0 * Float (Period_Ms) / 1000.0;
      begin
         Reset (F);
         F.Count := 1;
         for N in 0 .. 19 loop
            Now := Now + Period_Ms;
            F.Stamp := Now;
            F.Items (1) := (Pos      => (Float (N) * Step, 0.0, 0.0),
                            Distance => Float (N) * Step);
            Update (Trk, F);
         end loop;
         return First_Active (Trk).Velocity.X;
      end Measured_Speed;

      Slow : constant Float := Measured_Speed (1_000);   --  1 tour/s
      Fast : constant Float := Measured_Speed (500);     --  2 tours/s
   begin
      Assert (abs (Slow - 100.0) < 10.0,
              "A 1 tour/s la vitesse devrait valoir 100 mm/s, obtenu "
              & Slow'Image);
      Assert (abs (Fast - 100.0) < 10.0,
              "A 2 tours/s elle devrait valoir 100 mm/s AUSSI, obtenu "
              & Fast'Image);
      Assert (abs (Slow - Fast) < 10.0,
              "Les deux cadences doivent donner la meme vitesse");
   end Test_Speed_Rate_Independent;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Coast_Is_Time_Based'Access,
         "Cycle de vie compte en temps, pas en mises a jour");
      Register_Routine
        (T, Test_Blind_Zone_Coast'Access,
         "Pistage : une cible qui traverse la zone aveugle garde son ID");
      Register_Routine
        (T, Test_Speed_Rate_Independent'Access,
         "Vitesse en mm/s independante de la cadence");
      Register_Routine
        (T, Test_Source_Dispatching'Access,
         "Source pilotee a travers l'interface (R3)");
      Register_Routine
        (T, Test_Float_Format'Access,
         "Format compact des flottants serialises");
      Register_Routine
        (T, Test_Geometry_Roundtrip'Access, "Aller-retour geometrie");
      Register_Routine
        (T, Test_Azimuth_Normalization'Access, "Normalisation d'azimut");
      Register_Routine
        (T, Test_Zenith'Access, "Point au zenith (bornage Arcsin)");
      Register_Routine
        (T, Test_Cluster'Access, "Regroupement de detections 3D");
      Register_Routine
        (T, Test_Track_Filter'Access,
         "Pistage : filtre alpha-beta, M-sur-N, coasting");
      Register_Routine
        (T, Test_Tentative_Dies'Access,
         "Pistage : une tentative jamais revue meurt");
      Register_Routine
        (T, Test_Global_Association'Access,
         "Pistage : association globale (pas de vol)");
      Register_Routine
        (T, Test_Track_Merge'Access,
         "Pistage : fusion anti-fragmentation");
      Register_Routine
        (T, Test_Crossing_Keeps_Ids'Access,
         "Pistage : deux cibles qui se croisent gardent leur ID");
      Register_Routine
        (T, Test_Stitching_Keeps_Id'Access,
         "Pistage : une cible perdue puis revue reprend son ID");
      Register_Routine
        (T, Test_Same_Stamp_Keeps_Velocity'Access,
         "Temps : frame au meme instant, aucune vitesse inferee");
      Register_Routine
        (T, Test_Late_Frame_Rejected'Access,
         "Temps : frame tardive rejetee, comptee, non revendiquee");
      Register_Routine
        (T, Test_Velocity_After_Gap'Access,
         "Temps : vitesse apres une absence, ecart pris depuis l'ancre");
      Register_Routine
        (T, Test_Regular_Cadence_Unchanged'Access,
         "Temps : cadence reguliere = filtre alpha-beta de reference");
      Register_Routine
        (T, Test_Interleaved_Velocity_Guard'Access,
         "Temps : sources entrelacees, garde-fou bruit de vitesse");
      Register_Routine
        (T, Test_Two_Echoes_Same_Ray'Access,
         "Deux echos sur un meme rayon");
      Register_Routine
        (T, Test_Wall_Distance'Access,
         "Distance aux murs de la piece");
      Register_Routine
        (T, Test_Wall_Incidence'Access,
         "Incidence sur les murs : choix du bon mur");
      Register_Routine
        (T, Test_Specular_Wall'Access,
         "Mur lisse : speculaire de face, diffus de biais");
      Register_Routine
        (T, Test_Clutter_Filter'Access,
         "Carte de clutter adaptative (MTI)");
      Register_Routine
        (T, Test_Clutter_Any_Angle'Access,
         "Clutter : tout angle fini, sans boucle ni exception");
      Register_Routine
        (T, Test_CFAR'Access,
         "Seuil adaptatif CFAR");
   end Register_Tests;

end Radar_Pipeline_Tests;
