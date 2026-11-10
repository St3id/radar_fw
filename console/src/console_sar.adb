with Ada.Text_IO;
with Radar_Run_Sar;

package body Console_Sar is

   protected State is
      procedure Set_Busy;
      procedure Finish (Bad : Boolean);
      function Is_Done return Boolean;
      function Is_Failed return Boolean;
   private
      Finished : Boolean := True;
      Error    : Boolean := False;
   end State;

   protected body State is
      procedure Set_Busy is
      begin
         Finished := False;
         Error    := False;
      end Set_Busy;

      procedure Finish (Bad : Boolean) is
      begin
         Finished := True;
         Error    := Bad;
      end Finish;

      function Is_Done return Boolean is (Finished);
      function Is_Failed return Boolean is (Error);
   end State;

   --  Grande pile : la retroprojection travaille sur des tableaux locaux.
   task Worker with Storage_Size => 64 * 1024 * 1024 is
      entry Run (Path : String);
   end Worker;

   task body Worker is
      use Ada.Text_IO;
      File : File_Type;
   begin
      loop
         select
            accept Run (Path : String) do
               Create (File, Out_File, Path);
            end Run;
         or
            terminate;
         end select;

         begin
            Set_Output (File);
            Radar_Run_Sar;
            Set_Output (Standard_Output);
            Close (File);
            State.Finish (Bad => False);
         exception
            when others =>
               Set_Output (Standard_Output);
               if Is_Open (File) then
                  Close (File);
               end if;
               State.Finish (Bad => True);
         end;
      end loop;
   end Worker;

   procedure Start (Output_Path : String) is
   begin
      State.Set_Busy;
      Worker.Run (Output_Path);
   end Start;

   function Done return Boolean is (State.Is_Done);
   function Failed return Boolean is (State.Is_Failed);

end Console_Sar;
