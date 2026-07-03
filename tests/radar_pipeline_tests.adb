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

   --  Test 5 : pistage. Une piste ratee pendant 2 tours puis retrouvee
   --  300 mm plus loin s'est deplacee sur 3 tours : la vitesse doit etre
   --  100 mm/tour (regression : avant, on rendait 300, surestime x3).
   procedure Test_Track_Velocity_After_Miss
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Trk   : Tracker;
      F     : Frame;
      Empty : Frame;
   begin
      Reset (F);
      Reset (Empty);

      --  Tour 1 : creation de la piste en (0,0,0).
      F.Count := 1;
      F.Items (1) := (Pos => (0.0, 0.0, 0.0), Distance => 0.0);
      Update (Trk, F);

      --  Tours 2 et 3 : l'objet n'est pas revu.
      Update (Trk, Empty);
      Update (Trk, Empty);

      --  Tour 4 : retrouve 300 mm plus loin.
      F.Items (1) := (Pos => (300.0, 0.0, 0.0), Distance => 300.0);
      Update (Trk, F);

      declare
         Found : Boolean := False;
      begin
         for Tk of Trk.Tracks loop
            if Tk.Active then
               Assert (not Found, "Une seule piste devrait etre active");
               Found := True;
               Assert (Tk.Id = 1, "L'ID de la piste devrait rester 1");
               Assert (abs (Tk.Velocity.X - 100.0) < 0.001,
                       "300 mm en 3 tours devraient donner 100 mm/tour");
            end if;
         end loop;
         Assert (Found, "La piste devrait avoir survecu aux tours rates");
      end;
   end Test_Track_Velocity_After_Miss;

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

      --  Apprentissage : un mur en case 100, direction az=9, el=0.
      Learn (C, 9.0, 0.0, One (100));

      Assert (Filter (C, 9.0, 0.0, One (100)).Count = 0,
              "L'echo du mur appris devrait etre supprime");
      Assert (Filter (C, 9.0, 0.0, One (101)).Count = 0,
              "Un echo dans la marge de garde devrait etre supprime");
      Assert (Filter (C, 9.0, 0.0, One (150)).Count = 1,
              "Un echo a une autre distance devrait passer (mobile)");
      Assert (Filter (C, 90.0, 0.0, One (100)).Count = 1,
              "La meme case dans une AUTRE direction devrait passer");
   end Test_Clutter_Filter;

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
        (T, Test_Track_Velocity_After_Miss'Access,
         "Vitesse de piste apres tours rates");
      Register_Routine
        (T, Test_Two_Echoes_Same_Ray'Access,
         "Deux echos sur un meme rayon");
      Register_Routine
        (T, Test_Wall_Distance'Access,
         "Distance aux murs de la piece");
      Register_Routine
        (T, Test_Clutter_Filter'Access,
         "Carte de clutter (MTI)");
   end Register_Tests;

end Radar_Pipeline_Tests;
