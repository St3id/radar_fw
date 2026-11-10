with Radar_Ld2450_Log;
with Radar_Ld2450_Plausibility;
with Radar_Ld2450_Sim;
with Radar_Ld2450_Stream;
with Radar_Planar_Source;
with Radar_Source;

--  Radar_Ld2450_Sim_Source : l'emulateur branche en direct, par le meme
--  parseur et le meme filtre que la lecture d'une capture.
--
--  Enregistrer ecrit les octets emis, avec Origin_Emulated dans l'en-tete :
--  le fichier se rejoue ensuite comme une capture et reste marque simule.

package Radar_Ld2450_Sim_Source is

   type Live_Source is new Radar_Planar_Source.Planar_Source with private;

   function Make (Seed : Natural := 42) return Live_Source;

   overriding
   procedure Next_Report
     (Self      : in out Live_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean);

   overriding
   function Has_More (Self : Live_Source) return Boolean is (True);

   procedure Start_Recording
     (Self : in out Live_Source;
      Path : String;
      Ok   : out Boolean);

   procedure Stop_Recording (Self : in out Live_Source);

   function Is_Recording (Self : Live_Source) return Boolean;

   function Stream (Self : Live_Source) return Radar_Ld2450_Stream.Parser;
   function Checks
     (Self : Live_Source) return Radar_Ld2450_Plausibility.Validator;

private

   type Writer_Access is access Radar_Ld2450_Log.Writer;

   type Live_Source is new Radar_Planar_Source.Planar_Source with record
      Sim    : Radar_Ld2450_Sim.Emulator;
      Parser : Radar_Ld2450_Stream.Parser;
      Filter : Radar_Ld2450_Plausibility.Validator;
      Last   : Radar_Source.Time_Ms := 0;
      Primed : Boolean := False;
      Log    : Writer_Access;
      Log_Base : Radar_Source.Time_Ms := 0;
   end record;

end Radar_Ld2450_Sim_Source;
