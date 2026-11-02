with Radar_Sweep;  use Radar_Sweep;

--  Radar_Buffer : la boite aux lettres partagee entre la tache qui
--  produit les balayages et celle qui les consomme.
--
--  Le producteur y depose un balayage ; le consommateur se bloque sur
--  l'entry Get tant qu'il n'y a rien a lire, au lieu de venir sonder en
--  boucle. C'est le motif Ravenscar canonique : tache cyclique, objet
--  protege, tache sporadique.
--
--  Unite prouvee en SPARK, dans le contexte du profil Ravenscar impose
--  par radar_demo.gpr.

package Radar_Buffer
  with SPARK_Mode => On
is

   protected Mailbox is

      --  Depose un balayage dans la boite (appele par le producteur).
      --  Ecrase l'eventuel balayage precedent non lu : on veut toujours
      --  la donnee la plus fraiche (boite aux lettres, pas une file).
      --  Last = True pour le dernier balayage de la serie.
      procedure Put (S : Sweep; Last : Boolean);

      --  Recupere un balayage. entry a barriere : l'appelant est suspendu
      --  tant que la boite est vide ; le reveil est gere par le noyau,
      --  pas par du polling. Ravenscar exige une barriere simple (une
      --  seule variable booleenne) : c'est le cas.
      --
      --  Last dit au consommateur quand s'arreter. Il ne doit PAS compter
      --  ses lectures : Put ecrase une donnee non lue, si bien qu'un
      --  consommateur qui attendrait N balayages en recevrait peut-etre
      --  N - 1, et attendrait le dernier pour toujours. Le dernier
      --  balayage, lui, ne peut pas etre ecrase : rien ne vient apres.
      entry Get (S : out Sweep; Last : out Boolean);

      --  Balayages ecrases avant d'avoir ete lus (sature a Natural'Last) :
      --  une perte doit etre visible, pas silencieuse.
      function Overwritten return Natural;

   private
      Data     : Sweep := (others => 0);
      Has_Data : Boolean := False;
      Is_Last  : Boolean := False;
      Lost     : Natural := 0;
   end Mailbox;

end Radar_Buffer;
