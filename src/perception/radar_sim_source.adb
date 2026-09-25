with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;         use Ada.Numerics.Float_Random;
with Radar_Geometry;  use Radar_Geometry;
with Radar_Sweep;     use Radar_Sweep;

--  Corps de Radar_Sim_Source. Le generateur aleatoire part d'une graine
--  fixe : deux executions donnent exactement le meme flux de mesures, ce
--  qui permet de rejouer un defaut de pistage sans materiel.

package body Radar_Sim_Source is

   Beam_Width : constant Float := 3.0;   --  tolerance azimut (degres)
   El_Width   : constant Float := 5.0;   --  tolerance elevation (degres)

   --  Bruit de fond : amplitude max du bruit aleatoire present dans
   --  chaque case (le monde reel n'est jamais silencieux). C'est le
   --  CFAR qui s'en accommode ; un seuil fixe ne le pourrait pas.
   Noise_Level : constant Float := 80.0;

   --  ----- Realisme des cibles (ARCHITECTURE.md, realisme point 1) -----

   --  Position des reflecteurs par rapport au centre de l'objet, en mm
   --  (une cible etendue type humain : torse, membres...).
   type Offset is record
      X, Y, Z : Float;
   end record;

   Offsets : constant array (1 .. Scatter_Count) of Offset :=
     ((120.0, 50.0, 40.0),
      (-90.0, 100.0, -50.0),
      (40.0, -120.0, 90.0),
      (-70.0, -60.0, -100.0));

   --  Fading simplifie : le niveau est retire uniformement a chaque tour,
   --  sans appliquer la loi statistique d'un modele Swerling.
   --  Min_Echo reste au-dessus du seuil CFAR typique (4 x bruit moyen
   --  ~40 = 160) : un echo present est detectable, sauf malchance.
   Min_Echo : constant Amplitude := 250;
   Max_Echo : constant Amplitude := 3_500;

   --  Probabilite qu'un reflecteur soit eteint ce tour-ci (orientation
   --  defavorable), et qu'un objet entier s'evanouisse (fading profond).
   Dropout_Probability   : constant Float := 0.15;
   Deep_Fade_Probability : constant Float := 0.10;

   --  Multitrajet : probabilite qu'un objet produise ce tour-ci un echo
   --  fantome derriere le mur (trajet radar -> mur -> cible -> radar).
   --  Intermittent par nature : c'est la regle M-sur-N du pistage qui
   --  doit l'empecher de devenir une piste.
   Ghost_Probability : constant Float := 0.05;
   Ghost_Echo        : constant Amplitude := 500;

   --  Generateur a graine fixe : les sorties restent reproductibles
   --  d'une execution a l'autre (CI, comparaisons, mise au point).
   Gen : Ada.Numerics.Float_Random.Generator;

   --  Re-tire les amplitudes de tous les reflecteurs pour un tour.
   procedure Roll_Echoes (Self : in out Simulated_Source) is
   begin
      for I in 1 .. Max_Objects loop
         declare
            Faded : constant Boolean :=
              Random (Gen) < Deep_Fade_Probability;
         begin
            for K in 1 .. Scatter_Count loop
               if Faded or else Random (Gen) < Dropout_Probability then
                  Self.Echoes (I, K) := 0;   --  eteint ce tour-ci
               else
                  Self.Echoes (I, K) :=
                    Min_Echo
                    + Amplitude (Random (Gen) * Float (Max_Echo - Min_Echo));
               end if;
            end loop;

            Self.Ghosting (I) := Random (Gen) < Ghost_Probability;
         end;
      end loop;
   end Roll_Echoes;

   --  Plage d'elevation balayee : de -30 a +30 degres.
   El_Min : constant Float := -30.0;
   El_Max : constant Float := 30.0;

   --  Ecart angulaire minimal entre deux angles en degres, en tenant
   --  compte du passage 0/360 : l'ecart entre 359 et 1 vaut 2, pas 358.
   function Angle_Diff (A, B : Float) return Float is
      D : constant Float := abs (A - B);
   begin
      if D > 180.0 then
         return 360.0 - D;
      else
         return D;
      end if;
   end Angle_Diff;

   function Distance_To_Bin (Dist : Float) return Bin_Index is
      Mm_Per_Bin : constant Float :=
        Float (Max_Range_Mm) / Float (Sweep_Length);
      Raw : Integer;
   begin
      --  Float'Floor et pas une conversion directe : en Ada, Integer (X)
      --  arrondit au plus proche, alors que la conversion inverse
      --  (Bin_Distance) tronque. Les deux sens doivent partager la meme
      --  convention (debut de tranche), sinon l'aller-retour
      --  distance -> case -> distance derive d'une demi-case.
      Raw := Integer (Float'Floor (Dist / Mm_Per_Bin)) + 1;
      if Raw < Integer (Bin_Index'First) then
         return Bin_Index'First;
      elsif Raw > Integer (Bin_Index'Last) then
         return Bin_Index'Last;
      else
         return Bin_Index (Raw);
      end if;
   end Distance_To_Bin;

   --  ----- Murs speculaires (ARCHITECTURE.md, realisme point 9) -----
   --  Modele de scenario, pas loi universelle des murs : echo fort pres de
   --  la normale, echo diffus faible ailleurs. La reponse reelle depend du
   --  materiau, des couches, de l'humidite, de la rugosite, de la polarisation
   --  et de l'incidence. Rayleigh est un critere de rugosite, pas un verdict
   --  mur peint = miroir. Ces constantes demandent une mesure sur le
   --  montage final.

   --  Echo du mur vu de face : la valeur unique de l'ancien modele.
   Specular_Echo : constant Amplitude := 2_500;

   --  Part diffuse en incidence normale : 20 dB sous le speculaire, soit
   --  un facteur 10 en amplitude. HYPOTHESE de modelisation, a recaler
   --  sur l'A121 reel en visant un mur sous des incidences connues. Face
   --  au seuil CFAR typique (~160), elle s'eteint vers 50 degres.
   Diffuse_Echo : constant Float := 250.0;

   --  Coin vertical ideal entre deux murs (diedre) : le double rebond peut
   --  renvoyer l'onde vers sa source dans le plan horizontal. Son niveau
   --  depend de la geometrie et des materiaux ; ce n'est pas toujours le
   --  point le plus brillant d'une piece reelle.
   Corner_Echo : constant Amplitude := 3_500;

   --  Azimut du coin du premier quadrant ; les trois autres s'en
   --  deduisent par symetrie (180 - a, 180 + a, 360 - a).
   Corner_Az : constant Float :=
     Arctan (Room_Half_Y, Room_Half_X) * 180.0 / Pi;

   --  Distance horizontale du radar aux quatre coins.
   Corner_Distance : constant Float :=
     Sqrt (Room_Half_X ** 2 + Room_Half_Y ** 2);

   --  Echo d'un mur selon l'angle d'incidence (degres). Speculaire si la
   --  normale du mur est dans le faisceau (meme tolerance que pour les
   --  objets), diffus et decroissant sinon. Le Max protege la conversion
   --  d'un cosinus qu'un arrondi rendrait a peine negatif pres de 90.
   function Wall_Echo (Incidence : Float) return Amplitude is
     (if Incidence < Beam_Width then Specular_Echo
      else Amplitude
             (Float'Max (0.0, Diffuse_Echo * Cos (Incidence * Pi / 180.0))));

   --  Le faisceau vise-t-il un coin ? Un diedre VERTICAL ne renvoie
   --  l'onde vers sa source que dans le plan horizontal : hors de la
   --  tolerance d'elevation, le double rebond garde sa pente et manque le
   --  radar (il faudrait un sol ou un plafond, donc un triedre).
   function Sees_Corner (Az, El : Float) return Boolean is
     (abs El < El_Width
      and then (Angle_Diff (Az, Corner_Az) < Beam_Width
                or else Angle_Diff (Az, 180.0 - Corner_Az) < Beam_Width
                or else Angle_Diff (Az, 180.0 + Corner_Az) < Beam_Width
                or else Angle_Diff (Az, 360.0 - Corner_Az) < Beam_Width));

   function Make
     (Sweeps   : Positive;
      See_Room : Boolean := False) return Simulated_Source
   is
      S : Simulated_Source :=
        (Az_Step      => 0,
         El_Step      => 0,
         Current_Turn => 0,
         Max_Turns    => Sweeps,
         Az_Steps     => Default_Azimuth_Steps,
         El_Steps     => Default_Elevation_Steps,
         See_Room     => See_Room,
         Echoes       => (others => (others => 0)),
         Ghosting     => (others => False),
         Clock        => 0,
         Ms_Per_Step  => Default_Ms_Per_Step,
         Scene        => Initial_World);
   begin
      Roll_Echoes (S);   --  amplitudes du premier tour
      return S;
   end Make;

   --------------
   -- Per_Turn --
   --------------

   overriding
   function Per_Turn (Self : Simulated_Source) return Positive is
   begin
      return Self.Az_Steps * Self.El_Steps;
   end Per_Turn;

   -----------------
   -- Per_Azimuth --
   -----------------

   overriding
   function Per_Azimuth (Self : Simulated_Source) return Positive is
   begin
      return Self.El_Steps;
   end Per_Azimuth;

   --------------------
   -- Make_Room_Scan --
   --------------------

   function Make_Room_Scan
     (Az_Steps : Grid_Steps := 180;
      El_Steps : Grid_Steps := 24) return Simulated_Source is
   begin
      return (Az_Step      => 0,
              El_Step      => 0,
              Current_Turn => 0,
              Max_Turns    => 1,              --  un seul tour, meticuleux
              Az_Steps     => Az_Steps,
              El_Steps     => El_Steps,
              See_Room     => True,           --  percoit les murs
              Echoes       => (others => (others => 0)),
              Ghosting     => (others => False),
              Clock        => 0,
              Ms_Per_Step  => Default_Ms_Per_Step,
              Scene        => Empty_World);   --  pas d'objet mobile
   end Make_Room_Scan;

   ----------
   -- Next --
   ----------

   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean)
   is
   begin
      if Self.Current_Turn >= Self.Max_Turns then
         Available := False;
         Result    := (Azimuth => 0.0, Elevation => 0.0,
                       Stamp => Self.Clock, Data => (others => 0));
         return;
      end if;

      declare
         --  Direction visee : azimut et elevation.
         Az : constant Float :=
           Float (Self.Az_Step) * 360.0 / Float (Self.Az_Steps);
         El : constant Float :=
           El_Min + Float (Self.El_Step)
                    * (El_Max - El_Min) / Float (Self.El_Steps - 1);
         S : Sweep;
      begin
         --  Bruit de fond dans chaque case (jamais de silence en reel).
         for J in Bin_Index loop
            S (J) := Amplitude (Random (Gen) * Noise_Level);
         end loop;

         --  Les murs de la piece (mode cartographie) : a la distance du
         --  premier mur touche, un echo qui depend de l'angle sous lequel
         --  on le regarde, plus un echo fort si le faisceau vise un coin.
         --  'Max et non une affectation : un echo diffus plus faible que
         --  le bruit ne doit pas creuser un trou de silence dans la case.
         if Self.See_Room then
            declare
               W : constant Bin_Index :=
                 Distance_To_Bin (Wall_Distance (Az, El));
            begin
               S (W) := Amplitude'Max
                          (S (W), Wall_Echo (Wall_Incidence (Az, El)));
            end;

            if Sees_Corner (Az, El) then
               declare
                  C : constant Bin_Index :=
                    Distance_To_Bin (Corner_Distance / Cos (El * Pi / 180.0));
               begin
                  S (C) := Amplitude'Max (S (C), Corner_Echo);
               end;
            end if;
         end if;

         --  Les objets : chaque reflecteur visible ce tour-ci (Echoes
         --  tire au sort par Roll_Echoes) produit son propre echo, a sa
         --  propre position. Une cible reelle est etendue : son centre
         --  percu "se promene" selon le reflecteur dominant du moment.
         for I in 1 .. Self.Scene.Count loop
            declare
               O : constant Object := Self.Scene.Objects (I);
            begin
               for K in 1 .. Scatter_Count loop
                  if Self.Echoes (I, K) > 0 then
                     declare
                        P : constant Point_3D :=
                          (O.X + Offsets (K).X,
                           O.Y + Offsets (K).Y,
                           O.Z + Offsets (K).Z);
                        R : constant Polar := To_Polar (P);
                        B : Bin_Index;
                     begin
                        --  Le reflecteur doit etre dans le faisceau en
                        --  azimut et en elevation. L'azimut se compare
                        --  modulo 360 (Angle_Diff) : un objet a 359
                        --  degres est bien dans le faisceau vise a 0.
                        if Angle_Diff (R.Azimuth, Az) < Beam_Width
                          and then abs (R.Elevation - El) < El_Width
                        then
                           B := Distance_To_Bin (R.Distance);
                           --  'Max : un echo fort n'est pas efface par
                           --  un faible tombant dans la meme case.
                           S (B) := Amplitude'Max (S (B), Self.Echoes (I, K));
                        end if;
                     end;
                  end if;
               end loop;

               --  Fantome multitrajet : le signal rebondit sur le mur
               --  puis sur la cible ; l'echo parait venir de derriere
               --  le mur (distance mur + (mur - cible)), plus faible.
               if Self.See_Room and then Self.Ghosting (I) then
                  declare
                     R : constant Polar := To_Polar ((O.X, O.Y, O.Z));
                     G : Float;
                  begin
                     if Angle_Diff (R.Azimuth, Az) < Beam_Width
                       and then abs (R.Elevation - El) < El_Width
                     then
                        G := 2.0 * Wall_Distance (Az, El) - R.Distance;
                        if G > 0.0 and then G < Float (Max_Range_Mm) then
                           declare
                              B : constant Bin_Index := Distance_To_Bin (G);
                           begin
                              S (B) := Amplitude'Max (S (B), Ghost_Echo);
                           end;
                        end if;
                     end if;
                  end;
               end if;
            end;
         end loop;

         Result    := (Azimuth => Az, Elevation => El,
                       Stamp   => Self.Clock, Data => S);
         Available := True;
      end;

      --  L horloge virtuelle avance d une mesure : sur le vrai
      --  materiel, c est le temps de pointage plus l integration.
      Self.Clock := Self.Clock + Self.Ms_Per_Step;

      --  Avancer dans la grille : d'abord l'elevation, puis l'azimut.
      Self.El_Step := Self.El_Step + 1;
      if Self.El_Step >= Self.El_Steps then
         Self.El_Step := 0;
         Self.Az_Step := Self.Az_Step + 1;

         --  Fin du tour complet (tous azimuts x toutes elevations) :
         --  le monde avance et les niveaux d'echo sont retires au sort.
         if Self.Az_Step >= Self.Az_Steps then
            Self.Az_Step      := 0;
            Self.Current_Turn := Self.Current_Turn + 1;
            Step (Self.Scene);
            Roll_Echoes (Self);
         end if;
      end if;
   end Next;

   overriding
   function Has_More (Self : Simulated_Source) return Boolean is
   begin
      return Self.Current_Turn < Self.Max_Turns;
   end Has_More;

begin
   --  Graine fixe : memes tirages a chaque execution (reproductible).
   Ada.Numerics.Float_Random.Reset (Gen, 42);
end Radar_Sim_Source;
