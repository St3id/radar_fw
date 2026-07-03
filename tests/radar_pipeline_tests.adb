with AUnit.Assertions;  use AUnit.Assertions;
with Radar_Geometry;    use Radar_Geometry;
with Radar_Detect;      use Radar_Detect;
with Radar_Track;       use Radar_Track;
with Radar_Source;      use Radar_Source;
with Radar_World;       use Radar_World;
with Radar_Sweep;       use Radar_Sweep;
with Radar_Clutter;     use Radar_Clutter;

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

   --  Test 4 : regroupement. Deux echos d'une MEME cible etendue
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
              Missing => 0, Hits => 0, Confirmed => False, Active => False);
   end First_Active;

   --  Test 5 : cycle de vie et filtre de piste. Une cible qui avance de
   --  100 mm/tour : la piste nait TENTATIVE (non confirmee), se
   --  confirme apres 3 detections, sa vitesse FILTREE (alpha-beta)
   --  converge vers 100 mm/tour, et elle roule sur son erre pendant
   --  une occultation (coasting).
   procedure Test_Track_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);
      F.Count := 1;

      --  Tour 1 : premiere detection -> tentative, pas confirmee.
      F.Items (1) := (Pos => (0.0, 0.0, 0.0), Distance => 0.0);
      Update (Trk, F);
      Assert (not First_Active (Trk).Confirmed,
              "Une seule detection ne devrait pas confirmer la piste");

      --  Tours 2 a 10 : la cible avance de 100 mm par tour.
      for N in 1 .. 9 loop
         F.Items (1) := (Pos => (Float (N) * 100.0, 0.0, 0.0),
                         Distance => Float (N) * 100.0);
         Update (Trk, F);
      end loop;

      Assert (First_Active (Trk).Confirmed,
              "La piste devrait etre confirmee (M-sur-N)");
      Assert (First_Active (Trk).Id = 1,
              "L'ID d'origine devrait etre conserve");
      Assert (abs (First_Active (Trk).Velocity.X - 100.0) < 20.0,
              "La vitesse filtree devrait converger vers 100 mm/tour");

      --  Occultation de 2 tours : la piste confirmee SURVIT et sa
      --  position continue d'avancer sur son erre.
      declare
         Before : constant Float := First_Active (Trk).Pos.X;
      begin
         Update (Trk, Empty);
         Update (Trk, Empty);
         Assert (First_Active (Trk).Active
                 and then First_Active (Trk).Confirmed,
                 "La piste confirmee devrait survivre a l'occultation");
         Assert (First_Active (Trk).Pos.X > Before + 100.0,
                 "Coasting : la position devrait continuer d'avancer");
      end;
   end Test_Track_Filter;

   --  Test 5ter : ASSOCIATION GLOBALE. Deux pistes etablies en x=0 et
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
      F   : Frame;
   begin
      Reset (F);
      F.Count := 2;

      --  3 tours : deux pistes immobiles en 0 et 500, confirmees.
      for N in 1 .. 3 loop
         F.Items (1) := (Pos => (0.0, 0.0, 0.0),   Distance => 0.0);
         F.Items (2) := (Pos => (500.0, 0.0, 0.0), Distance => 500.0);
         Update (Trk, F);
      end loop;

      --  Le tour litigieux.
      F.Items (1) := (Pos => (480.0, 0.0, 0.0), Distance => 480.0);
      F.Items (2) := (Pos => (950.0, 0.0, 0.0), Distance => 950.0);
      Update (Trk, F);

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

   --  Test 5quater : FUSION anti-fragmentation. Deux echos persistants
   --  a 350 mm l'un de l'autre (cible etendue scindee) ne doivent
   --  produire qu'UNE piste - pas de piste "ombre".
   procedure Test_Track_Merge
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk : Tracker;
      F   : Frame;
   begin
      Reset (F);
      F.Count := 2;
      for N in 1 .. 5 loop
         F.Items (1) := (Pos => (0.0, 0.0, 0.0),   Distance => 0.0);
         F.Items (2) := (Pos => (350.0, 0.0, 0.0), Distance => 350.0);
         Update (Trk, F);
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

   --  Test 5bis : une TENTATIVE non re-detectee meurt vite. C'est le
   --  filtre anti-fantomes : un echo de multitrajet, intermittent,
   --  ne survit pas assez longtemps pour etre confirme.
   procedure Test_Tentative_Dies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);
      F.Count := 1;
      F.Items (1) := (Pos => (1000.0, 0.0, 0.0), Distance => 1000.0);

      Update (Trk, F);       --  un echo isole -> tentative
      Update (Trk, Empty);   --  plus rien...
      Update (Trk, Empty);

      Assert (not First_Active (Trk).Active,
              "Une tentative jamais revue devrait mourir sans trace");
   end Test_Tentative_Dies;

   --  Test 6 : deux echos sur le MEME rayon (deux objets alignes) =
   --  deux detections (regression : avant, seul le pic etait garde et
   --  le second objet etait invisible).
   procedure Test_Two_Echoes_Same_Ray
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      M : Measurement := (Azimuth => 0.0, Elevation => 0.0,
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

      --  1re observation d'un echo en case 100 : PAS encore du decor
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

   --  Test 9 : CFAR. Un pic net au-dessus du bruit local est detecte ;
   --  un champ UNIFORMEMENT fort n'est PAS une cible (chaque case vaut
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

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
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
        (T, Test_Two_Echoes_Same_Ray'Access,
         "Deux echos sur un meme rayon");
      Register_Routine
        (T, Test_Wall_Distance'Access,
         "Distance aux murs de la piece");
      Register_Routine
        (T, Test_Clutter_Filter'Access,
         "Carte de clutter adaptative (MTI)");
      Register_Routine
        (T, Test_CFAR'Access,
         "Seuil adaptatif CFAR");
   end Register_Tests;

end Radar_Pipeline_Tests;
