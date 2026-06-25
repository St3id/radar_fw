# radar_fw

Firmware de radar de scan 3D développé en **Ada/SPARK**, ciblant un microcontrôleur **STM32 (ARM Cortex-M)**.

Ce projet sert de démonstrateur de programmation embarquée haute-intégrité :
conception en Ada, concurrence déterministe (profil Ravenscar) et
**vérification formelle avec SPARK**.

## Objectif

Acquérir un balayage radar, en extraire les cibles (distance, angle), et
reconstruire une représentation 3D de la scène. Le radar est ici un support
technique pour démontrer une chaîne embarquée rigoureuse, applicable au
domaine défense / aéronautique.

## État d'avancement

- [x] Traitement d'un balayage : détection du pic et conversion en distance
- [x] Types bornés et contrats (conception « correct par construction »)
- [x] Vérification formelle SPARK : **8 checks prouvés, 0 non prouvé**
- [ ] Architecture concurrente Ravenscar (tâches + objets protégés)
- [ ] Driver capteur en Ada sur STM32
- [ ] Balayage motorisé et reconstruction 3D

## Vérification formelle

Le paquet `Radar_Sweep` est entièrement prouvé avec SPARK (prouveur CVC5) :

- absence d'erreur d'exécution (débordements, indices hors bornes) ;
- contrats fonctionnels (la détection de pic renvoie bien le maximum) ;
- terminaison des sous-programmes.

Reproduire la preuve :

    alr gnatprove

## Compilation et exécution

    alr build
    alr run

## Outils

Ada 2022, SPARK, Alire, GNAT (natif et `gnat_arm_elf` pour la cible STM32).

## Licence

MIT.
