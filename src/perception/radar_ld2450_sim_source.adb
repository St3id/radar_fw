with Ada.Unchecked_Deallocation;
with Radar_Ld2450;
with Radar_Ld2450_Replay;

package body Radar_Ld2450_Sim_Source is

   use type Radar_Source.Time_Ms;

   procedure Free is new Ada.Unchecked_Deallocation
     (Radar_Ld2450_Log.Writer, Writer_Access);

   function Make (Seed : Natural := 42) return Live_Source is
     (Radar_Planar_Source.Planar_Source with
      Sim    => Radar_Ld2450_Sim.Make (Seed => Seed),
      Parser => <>,
      Filter => <>,
      Last   => 0,
      Primed => False,
      Log    => null,
      Log_Base => 0);

   overriding
   procedure Next_Report
     (Self      : in out Live_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean)
   is
      F    : Radar_Ld2450_Sim.Emitted_Frame;
      Sent : Boolean;
   begin
      Result    := (others => <>);
      Available := False;
      Radar_Ld2450_Sim.Next_Frame (Self.Sim, F, Sent);

      if Self.Log /= null then
         --  L'heure du fichier part du debut de l'enregistrement : sinon le
         --  rejeu attendrait d'autant et y verrait un silence du module.
         if Sent then
            Radar_Ld2450_Log.Append
              (Self.Log.all, F.Stamp - Self.Log_Base, F.Bytes);
         else
            --  Un bloc vide : la liaison etait ouverte et rien n'arrivait.
            Radar_Ld2450_Log.Append
              (Self.Log.all, F.Stamp - Self.Log_Base,
               Radar_Ld2450.Byte_Array'(1 .. 0 => 0));
         end if;
      end if;

      if not Sent then
         return;
      end if;

      for B of F.Bytes loop
         declare
            Frame : Radar_Ld2450_Stream.Decoded_Frame;
            Ready : Boolean;
         begin
            Radar_Ld2450_Stream.Feed (Self.Parser, B, Frame, Ready);
            if Ready then
               declare
                  Raw     : Radar_Ld2450.Raw_Report;
                  Elapsed : constant Natural :=
                    (if Self.Primed and then F.Stamp > Self.Last
                     then Natural (F.Stamp - Self.Last) else 0);
               begin
                  Radar_Ld2450_Plausibility.Validate
                    (Self.Filter, Frame.Targets, Elapsed, Raw);
                  Result := Radar_Ld2450_Replay.To_Report (Raw, F.Stamp, 1);
                  Self.Last   := F.Stamp;
                  Self.Primed := True;
                  Available   := True;
               end;
            end if;
         end;
      end loop;
   end Next_Report;

   procedure Start_Recording
     (Self : in out Live_Source;
      Path : String;
      Ok   : out Boolean) is
   begin
      Stop_Recording (Self);
      Self.Log := new Radar_Ld2450_Log.Writer;
      Radar_Ld2450_Log.Create
        (Self.Log.all, Path, Radar_Ld2450_Log.Origin_Emulated, Ok);
      if not Ok then
         Free (Self.Log);
      end if;
      Self.Log_Base := Self.Last;
   end Start_Recording;

   procedure Stop_Recording (Self : in out Live_Source) is
   begin
      if Self.Log /= null then
         Radar_Ld2450_Log.Close (Self.Log.all);
         Free (Self.Log);
      end if;
   end Stop_Recording;

   function Is_Recording (Self : Live_Source) return Boolean is
     (Self.Log /= null);

   function Stream (Self : Live_Source) return Radar_Ld2450_Stream.Parser is
     (Self.Parser);

   function Checks
     (Self : Live_Source) return Radar_Ld2450_Plausibility.Validator is
     (Self.Filter);

end Radar_Ld2450_Sim_Source;
