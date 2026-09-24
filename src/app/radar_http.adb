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

   ---------------
   -- Subscribe --
   ---------------

   --  Abonne une connexion au flux /events : en-tetes SSE, puis la
   --  connexion reste ouverte. Kept = False si tous les emplacements sont
   --  pris : reponse 503, et c'est l'appelant qui ferme.
   procedure Subscribe
     (S    : in out Server;
      Sock : Socket_Type;
      Kept : out Boolean)
   is
      --  Ecriture non bloquante : une page qui ne lit plus (onglet gele)
      --  remplirait le tampon d'emission, et Send_Socket bloquerait alors
      --  tout le serveur mono-thread - calcul radar compris. En non
      --  bloquant, Broadcast recoit une erreur a la place et retire
      --  l'abonne ; le navigateur se reconnecte tout seul.
      Non_Blocking : Request_Type :=
        (Name => Non_Blocking_IO, Enabled => True);
   begin
      Kept := False;
      for I in S.Subs'Range loop
         if S.Subs (I) = No_Socket then
            --  Transfer-Encoding: chunked, et non un corps sans longueur :
            --  sans decoupage, Chromium ouvrait bien le flux mais ne
            --  livrait aucun message a la page (mesure sur Edge, 2026-09).
            --  Chaque message part donc dans son propre morceau HTTP.
            Send_Str (Sock,
              "HTTP/1.1 200 OK" & CRLF
              & "Content-Type: text/event-stream; charset=utf-8" & CRLF
              & "Cache-Control: no-store" & CRLF
              & "Transfer-Encoding: chunked" & CRLF
              & "Connection: keep-alive" & CRLF & CRLF);
            Control_Socket (Sock, Non_Blocking);
            S.Subs (I) := Sock;
            Kept := True;
            return;
         end if;
      end loop;

      Send_Response (Sock, "text/plain",
                     To_Unbounded_String ("trop d'abonnes"),
                     "503 Service Unavailable");
   end Subscribe;

   --  Longueur d'un morceau HTTP en hexadecimal, sans espace ni zero de
   --  tete ("1A3") : le format qu'impose Transfer-Encoding: chunked.
   --  8 chiffres suffisent a tout Natural (2**31 - 1 = 7FFFFFFF).
   function Hex_Length (N : Natural) return String is
      Hex_Digits : constant String := "0123456789ABCDEF";
      Buf        : String (1 .. 8);
      P          : Positive := Buf'Last + 1;
      V          : Natural := N;
   begin
      loop
         P := P - 1;
         Buf (P) := Hex_Digits (V mod 16 + 1);
         V := V / 16;
         exit when V = 0;
      end loop;
      return Buf (P .. Buf'Last);
   end Hex_Length;

   ---------------
   -- Broadcast --
   ---------------

   procedure Broadcast (S : in out Server; Data : String) is
      --  Format SSE : "data: <message>" puis une ligne vide.
      Msg : constant String := "data: " & Data & ASCII.LF & ASCII.LF;
   begin
      for I in S.Subs'Range loop
         if S.Subs (I) /= No_Socket then
            begin
               --  Un morceau HTTP : longueur en hexadecimal, CRLF, le
               --  message, CRLF.
               Send_Str (S.Subs (I),
                         Hex_Length (Msg'Length) & CRLF & Msg & CRLF);
            exception
               when Socket_Error =>
                  --  Page fermee, ou qui ne lit plus : emplacement libere.
                  begin
                     Close_Socket (S.Subs (I));
                  exception
                     when Socket_Error => null;
                  end;
                  S.Subs (I) := No_Socket;
            end;
         end if;
      end loop;
   end Broadcast;

   --  Lit la requete, extrait le chemin, delegue au handler, ferme - sauf
   --  pour un abonne /events, dont la connexion doit rester ouverte.
   procedure Handle
     (S       : in out Server;
      Sock    : Socket_Type;
      Handler : not null access procedure
                  (Path : String; Sock : Socket_Type))
   is
      Buf  : Stream_Element_Array (1 .. 2048);
      Last : Stream_Element_Offset;
      Req  : String (1 .. 2048) := (others => ' ');
      Keep : Boolean := False;
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
         elsif Req (Sp1 + 1 .. Sp2 - 1) = "/events" then
            Subscribe (S, Sock, Keep);
         else
            Handler (Req (Sp1 + 1 .. Sp2 - 1), Sock);
         end if;
      end;

      --  Un abonne garde sa connexion : c'est Broadcast qui ecrira dessus,
      --  et qui la fermera quand la page partira.
      if not Keep then
         Close_Socket (Sock);
      end if;
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
     (S        : in out Server;
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
               --  Delai de lecture de 200 ms : un navigateur ouvre souvent
               --  une connexion d'avance (preconnexion) sans rien y
               --  envoyer. Sans delai, Receive_Socket l'attendait sans fin
               --  et figeait tout le serveur mono-thread, calcul radar
               --  compris. Invisible tant que la page sondait toutes les
               --  250 ms (la requete suivante passait par elle) ; bloquant
               --  des qu'elle a ecoute un flux /events (mesure).
               Set_Socket_Option
                 (Conn, Socket_Level, (Receive_Timeout, Timeout => 0.2));
               Handle (S, Conn, Handler);
            end;
         end;
      end loop;
   end Serve_Until;

end Radar_Http;
