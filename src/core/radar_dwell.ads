--  Radar_Dwell : repartir le temps d'une passe de tourelle entre les cibles.
--
--  La duree d'une passe reste fixe : ralentir sur une cible ne retarde pas la
--  carte. Hors des cibles, la tete tourne a sa vitesse maximale, et le temps
--  ainsi gagne est partage a parts egales entre les cibles. Le capteur mesure
--  a cadence constante : plus de temps dans un secteur, c'est plus de
--  balayages.
--
--  Ce gain est du signal, pas de la finesse : la resolution d'une synthese
--  d'ouverture vient de la longueur de l'arc. Une cible qui marche bouge trop
--  pendant le ralentissement pour rester coherente : elle gagne des mesures,
--  pas de nettete.
--
--  Un plan se compte en microsecondes entieres, sans flottant, et se recalcule
--  a chaque passe. La passe se decoupe en secteurs d'angle ; ce paquet ignore
--  d'ou viennent les cibles et comment le moteur tient ce plan.

package Radar_Dwell
  with SPARK_Mode => On
is

   --  HYPOTHESE - une passe couvre 360 degres plus les ~60 du faisceau.
   Sector_Degrees : constant := 5;
   Sector_Count   : constant := 84;
   Pass_Degrees   : constant := Sector_Degrees * Sector_Count;

   --  HYPOTHESE - 0,9 tr/s : au-dela, 921 600 bauds ne transportent plus les
   --  180 balayages par tour d'une rangee SAR. Arrondi vers le haut, pour ne
   --  jamais depasser ce plafond.
   Min_Sector_Us : constant := 15_433;

   --  HYPOTHESE - vitesse sans cible : ~0,44 tr/s, soit ~2,65 s par passe.
   Nominal_Sector_Us : constant := 31_550;
   Pass_Us           : constant := Sector_Count * Nominal_Sector_Us;

   --  Temps garde pour les rampes : le moteur ne change pas de vitesse d'un
   --  coup, donc il arrive en retard sur le plan. La valeur vient de la mesure
   --  de Radar_Turret_Sim, sous une acceleration elle aussi supposee.
   Ramp_Reserve_Us : constant := 240_000;

   --  Le temps a redistribuer, une fois tout tourne a la vitesse maximale.
   Bonus_Us : constant :=
     Pass_Us - Ramp_Reserve_Us - Sector_Count * Min_Sector_Us;

   --  HYPOTHESE - une cible reste dans le faisceau sur ~60 degres.
   Window_Sectors : constant := 12;

   Max_Cues : constant := 8;

   subtype Sector is Positive range 1 .. Sector_Count;
   subtype Cue_Count is Natural range 0 .. Max_Cues;
   subtype Sector_Us is Positive range Min_Sector_Us .. Pass_Us;

   type Sector_Times is array (Sector) of Sector_Us;
   type Cue_List is array (1 .. Max_Cues) of Sector;

   function Sector_Of (Pass_Degree : Natural) return Sector is
     (Pass_Degree / Sector_Degrees + 1)
     with Pre => Pass_Degree < Pass_Degrees;

   --  La fenetre d'une cible, coupee aux bords de la passe : une cible du bord
   --  garde sa part de temps entiere, sur moins de secteurs.
   function Window_First (Cue : Sector) return Sector is
     (Positive'Max (Sector'First, Cue - Window_Sectors / 2));

   function Window_Last (Cue : Sector) return Sector is
     (Positive'Min (Sector'Last, Cue + Window_Sectors / 2 - 1));

   --  La part de chaque cible. Le reste de la division, moins d'une
   --  microseconde par cible, n'est donne a personne : l'egalite prime.
   function Share (Count : Cue_Count) return Natural is
     (Bonus_Us / Count)
     with Pre => Count > 0;

   --  Somme des premiers secteurs, pour enoncer les contrats ci-dessous.
   function Sum_To (Times : Sector_Times; Last : Natural) return Natural is
     (if Last = 0 then 0 else Sum_To (Times, Last - 1) + Times (Last))
     with
       Ghost,
       Pre                => Last <= Sector_Count,
       Post               => Sum_To'Result <= Last * Pass_Us,
       Subprogram_Variant => (Decreases => Last);

   --  Donne Amount microsecondes a la fenetre d'une cible, sans rien perdre ni
   --  toucher au reste. Des fenetres qui se recouvrent additionnent donc leurs
   --  parts, sans etape de fusion : chaque cible garde exactement son temps.
   procedure Add_Share
     (Times  : in out Sector_Times;
      Cue    : Sector;
      Amount : Natural)
     with
       Pre  =>
         Amount <= Bonus_Us
         and then (for all S in Sector => Times (S) + Amount <= Pass_Us),
       Post =>
         Sum_To (Times, Sector_Count)
           = Sum_To (Times'Old, Sector_Count) + Amount
         and then
         (for all S in Sector =>
            (if S in Window_First (Cue) .. Window_Last (Cue)
             then Times (S) in Times'Old (S) .. Times'Old (S) + Amount
             else Times (S) = Times'Old (S)));

   --  Le plan d'une passe. Sans cible, la vitesse est uniforme et la passe
   --  dure exactement Pass_Us. Avec des cibles, chacune recoit Share (Count),
   --  et la somme laisse la reserve de rampe intacte.
   --
   --  Le plafond de vitesse tient au type : aucun secteur sous Min_Sector_Us.
   procedure Build
     (Cues  : Cue_List;
      Count : Cue_Count;
      Plan  : out Sector_Times)
     with
       Post =>
         (if Count = 0 then
            (for all S in Sector => Plan (S) = Nominal_Sector_Us)
            and then Sum_To (Plan, Sector_Count) = Pass_Us
          else
            Sum_To (Plan, Sector_Count)
              = Sector_Count * Min_Sector_Us + Count * Share (Count)
            and then Sum_To (Plan, Sector_Count) <= Pass_Us - Ramp_Reserve_Us
            and then
            Sum_To (Plan, Sector_Count)
              > Pass_Us - Ramp_Reserve_Us - Count);

end Radar_Dwell;
