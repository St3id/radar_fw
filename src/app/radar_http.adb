with Ada.Streams;  use Ada.Streams;

--  Corps de Radar_Http. Seule la premiere ligne de la requete est
--  analysee : ce serveur ne repond qu'a des GET sur des chemins connus,
--  et tout le reste est ignore volontairement.

package body Radar_Http is

   CRLF : constant String := ASCII.CR & ASCII.LF;

   -----------
   -- Start --
   -----------

   procedure Start (S : in out Server; Port : Natural) is
   begin
      Create_Socket (S.Sock);
      Set_Socket_Option (S.Sock, Socket_Level, (Reuse_Address, True));
      Bind_Socket (S.Sock, (Family => Family_Inet,
                            Addr   => Inet_Addr ("127.0.0.1"),
                            Port   => Port_Type (Port)));
      Listen_Socket (S.Sock);
      Create_Selector (S.Sel);
   end Start;

   --  Envoi complet d'une chaine (Send_Socket peut etre partiel).
   procedure Send_Str (Sock : Socket_Type; Msg : String) is
      Data  : Stream_Element_Array (1 .. Stream_Element_Offset (Msg'Length));
      First : Stream_Element_Offset := Data'First;
      Last  : Stream_Element_Offset;
   begin
      for I in Msg'Range loop
         Data (Stream_Element_Offset (I - Msg'First + 1)) :=
           Stream_Element (Character'Pos (Msg (I)));
      end loop;
      while First <= Data'Last loop
         Send_Socket (Sock, Data (First .. Data'Last), Last);
         exit when Last >= Data'Last;
         First := Last + 1;
      end loop;
   end Send_Str;

   -------------------
   -- Send_Response --
   -------------------

   procedure Send_Response
     (Sock    : Socket_Type;
      Ctype   : String;
      Content : Unbounded_String;
      Code    : String := "200 OK")
   is
      B : constant String := To_String (Content);
   begin
      Send_Str (Sock,
        "HTTP/1.1 " & Code & CRLF
        & "Content-Type: " & Ctype & "; charset=utf-8" & CRLF
        & "Content-Length:" & Natural'Image (B'Length) & CRLF
        & "Cache-Control: no-store" & CRLF
        & "Connection: close" & CRLF & CRLF);
      Send_Str (Sock, B);
   end Send_Response;

   --  Lit la requete, extrait le chemin, delegue au handler, ferme.
   procedure Handle
     (Sock    : Socket_Type;
      Handler : not null access procedure
                  (Path : String; Sock : Socket_Type))
   is
      Buf  : Stream_Element_Array (1 .. 2048);
      Last : Stream_Element_Offset;
      Req  : String (1 .. 2048) := (others => ' ');
   begin
      Receive_Socket (Sock, Buf, Last);
      for I in Buf'First .. Last loop
         Req (Natural (I)) := Character'Val (Buf (I));
      end loop;

      --  Ligne de requete : "GET /chemin HTTP/1.1".
      declare
         Sp1 : Natural := 0;
         Sp2 : Natural := 0;
      begin
         for I in Req'Range loop
            if Req (I) = ' ' then
               if Sp1 = 0 then
                  Sp1 := I;
               else
                  Sp2 := I;
                  exit;
               end if;
            end if;
         end loop;

         if Sp1 = 0 or else Sp2 = 0 then
            Send_Response (Sock, "text/plain",
                           To_Unbounded_String ("bad request"),
                           "400 Bad Request");
         else
            Handler (Req (Sp1 + 1 .. Sp2 - 1), Sock);
         end if;
      end;

      Close_Socket (Sock);
   exception
      when Socket_Error =>
         --  Client parti en cours de route : on ferme et on continue.
         begin
            Close_Socket (Sock);
         exception
            when Socket_Error => null;
         end;
   end Handle;

   -----------------
   -- Serve_Until --
   -----------------

   procedure Serve_Until
     (S        : Server;
      Deadline : Time;
      Handler  : not null access procedure
                   (Path : String; Sock : Socket_Type))
   is
      R_Set  : Socket_Set_Type;
      W_Set  : Socket_Set_Type;
      Status : Selector_Status;
   begin
      loop
         declare
            Remaining : constant Duration := To_Duration (Deadline - Clock);
         begin
            exit when Remaining <= 0.0;
            Empty (R_Set);
            Set (R_Set, S.Sock);
            Empty (W_Set);
            Check_Selector (S.Sel, R_Set, W_Set, Status, Remaining);
            exit when Status /= Completed;

            declare
               Conn : Socket_Type;
               Addr : Sock_Addr_Type;
            begin
               Accept_Socket (S.Sock, Conn, Addr);
               Handle (Conn, Handler);
            end;
         end;
      end loop;
   end Serve_Until;

end Radar_Http;
