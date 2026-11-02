with Radar_Ld2450;

package body Radar_Ld2450_Replay is

   use Radar_Ld2450;
   use type Radar_Ld2450_Log.Read_Status;
   use type Radar_Source.Time_Ms;

   --  Passe d'un rapport du module, dans ses unites, a un rapport du
   --  contrat 2D : la vitesse passe des cm/s du module aux mm/s du projet.
   function To_Report
     (Raw    : Raw_Report;
      Stamp  : Radar_Source.Time_Ms;
      Sensor : Positive) return Radar_Planar_Source.Planar_Report
   is
      R : Radar_Planar_Source.Planar_Report;
   begin
      R.Count  := Raw.Count;
      R.Stamp  := Stamp;
      R.Sensor := Sensor;
      for I in 1 .. Raw.Count loop
         R.Items (I) :=
           (X_Mm       => Float (Raw.Targets (I).X_Mm),
            Y_Mm       => Float (Raw.Targets (I).Y_Mm),
            Speed_Mm_S => Float (Raw.Targets (I).Speed_Cm_S) * 10.0);
      end loop;
      return R;
   end To_Report;

   --  Le temps depuis la trame precedente, tel que l'attend Validate : 0 si
   --  les horodatages reculent ou si c'est la premiere trame. Un fichier
   --  edite a la main ne doit pas pouvoir lever une exception ici.
   function Elapsed
     (Self : Replay_Source; Now : Radar_Source.Time_Ms) return Natural
   is
     (if Self.Has_Frame and then Now > Self.Last_Frame
      then Natural (Now - Self.Last_Frame)
      else 0);

   ----------
   -- Open --
   ----------

   procedure Open
     (Self   : in out Replay_Source;
      Path   : String;
      Sensor : Positive := 1;
      Ok     : out Boolean)
   is
      First_Block : Positive;
      Fresh       : Replay_Source;
   begin
      Self := Fresh;
      Self.Sensor := Sensor;
      Radar_Ld2450_Log.Load (Path, Self.Content, First_Block, Ok);
      Self.Next_Block := First_Block;
      Self.Finished   := not Ok;
      if not Ok then
         Self.Stopped := Radar_Ld2450_Log.Malformed;
      end if;
   end Open;

   -----------------
   -- Next_Report --
   -----------------

   overriding
   procedure Next_Report
     (Self      : in out Replay_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean)
   is
   begin
      Result    := (others => <>);
      Available := False;

      if Self.Finished then
         return;
      end if;

      loop
         --  D'abord les octets du bloc courant : un bloc peut contenir
         --  plusieurs trames, ou la fin d'une trame et le debut de la
         --  suivante.
         while Self.Chunk_Next <= Self.Chunk_Last loop
            declare
               Frame : Radar_Ld2450_Stream.Decoded_Frame;
               Ready : Boolean;
            begin
               Radar_Ld2450_Stream.Feed
                 (Self.Parser, Self.Content.Element (Self.Chunk_Next),
                  Frame, Ready);
               Self.Chunk_Next := Self.Chunk_Next + 1;
               if Ready then
                  declare
                     Raw : Raw_Report;
                  begin
                     Radar_Ld2450_Plausibility.Validate
                       (Self.Filter, Frame.Targets,
                        Elapsed (Self, Self.Chunk_Stamp), Raw);
                     Result := To_Report (Raw, Self.Chunk_Stamp, Self.Sensor);
                     Self.Last_Frame := Self.Chunk_Stamp;
                     Self.Has_Frame  := True;
                     Available := True;
                     return;
                  end;
               end if;
            end;
         end loop;

         --  Bloc suivant. Le silence se signale AVANT de traiter le bloc qui
         --  y met fin : le consommateur le voit a sa place dans le temps.
         declare
            Stamp  : Radar_Source.Time_Ms;
            First  : Positive;
            Length : Natural;
            Status : Radar_Ld2450_Log.Read_Status;
         begin
            Radar_Ld2450_Log.Next_Chunk
              (Self.Content, Self.Next_Block, Stamp, First, Length, Status);

            if Status /= Radar_Ld2450_Log.Chunk_Ok then
               Self.Finished := True;
               Self.Stopped  := Status;
               return;
            end if;

            Self.Chunk_Next  := First;
            Self.Chunk_Last  := First + Length - 1;
            Self.Chunk_Stamp := Stamp;

            declare
               Gap : constant Boolean :=
                 Stamp > Self.Last_Activity
                 and then Stamp - Self.Last_Activity > Silence_Gap_Ms;
               Fresh_Silence : constant Boolean :=
                 Gap and then not Self.In_Silence;
            begin
               if Length > 0 then
                  Self.Last_Activity := Stamp;
                  Self.In_Silence    := False;
               elsif Fresh_Silence then
                  Self.In_Silence := True;
               end if;

               if Fresh_Silence then
                  Self.Silence_Count := Self.Silence_Count + 1;
                  return;
               end if;
            end;
         end;
      end loop;
   end Next_Report;

   --------------
   -- Has_More --
   --------------

   overriding
   function Has_More (Self : Replay_Source) return Boolean is
     (not Self.Finished);

   ------------
   -- Stream --
   ------------

   function Stream (Self : Replay_Source) return Radar_Ld2450_Stream.Parser is
     (Self.Parser);

   ------------
   -- Checks --
   ------------

   function Checks
     (Self : Replay_Source) return Radar_Ld2450_Plausibility.Validator
   is
     (Self.Filter);

   --------------
   -- Silences --
   --------------

   function Silences (Self : Replay_Source) return Natural is
     (Self.Silence_Count);

   -----------------
   -- Stop_Reason --
   -----------------

   function Stop_Reason
     (Self : Replay_Source) return Radar_Ld2450_Log.Read_Status
   is
     (Self.Stopped);

end Radar_Ld2450_Replay;
