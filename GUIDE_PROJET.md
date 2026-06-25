# Guide du projet — radar_fw

Document de référence du projet : intention, architecture, état d'avancement et
feuille de route. Sert de mémoire de projet (pour moi **et** pour un agent comme
Claude Code, qui n'a pas accès à l'historique des discussions et se repère grâce
aux fichiers du dépôt).

---

## 1. Intention (à lire en premier)

L'objectif réel de ce projet est de **démontrer de la programmation embarquée
haute-intégrité en Ada/SPARK**, en vue de postes en **défense / aéronautique**
(Thales, Safran, Dassault, MBDA, Airbus Defence & Space, Naval Group,
ArianeGroup…).

> Le radar est un **prétexte technique**, pas la finalité. Ce qui compte, c'est
> la chaîne embarquée rigoureuse : Ada, concurrence déterministe (Ravenscar),
> contrats, et **preuve formelle SPARK**. Prioriser l'effort en conséquence.

Argument de vente d'un tel projet : conception « correct par construction »,
absence d'erreur d'exécution **prouvée**, contrats fonctionnels prouvés —
exactement ce que recherche le domaine.

> Note réaliste : beaucoup de postes défense en France exigent la nationalité
> française et une habilitation. Un portfolio Ada/SPARK solide reste un atout
> fort pour décrocher stages et entretiens.

---

## 2. Matériel

| Matériel                        | Statut    | Rôle                                          |
|---------------------------------|-----------|-----------------------------------------------|
| ESP32                           | possédé   | hors cible (Xtensa ; Ada possible mais peu balisé) |
| PIC                             | possédé   | hors cible (pas de support Ada)               |
| WeAct **STM32G474**             | à acheter | cerveau Ada (Cortex-M4 + FPU), ~10–15 €       |
| ST-Link V2 (clone)              | à acheter | programmateur/débogueur, ~3–5 €               |
| Capteur radar **Acconeer A121** | à acheter | radar 60 GHz, données brutes, ~20–50 €        |
| Moteurs pas-à-pas + drivers     | à acheter | balayage mécanique (scan)                     |

Choix du STM32 : c'est la famille proprement supportée par la toolchain Ada
(`gnat_arm_elf`) et les runtimes (`light`, `light-tasking`, Ravenscar). Le G474
a les runtimes publiés, dont `light-tasking` indispensable à la vitrine
Ravenscar. Budget matériel total visé : **100–300 €**.

---

## 3. Architecture cible

```
[Capteur A121] --SPI--> [STM32G474 — Ada bare-metal, profil Ravenscar]
[Moteur+encodeur] <----> |  tâche acquisition  |
                         |  tâche moteur/scan  |  --> objet protégé (tampon, prouvé SPARK)
                         |  tâche télémétrie   |  --UART/USB--> [PC : DSP lourd + rendu 3D]
```

Principes :

- Le **STM32 fait le temps réel et le formatage des données en Ada** (la vitrine
  embarquée). Pas de FFT lourde sur le MCU.
- Le **PC** fait le DSP lourd et la reconstruction 3D (Python / Open3D).
- Le **driver SPI du capteur est écrit en Ada** (élément différenciant), pas une
  lib C toute faite.

### Sur les « plusieurs faisceaux »

Le vrai multi-faisceaux (phased array type **AESA**) n'est pas réalisable au
budget hobby. La version abordable est le **beamforming par balayage mécanique**
(on pointe → on synthétise l'angle), éventuellement complété par du beamforming
numérique. À présenter comme tel, pas comme de l'AESA. Attentes réalistes sur le
rendu : nuage de points 3D **épars** (bonne résolution en distance, résolution
angulaire grossière), pas une maquette CAO.

---

## 4. État d'avancement

### Fait

- [x] Environnement Ada complet (Alire + VS Code + toolchains native et ARM)
- [x] Paquet `Radar_Sweep` : types bornés (`Millimeters`, `Bin_Index`,
      `Amplitude`, `Sweep`), `Peak_Bin` (détection du pic) et `Peak_Distance`
      (conversion en distance), avec contrats `Post` et `Loop_Invariant`
- [x] Banc de test dans `radar_fw.adb` (pic simulé en case 64 → détecté, ~4914 mm)
- [x] **Preuve SPARK complète : 8 checks, 0 non prouvé** (prouveur CVC5)
- [x] Git + GitHub (`github.com/St3id/radar_fw`) + README

### À venir — feuille de route

Chaque phase = un jalon montrable. Les phases 1–3 ne demandent **aucun matériel**.

1. **(sans HW)** Enrichir le traitement : cas « aucune cible » (seuil de
   détection), détection multi-cibles — et **prouver** ces versions en SPARK.
2. **(sans HW)** Cadre de tests **AUnit** (remplace le `if` du main ;
   renforce l'argument traçabilité exigences → tests).
3. **(sans HW)** Documenter la traçabilité (exigences ↔ code ↔ tests).
4. **(carte requise)** Phase 0 « blinky » sur STM32G474 :
   cross-compiler (`gnat_arm_elf` + runtime **AdaCore** `embedded_stm32g4xx` /
   `light-tasking-stm32g4xx`), puis flasher via OpenOCD/ST-Link.
   *Éviter les crates `a0b` (voir § Notes).*
5. **(carte requise)** Driver **A121 en SPI**, écrit en Ada.
6. **(carte requise)** Architecture **Ravenscar** : tâches + objet protégé
   (tampon partagé), idéalement prouvé SPARK.
7. **(carte requise)** Scan motorisé + assemblage du nuage de points.
8. **(PC)** DSP + reconstruction 3D (Python / Open3D), affichage progressif.

---

## 5. Conventions du projet

- **Cycle Git** : `git add .` → `git commit -m "..."` → `git push`, à chaque
  jalon. Messages clairs (un recruteur lit l'historique).
- **Types bornés + contrats partout** : pas d'entier nu pour une grandeur
  physique ; préconditions/postconditions sur les interfaces.
- **`SPARK_Mode => On`** sur tous les paquets de calcul ; le `main` de test peut
  rester en `SPARK_Mode => Off`.
- **Reprouver après chaque ajout** de logique (`alr gnatprove`, viser 0 unproved).
- **README** tenu à jour (la liste d'avancement reflète l'état réel).
- Commentaires : tolérés sans accents par sécurité ; passage en anglais prévu
  pour la visibilité GitHub.

---

## 6. Notes & enseignements

- **Crates `a0b`** (BSP communautaire STM32) : ne compilent pas avec la toolchain
  récente — elles sont épinglées à `gnat_arm_elf=14.2` / `gprbuild=22`, d'où
  l'erreur `Runtime_Ada is not a single string` avec gnat 15.2 / gprbuild 25.
  → Pour la cible STM32, utiliser le runtime **maintenu par AdaCore**
  (`embedded_stm32g4xx`), pas ces crates.
- **Le blinky a besoin du matériel** : le brochage LED se vérifie sur la carte
  réelle. La cross-compilation peut se préparer sans carte, mais la validation
  finale (flash) attend le STM32.
- **ESP32** : Ada possible (toolchain `gnat_xtensa_esp32_elf` présente) mais
  hors cible défense/aéro et moins documenté → on reste sur STM32.

---

## 7. Briefing à coller pour Claude Code (ou nouvelle session)

> Projet `radar_fw` : démonstrateur d'embarqué haute-intégrité en **Ada/SPARK**,
> visant la défense/aéro. Le radar est un prétexte ; la vitrine, c'est la
> rigueur (Ravenscar, contrats, preuve SPARK). Cible matérielle : **STM32G474**.
> État actuel : environnement OK ; paquet `Radar_Sweep` (détection de pic +
> distance) écrit, testé et **prouvé en SPARK (0 unproved)** ; versionné sur
> GitHub. Voir `GUIDE_PROJET.md` (ce fichier) et `GUIDE_INSTALLATION_ADA.md`.
> Prochaine étape sans matériel : enrichir le traitement (seuil « aucune cible »,
> multi-cibles) et le prouver en SPARK, puis AUnit.
> Important : c'est un projet d'apprentissage — **expliquer avant de modifier**,
> et procéder par petites étapes.
