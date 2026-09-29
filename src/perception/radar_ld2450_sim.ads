with Radar_Ld2450;  use Radar_Ld2450;
with Radar_Source;  use Radar_Source;
with Radar_World;   use Radar_World;

--  Radar_Ld2450_Sim : un LD2450 simule, vu depuis sa liaison serie.
--
--  Il remplace le PORT SERIE, pas le decodeur : dix fois par seconde, il
--  produit les 30 octets qu'un vrai module enverrait pour la scene
--  simulee (Radar_World), avec les imperfections du capteur et les
--  defauts de liaison de l'analyse CEM (ARCHITECTURE.md, section 2.5,
--  point 5). Le parseur lira ces octets comme ceux d'un vrai port, puis
--  livrera des rapports par Radar_Planar_Source.
--
--  Chaque trame vient avec ce que le module a VOULU envoyer (Intended) :
--  les tests du parseur compareront ce qu'il relit a cette verite.
--
--  Repere du capteur : pose a l'origine, vise +X ("devant" dans tout le
--  projet), Y du capteur = distance vers l'avant, X du capteur positif
--  vers la droite (le -Y du monde). Ce cote du X positif est une
--  convention a verifier sur un module reel.
--
--  Hors SPARK : trigonometrie et flottants, comme le reste de la
--  perception simulee.

package Radar_Ld2450_Sim is

   --  Cadence du module : 10 trames par seconde (manuel Hi-Link). Un pas
   --  du monde simule dure une periode.
   Period_Ms : constant := 100;

   --  Ce que le capteur voit, et avec quelle precision. Les valeurs par
   --  defaut sont des ordres de grandeur (fiche et releves d'utilisateurs),
   --  a remesurer sur un module reel.
   type Sensor_Model is record
      Half_Azimuth_Deg     : Float   := 60.0;   --  champ horizontal
      Half_Elevation_Deg   : Float   := 35.0;   --  champ vertical
      Range_Noise_Mm       : Float   := 50.0;   --  +/- sur la distance
      Angle_Noise_Axis_Deg : Float   := 2.0;    --  +/- sur l'angle, dans
      Angle_Noise_Edge_Deg : Float   := 20.0;   --  l'axe puis au bord
      Miss_Probability     : Float   := 0.05;   --  cible non rapportee
      Ghost_Probability    : Float   := 0.02;   --  fantome dans une trame
      Jitter_Ms            : Natural := 5;      --  +/- sur l'emission
      Resolution_Mm        : Word    := 360;    --  champ "resolution"
   end record;

   Default_Sensor : constant Sensor_Model := (others => <>);

   --  Un capteur sans bruit, sans perte, sans fantome ni gigue : pour les
   --  tests qui verifient la geometrie au millimetre.
   Ideal_Sensor : constant Sensor_Model :=
     (Range_Noise_Mm       => 0.0,
      Angle_Noise_Axis_Deg => 0.0,
      Angle_Noise_Edge_Deg => 0.0,
      Miss_Probability     => 0.0,
      Ghost_Probability    => 0.0,
      Jitter_Ms            => 0,
      others               => <>);

   --  Portee selon l'angle horizontal : 8 m dans l'axe, 6 m a 30 deg,
   --  5 m a 45 deg, 1 m a 60 deg, lineaire entre ces points et nulle
   --  au-dela. Releves d'utilisateurs : le manuel annonce ~6 m.
   function Max_Range_Mm (Azimuth_Deg : Float) return Float;

   --  Les defauts de liaison (analyse CEM), chacun tire a chaque trame.
   --  Tous nuls par defaut.
   type Fault_Model is record
      Corrupt_Probability : Float   := 0.0;     --  un bit d'un octet inverse
      Silence_Probability : Float   := 0.0;     --  le module se tait...
      Silence_Ms          : Time_Ms := 1_000;   --  ... aussi longtemps
      Restart_Probability : Float   := 0.0;     --  il redemarre, se tait le
      Restart_Ms          : Time_Ms := 500;     --  temps de demarrer, et
                                                --  retombe en mono-cible
   end record;

   No_Faults : constant Fault_Model := (others => <>);

   --  Une trame telle qu'elle passe sur la ligne.
   type Emitted_Frame is record
      Bytes          : Frame_Bytes := (others => 0);  --  defauts compris
      Stamp          : Time_Ms     := 0;              --  fin d'emission
      Intended       : Raw_Report;                    --  avant la ligne
      Corrupted_Byte : Natural     := 0;              --  0 = aucun
   end record;

   type Emulator is private;

   --  Seed rend tout reproductible : meme graine, memes octets.
   function Make
     (Scene  : World        := Initial_World;
      Sensor : Sensor_Model := Default_Sensor;
      Faults : Fault_Model  := No_Faults;
      Seed   : Natural      := 42) return Emulator;

   --  Avance d'une periode : le monde fait un pas, puis le module emet sa
   --  trame. Sent = False si le module se tait (silence ou redemarrage) ;
   --  F ne porte alors que l'instant.
   procedure Next_Frame
     (E    : in out Emulator;
      F    : out Emitted_Frame;
      Sent : out Boolean);

   --  Defauts declenches a la demande, pour les tests : le module se tait
   --  pendant Duration_Ms a partir de la prochaine periode, ou redemarre
   --  (silence de Restart_Ms, puis mono-cible).
   procedure Force_Silence (E : in out Emulator; Duration_Ms : Time_Ms);
   procedure Force_Restart (E : in out Emulator);

   --  La commande multi-cible de l'hote (ARCHITECTURE.md, section 2.6,
   --  piege 2). Apres un redemarrage, le module simule reste en mono-cible
   --  tant qu'elle n'a pas ete renvoyee : hypothese pessimiste, a verifier
   --  sur un module reel.
   procedure Request_Multi_Target (E : in out Emulator);

   function Multi_Target (E : Emulator) return Boolean;

private

   --  L'etat d'un generateur pseudo-aleatoire congruentiel (voir le corps).
   type Random_State is mod 2 ** 32;

   type Emulator is record
      Scene        : World;
      Sensor       : Sensor_Model;
      Faults       : Fault_Model;
      Rng          : Random_State := 42;
      Now          : Time_Ms      := 0;     --  instant nominal courant
      Silent_Until : Time_Ms      := 0;     --  muet tant que Now < ceci
      Multi        : Boolean      := True;  --  mode multi-cible actif
   end record;

   function Multi_Target (E : Emulator) return Boolean is (E.Multi);

end Radar_Ld2450_Sim;
