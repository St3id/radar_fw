package body Radar_Buffer is

   protected body Mailbox is

      ---------
      -- Put --
      ---------

      procedure Put (S : Sweep) is
      begin
         Data     := S;
         Has_Data := True;
      end Put;

      ---------
      -- Get --
      ---------

      procedure Get (S : out Sweep; Available : out Boolean) is
      begin
         S         := Data;
         Available := Has_Data;
         Has_Data  := False;   --  on a consomme la donnee
      end Get;

   end Mailbox;

end Radar_Buffer;