--  Libelles en UTF-8 pour GTK : voir la note de console_ui.adb.
pragma Wide_Character_Encoding (BRACKETS);

package body Radar_Modes is

   use type Radar_Ld2450_Log.Capture_Origin;

   --  Le LD2450 ne voit que ce qui bouge : aucun mur, donc pas de carte. Et
   --  le SAR demande la phase, que seule la simulation de profils fournit.
   function Allowed (S : Source_Kind; A : Activity_Kind) return Boolean is
     (A = Watch or else S = Sim_Profiles);

   function Reason (S : Source_Kind; A : Activity_Kind) return String is
     (if Allowed (S, A) then ""
      elsif A = Mapping
      then "Ce capteur ne voit que ce qui bouge : pas de murs, pas de carte."
      else "Il faut la phase du signal : simulation 3D seulement.");

   function Source_Label (S : Source_Kind) return String is
     (case S is
         when Sensor_Serial => "Capteur LD2450 (port série)",
         when Capture_File  => "Fichier de capture",
         when Sim_Ld2450    => "Simulation LD2450",
         when Sim_Profiles  => "Simulation 3D (profils)");

   function Activity_Label (A : Activity_Kind) return String is
     (case A is
         when Watch        => "Veille",
         when Mapping      => "Cartographie",
         when Sar_Analysis => "Analyse SAR");

   function Is_Simulated
     (S      : Source_Kind;
      Origin : Radar_Ld2450_Log.Capture_Origin) return Boolean is
     (S in Sim_Ld2450 | Sim_Profiles
      or else (S = Capture_File
               and then Origin = Radar_Ld2450_Log.Origin_Emulated));

   function Source_Text
     (S      : Source_Kind;
      Origin : Radar_Ld2450_Log.Capture_Origin) return String is
     (case S is
         when Sensor_Serial => "Capteur (non validé)",
         when Sim_Ld2450    => "LD2450 SIMULÉ",
         when Sim_Profiles  => "Profils SIMULÉS",
         when Capture_File  =>
           (case Origin is
               when Radar_Ld2450_Log.Origin_Emulated => "Fichier - SIMULÉ",
               when Radar_Ld2450_Log.Origin_Hardware => "Fichier - matériel",
               when Radar_Ld2450_Log.Origin_Unknown  =>
                  "Fichier - provenance non prouvée"));

end Radar_Modes;
