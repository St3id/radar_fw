with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

--  Corps de Radar_Track. Les cinq etapes d'un tour de pistage sont
--  numerotees dans Update et decrites dans la specification ; leur ordre
--  n'est pas indifferent, la prediction devant preceder l'association.

package body Radar_Track is

   --  Fenetre d association ("gate") : distance max entre une
   --  detection et la position PREDITE d une piste.
   --
   --  Elle ne peut pas etre constante. Le terme fixe couvre le bruit de
   --  mesure et l etalement de la cible ; le terme proportionnel couvre
   --  la MANOEUVRE : si la cible change de cap pendant dt, la
   --  prediction se trompe d environ v x dt. Avec un balayage
   --  mecanique, dt varie d une fraction de seconde a des dizaines de
   --  secondes selon la direction - un rayon fige serait beaucoup trop
   --  large tout de suite, ou beaucoup trop etroit ensuite.
   Base_Gate : constant Float := 600.0;

   --  Intervalle minimal entre deux corrections de VITESSE d'une piste.
   --
   --  La vitesse se corrige en divisant un ecart de position par le temps
   --  qui l'a produit. Sur un intervalle trop court, l'ecart n'est que du
   --  bruit de mesure et la division l'amplifie. Mesure sur l'ancien code
   --  (plancher de 1 ms) : une seconde frame au meme instant, 100 mm a
   --  cote, faisait passer une cible a 1 m/s a 29 m/s ; deux sources
   --  decalees de 10 ms donnaient de -3,5 a +5,5 m/s. Sous ce seuil, seule
   --  la position est corrigee, et l'ecart se mesure ensuite depuis
   --  l'ancre (Vel_Anchor), sur toute la duree ecoulee.
   --
   --  70 ms est une HYPOTHESE DE BANC, pas une mesure : P - 2 J, avec la
   --  cadence annoncee du LD2450 (P = 100 ms, non chronometree sur notre
   --  chaine) et une gigue supposee de J = 15 ms par horodatage. Sous ces
   --  hypotheses, deux frames successives d'une meme source corrigent
   --  toujours la vitesse, comme avant, et tout intervalle plus court
   --  (rafale de reception, second capteur decale) est ecarte. A
   --  reevaluer des que la periode et la gigue reelles du module auront
   --  ete mesurees.
   Min_Velocity_Interval_Ms : constant Time_Ms := 70;

   --  Gains du filtre alpha-beta : part de l'ecart mesure reinjectee
   --  dans la position (Alpha) et dans la vitesse (Beta). Des valeurs
   --  moderees lissent le jitter d'une cible etendue sans trop retarder
   --  la reaction aux vrais changements de cap.
   --
   --  Alpha = 0,5 : a mi-chemin entre la mesure et la prediction. Proche
   --  de 1, on croirait la mesure sur parole et le jitter d'une cible
   --  etendue (son centre percu se promene de 20 a 30 cm d'un tour a
   --  l'autre) partirait tel quel dans la position. Proche de 0, la
   --  piste ignorerait la mesure et deriverait sur sa seule erre.
   --
   --  Beta est DIVISE par la duree couverte par l'ecart (depuis l'ancre de
   --  la piste, voir Min_Velocity_Interval_Ms), et ce n'est pas un detail : un
   --  meme ecart de position observe sur un intervalle court revele une
   --  erreur de vitesse plus grande que le meme ecart observe sur un
   --  intervalle long. Sans cette division, la vitesse estimee
   --  dependrait de la cadence de balayage - c'est exactement ce que le
   --  test "vitesse independante de la cadence" interdit.
   Alpha : constant Float := 0.5;
   Beta  : constant Float := 0.3;

   --  Duree de survie sans echo, en MILLISECONDES et non en nombre de
   --  tours. Une piste confirmee "roule sur son erre" pendant les
   --  fading et trous de detection ; une tentative, elle, meurt vite -
   --  c est le filtre anti-fantomes.
   --
   --  Compter en tours etait juste tant qu une seule source cadencait le
   --  systeme. Des que deux sources de cadences differentes alimentent le
   --  meme pistage, chacune appelle Update : un compteur de tours ferait
   --  vieillir une piste plus vite selon le nombre de sources. Le temps,
   --  lui, ne depend d aucune cadence.
   Max_Coast_Confirmed_Ms : constant Time_Ms := 2_500;
   Max_Coast_Tentative_Ms : constant Time_Ms :=   900;

   --  Survie d une piste confirmee dont la position predite est dans la
   --  zone aveugle du capteur (Frame.Min_Range). La, ne rien voir est
   --  NORMAL : ce n est pas un indice de disparition.
   --
   --  10 s, mesure et non devine : en mode live, un objet lent
   --  (~130 mm/s) traverse la zone aveugle de 625 mm en 4 a 10 s ; a
   --  2,5 s, il ressortait avec un nouvel identifiant (3 changements sur
   --  6 en 254 tours). Pas infini pour autant : c est une piste
   --  fantome qui reste affichee, et si un AUTRE objet ressort de la
   --  zone avant l echeance, il herite de l identifiant. 10 s borne ce
   --  risque a la duree reellement observee.
   Max_Coast_Blind_Ms : constant Time_Ms := 10_000;

   --  Deux pistes actives a moins de cette distance (mm) sont le meme
   --  objet fragmente : elles fusionnent (inferieur au rayon de
   --  regroupement pour ne pas coller deux objets vraiment distincts).
   Merge_Radius : constant Float := 400.0;

   --  Ecart de vitesse (mm/s) au-dela duquel deux pistes CONFIRMEES
   --  proches sont deux objets distincts, et non un objet fragmente.
   --
   --  La proximite seule ne suffit pas : deux personnes qui se croisent
   --  passent a quelques centimetres l'une de l'autre (112 mm au croisement
   --  du mode track), et la fusion tuait l'une des deux pistes. Ce qui les
   --  distingue d'un fragment, c'est le mouvement : un fragment suit son
   --  objet, a la meme vitesse ; deux objets qui se croisent vont dans des
   --  directions differentes. On fusionne donc dans l'espace des etats
   --  (position ET vitesse), comme les pisteurs radar usuels.
   --
   --  150 mm/s : au-dessus du bruit de vitesse d'une piste de ce filtre
   --  (~50 mm/s par axe pour un jitter de 120 mm a 0,84 s par tour, donc
   --  ~100 mm/s d'ecart entre deux pistes du meme objet), en dessous de
   --  l'ecart des deux objets simules qui se croisent (~220 mm/s). Les
   --  tentatives, dont la vitesse n'est pas encore connue, fusionnent
   --  comme avant : la protection contre les pistes "ombre" reste entiere.
   Merge_Speed_Gap : constant Float := 150.0;

   function Dist3D (A, B : Point_3D) return Float is
     (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   --  Recollage des pistes ("track stitching"). Une piste confirmee peut
   --  mourir alors que son objet est toujours la : trou de detection plus
   --  long que le coasting, bord de faisceau, ou perte interne au module
   --  (les integrateurs du RD-03D/LD2450 constatent que le module perd
   --  lui-meme ses cibles par intermittence). Sans recollage, l'objet
   --  revient sous un NOUVEL identifiant : une saccade pour l'utilisateur.
   --
   --  On ne recolle qu'a la CONFIRMATION de la nouvelle piste, jamais a sa
   --  naissance : une fausse alarme, qui ne se confirme pas, ne peut pas
   --  voler l'identifiant d'un objet disparu.
   --
   --  6 s : au-dela, la position extrapolee ne vaut plus rien, et un autre
   --  objet entre dans la piece a cet endroit devient trop vraisemblable.
   Stitch_Window_Ms : constant Time_Ms := 6_000;

   --  Marge de recollage : la fenetre d'association de base, plus une
   --  derive qui grandit avec la duree de l'absence (mm par seconde).
   --  300 mm/s laisse a un pieton ~1,2 m de deviation en 4 s d'absence sans
   --  ouvrir le recollage a toute la piece, ce que ferait une marge en
   --  vitesse maximale (1,5 m/s x 4 s = 6 m).
   Stitch_Drift : constant Float := 300.0;

   --  Deux pistes proches sont-elles le MEME objet ? Toujours si l'une
   --  n'est qu'une tentative ; pour deux confirmees, seulement si elles
   --  vont a la meme vitesse.
   function Same_Object (A, B : Track) return Boolean is
     (not (A.Confirmed and then B.Confirmed)
      or else Dist3D (A.Velocity, B.Velocity) < Merge_Speed_Gap);

   --  Temps ecoule depuis la derniere association de cette piste.
   function Since_Seen (Tk : Track; Now : Time_Ms) return Time_Ms is
     (if Now > Tk.Last_Seen then Now - Tk.Last_Seen else 0);

   --  Demi-taille d une cible, en mm. Une cible n est pas un point : ses
   --  reflecteurs s etalent autour de son centre (+/-150 mm dans le
   --  simulateur, epaules d une personne ~ +/-200 mm). Son echo
   --  s effondre donc des que son BORD entre dans la zone aveugle, bien
   --  avant son centre. Mesure : un objet perdu a 595 mm reapparaissait
   --  a 731 mm, alors que sa position predite etait deja ressortie
   --  (664 mm) - sans cette marge, la piste mourait au bout de 2,5 s.
   --  C est une propriete de la CIBLE, d ou sa place ici ; la portee
   --  minimale, propriete du CAPTEUR, voyage dans la frame.
   Target_Half_Extent : constant Float := 200.0;

   --  La piste est-elle la ou le capteur ne la voit pas en entier ? Les
   --  positions sont exprimees dans le repere du capteur : la distance
   --  a l origine est la distance au radar. Un capteur qui voit tout
   --  (Min_Range = 0) n a pas de zone aveugle, meme avec la marge.
   function In_Blind_Zone (Tk : Track; F : Frame) return Boolean is
     (F.Min_Range > 0.0
      and then Sqrt (Tk.Pos.X ** 2 + Tk.Pos.Y ** 2 + Tk.Pos.Z ** 2)
               < F.Min_Range + Target_Half_Extent);

   function Speed_Of (Tk : Track) return Float is
     (Sqrt (Tk.Velocity.X ** 2 + Tk.Velocity.Y ** 2 + Tk.Velocity.Z ** 2));

   --  Fenetre d association de CETTE piste pour CE dt.
   function Gate_Of (Tk : Track; Dt : Float) return Float is
     (Base_Gate + Speed_Of (Tk) * Dt);

   --  Temps ecoule (s) entre la derniere frame traitee et F. Partage par
   --  Update et Owners : la position que Owners croit "predite" doit etre
   --  exactement celle qu'Update predira ensuite, sinon une detection
   --  serait attribuee a une piste qu'Update ne lui associerait pas.
   --  Nul pour une frame au meme instant : rien n'est alors predit, et
   --  plus aucune division ne se fait par ce dt.
   function Frame_Dt (T : Tracker; F : Frame) return Float is
     (Float (if F.Stamp > T.Last_Stamp then F.Stamp - T.Last_Stamp else 0)
      / 1000.0);

   --  Position d'une piste avancee de Dt secondes sur sa vitesse.
   function Predicted (Tk : Track; Dt : Float) return Point_3D is
     ((X => Tk.Pos.X + Tk.Velocity.X * Dt,
       Y => Tk.Pos.Y + Tk.Velocity.Y * Dt,
       Z => Tk.Pos.Z + Tk.Velocity.Z * Dt));

   --  Garde la trace d'une piste confirmee qui meurt, dans un emplacement
   --  libre ou, a defaut, a la place de la plus ancienne.
   procedure Bury (Lost : in out Lost_Array; Tk : Track; Now : Time_Ms) is
      Slot : Positive := Lost'First;
   begin
      for L in Lost'Range loop
         if Lost (L).Id = 0 then
            Slot := L;
            exit;
         elsif Lost (L).Lost_At < Lost (Slot).Lost_At then
            Slot := L;
         end if;
      end loop;
      Lost (Slot) := (Id       => Tk.Id,
                      Pos      => Tk.Pos,
                      Velocity => Tk.Velocity,
                      Lost_At  => Now);
   end Bury;

   --  La piste I vient de se confirmer : se trouve-t-elle la ou une piste
   --  perdue depuis moins de Stitch_Window_Ms aurait du etre ? Si oui, elle
   --  reprend son identifiant (la plus proche si plusieurs conviennent).
   procedure Try_Stitch
     (T : in out Tracker; I : Positive; Now : Time_Ms)
   is
      Best      : Natural := 0;
      Best_Dist : Float   := Float'Last;
   begin
      for L in T.Lost'Range loop
         if T.Lost (L).Id /= 0 then
            declare
               Age : constant Time_Ms :=
                 (if Now > T.Lost (L).Lost_At then Now - T.Lost (L).Lost_At
                  else 0);
               Age_S : constant Float := Float (Age) / 1000.0;
               Expected : constant Point_3D :=
                 (X => T.Lost (L).Pos.X + T.Lost (L).Velocity.X * Age_S,
                  Y => T.Lost (L).Pos.Y + T.Lost (L).Velocity.Y * Age_S,
                  Z => T.Lost (L).Pos.Z + T.Lost (L).Velocity.Z * Age_S);
               D : constant Float := Dist3D (Expected, T.Tracks (I).Pos);
            begin
               if Age > Stitch_Window_Ms then
                  T.Lost (L).Id := 0;   --  trop vieille : on l'oublie
               elsif D <= Base_Gate + Stitch_Drift * Age_S
                 and then D < Best_Dist
               then
                  Best      := L;
                  Best_Dist := D;
               end if;
            end;
         end if;
      end loop;

      if Best /= 0 then
         T.Tracks (I).Id := T.Lost (Best).Id;
         T.Lost (Best).Id := 0;
      end if;
   end Try_Stitch;

   ------------
   -- Update --
   ------------

   procedure Update (T : in out Tracker; F : Frame) is
      Matched : array (1 .. Max_Detections) of Boolean := (others => False);

      --  Temps ecoule depuis la frame precedente, en SECONDES.
      Dt : constant Float := Frame_Dt (T, F);
   begin
      --  ----- 0. Frame tardive : rejetee entiere, et comptee -----
      --  Traitee, elle ferait reculer l'horloge du pistage et fausserait
      --  vitesses et durees de survie (mesure sur l'ancien code : vitesse
      --  de -14,35 m/s et Last_Stamp qui recule de 50 ms). Rien n'est
      --  vieilli par elle : elle ne prouve rien sur le present.
      if F.Stamp < T.Last_Stamp then
         if T.Late_Frames < Natural'Last then
            T.Late_Frames := T.Late_Frames + 1;
         end if;
         return;
      end if;

      --  ----- 1. Prediction : chaque piste avance de v x dt -----
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            T.Tracks (I).Pos := Predicted (T.Tracks (I), Dt);
         end if;
      end loop;

      --  ----- 2 et 3. Association globale puis correction alpha-beta -----
      --  On prend iterativement la paire (piste, detection) la plus
      --  proche au monde, sous le rayon d'association. Contrairement au
      --  "chaque piste prend son plus proche" (glouton, dependant de
      --  l'ordre des pistes), aucune piste ne vole la detection d'une
      --  autre mieux placee.
      declare
         Track_Done : array (T.Tracks'Range) of Boolean :=
           (others => False);
      begin
         loop
            declare
               Best_I    : Natural := 0;
               Best_J    : Natural := 0;
               Best_Dist : Float   := Float'Last;
            begin
               for I in T.Tracks'Range loop
                  if T.Tracks (I).Active and then not Track_Done (I) then
                     for J in 1 .. F.Count loop
                        if not Matched (J) then
                           declare
                              D : constant Float :=
                                Dist3D (T.Tracks (I).Pos, F.Items (J).Pos);
                           begin
                              if D <= Gate_Of (T.Tracks (I), Dt)
                                and then D < Best_Dist
                              then
                                 Best_Dist := D;
                                 Best_I    := I;
                                 Best_J    := J;
                              end if;
                           end;
                        end if;
                     end loop;
                  end if;
               end loop;

               exit when Best_I = 0;

               --  Correction alpha-beta : on ne saute pas sur la
               --  mesure, on s'en rapproche (Alpha) et on ajuste la
               --  vitesse d'une fraction de l'ecart (Beta).
               declare
                  Rx : constant Float :=
                    F.Items (Best_J).Pos.X - T.Tracks (Best_I).Pos.X;
                  Ry : constant Float :=
                    F.Items (Best_J).Pos.Y - T.Tracks (Best_I).Pos.Y;
                  Rz : constant Float :=
                    F.Items (Best_J).Pos.Z - T.Tracks (Best_I).Pos.Z;
               begin
                  T.Tracks (Best_I).Pos :=
                    (X => T.Tracks (Best_I).Pos.X + Alpha * Rx,
                     Y => T.Tracks (Best_I).Pos.Y + Alpha * Ry,
                     Z => T.Tracks (Best_I).Pos.Z + Alpha * Rz);
                  --  Vitesse : seulement si l'ancre est assez ancienne,
                  --  et avec TOUT l'ecart accumule depuis elle. L'ecart
                  --  courant (Rx) ne suffirait pas : les corrections de
                  --  position intermediaires en ont deja absorbe une part.
                  --  Quand chaque frame associe la piste a plus du seuil
                  --  de la precedente, l'ancre est la position de la frame
                  --  precedente et ce calcul redonne exactement l'ancien.
                  declare
                     Tk : Track renames T.Tracks (Best_I);
                     E  : constant Time_Ms :=
                       (if F.Stamp > Tk.Vel_Stamp
                        then F.Stamp - Tk.Vel_Stamp else 0);
                  begin
                     if E >= Min_Velocity_Interval_Ms then
                        declare
                           Es : constant Float := Float (E) / 1000.0;
                           G  : constant Float := Beta / Es;
                           P  : constant Point_3D := Tk.Vel_Anchor;
                           V  : constant Point_3D := Tk.Velocity;
                           M  : Point_3D renames F.Items (Best_J).Pos;
                        begin
                           Tk.Velocity :=
                             (X => V.X + G * (M.X - (P.X + V.X * Es)),
                              Y => V.Y + G * (M.Y - (P.Y + V.Y * Es)),
                              Z => V.Z + G * (M.Z - (P.Z + V.Z * Es)));
                           Tk.Vel_Anchor := Tk.Pos;
                           Tk.Vel_Stamp  := F.Stamp;
                        end;
                     end if;
                  end;
               end;

               T.Tracks (Best_I).Missing   := 0;
               T.Tracks (Best_I).Last_Seen := F.Stamp;
               T.Tracks (Best_I).Hits      := T.Tracks (Best_I).Hits + 1;
               if T.Tracks (Best_I).Hits >= Confirm_Hits
                 and then not T.Tracks (Best_I).Confirmed
               then
                  T.Tracks (Best_I).Confirmed := True;
                  Try_Stitch (T, Best_I, F.Stamp);
               end if;
               Track_Done (Best_I) := True;
               Matched (Best_J)    := True;
            end;
         end loop;

         --  ----- 4a. Pistes non revues ce tour-ci -----
         --  Le delai de survie depend de ce que l absence d echo PROUVE.
         --  Une tentative non revue est probablement une fausse alarme :
         --  delai court. Une piste confirmee dans le champ du capteur a
         --  pu subir un fading : delai moyen. Une piste confirmee dans
         --  la zone aveugle n a simplement pas pu etre vue : delai long.
         for I in T.Tracks'Range loop
            if T.Tracks (I).Active and then not Track_Done (I) then
               declare
                  Tk    : Track renames T.Tracks (I);
                  Limit : constant Time_Ms :=
                    (if not Tk.Confirmed then Max_Coast_Tentative_Ms
                     elsif In_Blind_Zone (Tk, F) then Max_Coast_Blind_Ms
                     else Max_Coast_Confirmed_Ms);
               begin
                  Tk.Missing := Tk.Missing + 1;
                  if Since_Seen (Tk, F.Stamp) > Limit then
                     Tk.Active := False;
                     --  Une piste confirmee qui meurt peut etre recollee.
                     if Tk.Confirmed then
                        Bury (T.Lost, Tk, F.Stamp);
                     end if;
                  end if;
               end;
            end if;
         end loop;
      end;

      --  ----- 4b. Une tentative pour chaque detection orpheline -----
      for J in 1 .. F.Count loop
         if not Matched (J) then
            for I in T.Tracks'Range loop
               if not T.Tracks (I).Active then
                  T.Tracks (I) :=
                    (Id        => T.Next_Id,
                     Pos       => F.Items (J).Pos,
                     Velocity  => (0.0, 0.0, 0.0),  --  inconnue au depart
                     Missing   => 0,
                     Last_Seen => F.Stamp,
                     Hits      => 1,
                     Confirmed  => False,
                     Active     => True,
                     Vel_Stamp  => F.Stamp,
                     Vel_Anchor => F.Items (J).Pos);
                  T.Next_Id := T.Next_Id + 1;
                  exit;
               end if;
            end loop;
         end if;
      end loop;

      --  ----- 5. Fusion des pistes fragmentees -----
      --  Deux pistes actives a moins de Merge_Radius sont le meme objet
      --  (cible etendue scindee par la quantification, ou tentative nee
      --  d'un eclat) : la plus ancienne (plus de detections) absorbe
      --  l'autre - pas de piste "ombre" a l'affichage.
      for I in T.Tracks'Range loop
         if T.Tracks (I).Active then
            for J in I + 1 .. T.Tracks'Last loop
               if T.Tracks (J).Active
                 and then Dist3D (T.Tracks (I).Pos, T.Tracks (J).Pos)
                          < Merge_Radius
                 and then Same_Object (T.Tracks (I), T.Tracks (J))
               then
                  declare
                     Keep  : constant Natural :=
                       (if T.Tracks (I).Hits >= T.Tracks (J).Hits
                        then I else J);
                     Drop  : constant Natural :=
                       (if Keep = I then J else I);
                  begin
                     T.Tracks (Keep).Confirmed :=
                       T.Tracks (Keep).Confirmed
                       or else T.Tracks (Drop).Confirmed;
                     T.Tracks (Drop).Active := False;
                  end;
               end if;

               --  Si c'est I qui vient d'etre absorbee, ne plus rien
               --  comparer contre elle.
               exit when not T.Tracks (I).Active;
            end loop;
         end if;
      end loop;

      --  L heure de reference du prochain tour.
      T.Last_Stamp := F.Stamp;
   end Update;

   ------------
   -- Owners --
   ------------

   function Owners (T : Tracker; F : Frame) return Owner_List is
      Result : Owner_List := No_Owner;
      Dt     : constant Float := Frame_Dt (T, F);
   begin
      --  Une frame qu'Update rejettera n'est revendiquee par aucune piste :
      --  Owners et Update doivent voir le meme temps.
      if F.Stamp < T.Last_Stamp then
         return Result;
      end if;

      for J in 1 .. F.Count loop
         declare
            Best_Dist : Float := Float'Last;
         begin
            --  Seules les pistes CONFIRMEES revendiquent : une tentative
            --  est peut-etre un fantome, et la laisser couper un groupe
            --  reintroduirait la fragmentation que le regroupement evite.
            for I in T.Tracks'Range loop
               if T.Tracks (I).Active and then T.Tracks (I).Confirmed then
                  declare
                     D : constant Float :=
                       Dist3D (Predicted (T.Tracks (I), Dt), F.Items (J).Pos);
                  begin
                     if D <= Gate_Of (T.Tracks (I), Dt)
                       and then D < Best_Dist
                     then
                        Best_Dist  := D;
                        Result (J) := I;
                     end if;
                  end;
               end if;
            end loop;
         end;
      end loop;
      return Result;
   end Owners;

end Radar_Track;
