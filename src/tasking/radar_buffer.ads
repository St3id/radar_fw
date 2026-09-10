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
      procedure Put (S : Sweep);

      --  Recupere un balayage. entry a barriere : l'appelant est suspendu
      --  tant que la boite est vide ; le reveil est gere par le noyau,
      --  pas par du polling. Ravenscar exige une barriere simple (une
      --  seule variable booleenne) : c'est le cas.
      entry Get (S : out Sweep);

   private
      Data     : Sweep := (others => 0);
      Has_Data : Boolean := False;
   end Mailbox;

end Radar_Buffer;
