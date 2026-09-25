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
              Confirmed => False, Active => False);
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
        (T, Test_CFAR'Access,
         "Seuil adaptatif CFAR");
   end Register_Tests;

end Radar_Pipeline_Tests;
