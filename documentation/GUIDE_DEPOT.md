# Guide du dépôt — où trouver quoi

Carte du dépôt `radar_fw`. À ouvrir quand on cherche un fichier, pas quand on
cherche une décision (pour ça, c'est `CAP_PROJET.md`).

> **Règle qui garde ce guide vrai :** il ne contient **aucun chiffre
> d'avancement** (nombre de tests, de checks SPARK, de paquets). Ces chiffres
> vivent dans `CAP_PROJET.md` §5, à un seul endroit. Ce guide ne devient donc
> faux **que si un fichier bouge** — et dans ce cas, il faut le mettre à jour
> dans le même commit (voir `CLAUDE.md`, étape 5).

---

## 1. Je cherche… (l'entrée rapide)

| Ma question | Où aller |
| ----------- | -------- |
| C'est quoi ce projet ? | `README.md` (racine) |
| Où va le projet, qu'est-ce qui est interdit ? | `documentation/CAP_PROJET.md` §1 à §4 |
| Où en est-on vraiment ? Combien de tests ? | `documentation/CAP_PROJET.md` §5 |
| Quoi faire ensuite ? | `documentation/CAP_PROJET.md` §9 (feuille de route) |
| Qu'est-ce qu'on achète, et comment ça se câble ? | `documentation/GUIDE_MATERIEL.md` |
| Comment je branche le STM32, l'ESP32, le capteur ? | `documentation/GUIDE_MATERIEL.md` §4 bis |
| Comment je flashe la carte ? | `documentation/GUIDE_MATERIEL.md` §4 bis (fin) |
| Quel format ont les trames carte → PC ? | `documentation/CAP_PROJET.md` §7.6 |
| Pourquoi le code fait ça comme ça ? | `documentation/CAP_PROJET.md` §6 (réalisme) et §8 (dettes) |
| Comment un agent doit travailler ici ? | `CLAUDE.md` (racine) |
| Où est tel fichier ? | ce guide, sections 2 et 3 |

---

## 2. La racine

| Élément | Quoi | Versionné |
| ------- | ---- | --------- |
| `README.md` | la vitrine publique GitHub | oui |
| `CLAUDE.md` | la procédure de session (chargée automatiquement par Claude Code) | oui |
| `documentation/` | les documents projet | oui |
| `src/` | le code Ada, rangé par domaine | oui |
| `tests/` | les suites de tests AUnit | oui |
| `docs/` | **le site publié** sur GitHub Pages (`docs/index.html`) — ne pas confondre avec `documentation/` | oui |
| `alire.toml` | le manifeste Alire (dépendances, exécutable) | oui |
| `radar_fw.gpr` et les 3 autres `.gpr` | les projets de compilation (voir §4) | oui |
| `ravenscar.adc` | impose `pragma Profile (Ravenscar)` à la compilation de la démo | oui |
| `.github/workflows/ci.yml` | l'intégration continue | oui |
| `.gitignore`, `.markdownlint.json` | configuration | oui |
| `out/` | **généré** : les visualiseurs HTML des modes `map` et `track` | non |
| `obj/` `bin/` `alire/` `config/` `share/` | **généré** : sortie de build Alire/GNAT | non |
| `REVUE_CRITIQUE_2026-07-02.md` | note de travail **volontairement locale** (exclue via `.git/info/exclude`) | non |

**Les deux dossiers qui se ressemblent :**

- `documentation/` = les documents du projet, pour toi.
- `docs/` = la copie du visualiseur publiée sur le web, pour les visiteurs.
  Ce nom est **imposé par GitHub Pages**, on ne peut pas le changer.

---

## 3. Le code (`src/`), rangé par domaine

Les sous-dossiers ne sont pas décoratifs : ils correspondent à ce que chaque
projet de compilation embarque (§4).

### `src/processing/` — le cœur embarquable

Le seul code qui part sur le microcontrôleur. Interdit d'y mettre du
`Ada.Text_IO` ou du `Ada.Calendar` (règle R7).

| Fichier | Paquet | Rôle | SPARK |
| ------- | ------ | ---- | ----- |
| `radar_sweep.ads/.adb` | `Radar_Sweep` | types bornés, seuil, pic, distance, multi-cibles, CFAR | oui |
| `radar_clutter.ads/.adb` | `Radar_Clutter` | carte de clutter MTI adaptative | pas encore |

Les deux seules unités en `SPARK_Mode => On` du dépôt sont `Radar_Sweep` et
`Radar_Buffer` (`src/tasking/`). Vérifiable d'une commande :
`grep -rn "SPARK_Mode" src/`

### `src/source/` — d'où viennent les données, et la perception

| Fichier | Paquet | Rôle |
| ------- | ------ | ---- |
| `radar_source.ads` | `Radar_Source` | **l'interface abstraite** — le point d'entrée de tout capteur (R3) |
| `radar_sim_source.ads/.adb` | `Radar_Sim_Source` | la source simulée (bruit, Swerling, fantômes) |
| `radar_world.ads/.adb` | `Radar_World` | la vérité terrain : objets mobiles, murs |
| `radar_detect.ads/.adb` | `Radar_Detect` | détections 3D d'un tour + regroupement spatial |
| `radar_track.ads/.adb` | `Radar_Track` | le pistage : association, alpha-beta, M-sur-N, fusion |

### `src/geometry/` — les maths

| Fichier | Paquet | Rôle |
| ------- | ------ | ---- |
| `radar_geometry.ads/.adb` | `Radar_Geometry` | polaire ↔ cartésien |
| `radar_cloud.ads/.adb` | `Radar_Cloud` | le nuage de points |

### `src/tasking/` — la concurrence Ravenscar

| Fichier | Paquet | Rôle |
| ------- | ------ | ---- |
| `radar_buffer.ads/.adb` | `Radar_Buffer` | l'objet protégé `Mailbox` (entry à barrière) |
| `radar_tasks.ads/.adb` | `Radar_Tasks` | tâche cyclique + tâche sporadique |

### `src/app/` — les modes et la sortie

| Fichier | Rôle |
| ------- | ---- |
| `radar_fw.adb` | le point d'entrée : aiguille vers `track`, `map`, `live`, `scan` |
| `radar_run_tracking.adb` | mode `track` — génère `out/radar_tracking_3d.html` |
| `radar_run_mapping.adb` | mode `map` — génère `out/radar_3d.html` |
| `radar_run_live.adb` | mode `live` — serveur temps réel |
| `radar_run_scan.adb` | mode `scan` — serveur, cartographie progressive |
| `radar_http.ads/.adb` | `Radar_Http` : le serveur HTTP en Ada, partagé par `live` et `scan` |
| `radar_html.ads/.adb` | `Radar_Html` : helpers de sérialisation |

### `src/demo/`

| Fichier | Rôle |
| ------- | ---- |
| `radar_demo.adb` | le main de la démonstration Ravenscar |

### `tests/`

| Fichier | Rôle |
| ------- | ---- |
| `run_tests.adb` | le lanceur (produit `bin/run_tests`) |
| `radar_sweep_tests.ads/.adb` | suite 1 : traitement du balayage |
| `radar_pipeline_tests.ads/.adb` | suite 2 : géométrie, regroupement, pistage, clutter, CFAR |

---

## 4. Les quatre projets de compilation

Il y en a quatre, et ce n'est pas un accident : chacun compile un
sous-ensemble différent, pour une raison différente.

| Projet | Compile | Pourquoi il existe |
| ------ | ------- | ------------------ |
| `radar_fw.gpr` | `app` + `geometry` + `processing` + `source` | l'application PC |
| `radar_demo.gpr` | `demo` + `tasking` + `processing`, sous `ravenscar.adc` | imposer le profil Ravenscar (il n'importe **pas** la config AUnit, qui violerait `No_Calendar`) |
| `radar_core.gpr` | `processing` seul, pour `arm-eabi` | le garde-fou embarqué : si le cœur cesse d'être portable, ça casse ici (R7) |
| `radar_fw_tests.gpr` | `tests` + `radar_fw.gpr` | les tests AUnit |

Ils restent à la racine : c'est la convention Alire, `alr` s'attend à trouver
`radar_fw.gpr` là.

---

## 5. Les commandes

    alr build                          # compiler l'application
    alr run                            # mode track  -> out/radar_tracking_3d.html
    alr exec -- ./bin/radar_fw map     # mode map    -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live    # mode live   -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan    # mode scan   -> http://localhost:8080

    alr exec -- gprbuild -p -P radar_fw_tests.gpr   # compiler les tests
    alr exec -- ./bin/run_tests                     # les lancer

    alr exec -- gnatprove -P radar_fw.gpr   --report=all --checks-as-errors=on
    alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on

    alr exec -- gprbuild -p -P radar_demo.gpr   # la demo Ravenscar
    alr exec -- gprbuild -p -P radar_core.gpr   # le garde-fou ARM

Pour `map` et `track`, ouvrir ensuite le fichier généré dans `out/`. Pour
`live` et `scan`, ouvrir l'URL pendant que le programme tourne.

---

## 6. Quand mettre ce guide à jour

Dès qu'un **fichier ou un dossier bouge, naît ou disparaît** : nouveau paquet,
nouveau mode, nouveau projet `.gpr`, dossier renommé. Pas besoin d'y toucher
quand un compteur change — il n'y en a pas ici, c'est voulu.
