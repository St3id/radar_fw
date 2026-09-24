with Ada.Real_Time;          use Ada.Real_Time;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with GNAT.Sockets;           use GNAT.Sockets;

--  Radar_Http : un serveur HTTP minimal ecrit en Ada pur (GNAT.Sockets),
--  partage par les modes de surveillance et de cartographie progressive.
--
--  Volontairement mono-thread : l'appelant alterne un tour de traitement
--  radar et un appel a Serve_Until, qui attend passivement les connexions
--  jusqu'a une echeance. Aucune tache ici ; la concurrence Ravenscar vit
--  dans radar_demo et, a terme, sur la carte.

package Radar_Http is

   --  Abonnes au flux /events (Server-Sent Events) : une page ouverte
   --  recoit chaque nouvel etat des qu'il existe, au lieu de le
   --  redemander a intervalle fixe. Le sondage a 250 ms ajoutait jusqu'a
   --  un quart de seconde de retard et, face a un capteur a 10 Hz, aurait
   --  saute plus d'une mise a jour sur deux. Borne statique : au-dela, le
   --  nouvel abonne recoit 503 et le navigateur reessaie de lui-meme.
   Max_Subscribers : constant := 8;

   type Subscriber_Array is array (1 .. Max_Subscribers) of Socket_Type;

   type Server is limited record
      Sock : Socket_Type;
      Sel  : Selector_Type;
      Subs : Subscriber_Array := (others => No_Socket);
   end record;

   --  Cree le socket, l'attache a 127.0.0.1:Port (local seulement,
   --  volontaire : demo sans authentification) et le met en ecoute.
   procedure Start (S : in out Server; Port : Natural);

   --  Envoie une reponse HTTP complete sur une connexion.
   procedure Send_Response
     (Sock    : Socket_Type;
      Ctype   : String;
      Content : Unbounded_String;
      Code    : String := "200 OK");

   --  Sert les connexions entrantes jusqu'a l'echeance, puis rend la
   --  main. Handler recoit le chemin demande ("/", "/state.json"...)
   --  et doit repondre via Send_Response ; la connexion est fermee au
   --  retour. Parametre acces anonyme : accepte une procedure locale
   --  de l'appelant (fermeture descendante). Le chemin /events est traite
   --  ici et non par Handler : la connexion reste ouverte et rejoint les
   --  abonnes de Broadcast.
   procedure Serve_Until
     (S        : in out Server;
      Deadline : Time;
      Handler  : not null access procedure
                   (Path : String; Sock : Socket_Type));

   --  Pousse Data a toutes les pages abonnees a /events. Data tient sur
   --  une ligne (le format SSE termine un message par une ligne vide). Un
   --  abonne parti, ou qui ne lit plus, est ferme et retire.
   procedure Broadcast (S : in out Server; Data : String);

end Radar_Http;
