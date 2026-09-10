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

   type Server is limited record
      Sock : Socket_Type;
      Sel  : Selector_Type;
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
   --  de l'appelant (fermeture descendante).
   procedure Serve_Until
     (S        : Server;
      Deadline : Time;
      Handler  : not null access procedure
                   (Path : String; Sock : Socket_Type));

end Radar_Http;
