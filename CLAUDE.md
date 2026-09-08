# Procédure de session — radar_fw

Ce fichier est **chargé automatiquement au début de chaque session** de Claude
Code. Il ne décrit pas le projet (c'est le rôle de `documentation/CAP_PROJET.md`) : il décrit
**quoi faire, dans quel ordre**, pendant une session de travail.

Le lire ne suffit pas : il s'applique.

---

## Contexte permanent

- Projet **`radar_fw`** : un capteur radar qui cartographie un volume en 3D et
  y suit des entités mobiles. Écrit en **Ada 2022**, avec Alire.
- **Projet d'apprentissage.** L'auteur débute en Ada : **expliquer chaque
  changement, en français, AVANT de l'appliquer**, et comprendre le *pourquoi*
  compte autant que le résultat.
- Branche de travail courante : **`tracking-3d`**. La branche principale est
  `main`.
- La CI GitHub Actions tourne sur **toutes** les branches : un push casse ou
  ne casse pas, il n'y a pas de zone grise.

---

## Étape 1 — Au démarrage de la session

1. Lire **`documentation/CAP_PROJET.md`** : le cap (§1), la règle d'arbitrage (§2), le
   périmètre (§3) et les règles anti-dérive **R1 à R7** (§4).
2. Lire la section **§5 « État réel du dépôt »**. Les chiffres qui y figurent
   font foi : nombre de tests, checks SPARK, modes, paquets.
3. **Ne jamais supposer l'état d'avancement de mémoire.** Si le dépôt
   contredit le document, ce n'est pas le document qui a raison : c'est le
   document qu'il faut **corriger** (étape 5).
4. Pour trouver un fichier plutôt qu'une décision :
   **`documentation/GUIDE_DEPOT.md`** est la carte du dépôt.

---

## Étape 2 — Avant toute modification

1. **Expliquer en français** ce qui va changer et **pourquoi**. Pas un résumé
   après coup : une explication avant l'action.
2. **Attendre l'accord** avant d'écrire.
3. **Petites étapes.** Une notion à la fois. Ne pas enchaîner cinq fichiers
   d'un coup : l'auteur doit pouvoir suivre chaque changement.
4. **Vérifier la conformité au cap.** Si le changement s'approche d'une
   limite, la nommer explicitement — par exemple : « attention, ça mettrait un
   seuil de décision dans le JavaScript : c'est R1 ». De même pour un capteur
   branché hors de `Radar_Source` (R3), un ajout de dépendance PC dans
   `src/processing` (R7), ou un quatrième document markdown (R6).

---

## Étape 3 — Pendant l'écriture du code

- Respecter les conventions de `documentation/CAP_PROJET.md` §10 : types bornés, contrats,
  commentaires **en français sans accents** (ASCII pur) expliquant le
  *pourquoi*, style GNAT strict, zéro warning.
- Ne pas retirer un `SPARK_Mode => On` existant pour se simplifier la vie
  (R2). Pour du code neuf, un `SPARK_Mode => Off` **commenté** est acceptable.

---

## Étape 4 — Après une modification de code

Dans cet ordre, en s'arrêtant au premier échec :

    alr build
    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    alr exec -- ./bin/run_tests
    alr exec -- gnatprove -P radar_fw.gpr --report=all --checks-as-errors=on

Attendus : **18 tests verts**, **85 checks SPARK, 0 non prouvé**. Si un
chiffre a légitimement changé (test ajouté, code prouvé ajouté), c'est une
mise à jour de documentation, pas une anomalie — voir étape 5.

Si la modification touche le cœur ou la concurrence, ajouter :

    alr exec -- gprbuild -p -P radar_demo.gpr   # profil Ravenscar impose
    alr exec -- gprbuild -p -P radar_core.gpr   # garde-fou ARM (R7)

**Un échec se corrige, il ne se contourne pas.** Ne jamais désactiver un test,
relâcher un contrat ou retirer `--checks-as-errors=on` pour faire passer une
étape.

---

## Étape 5 — Mettre les documents à jour (obligatoire, dans le même commit)

C'est l'étape qu'on oublie, et c'est elle qui a produit six documents
contradictoires par le passé. Elle n'est pas facultative (R5).

| Ce qui a changé | Fichiers à mettre à jour |
| --------------- | ------------------------ |
| Nombre de tests | `README.md` (**2 endroits** : la liste d'avancement ET la section « Tests »), `documentation/CAP_PROJET.md` §5, **et ce fichier** (étape 4) |
| Nombre de checks SPARK | `README.md` (**2 endroits** : liste d'avancement ET section « Vérification formelle »), `documentation/CAP_PROJET.md` §5 |
| Nouveau mode d'exploitation | `README.md`, `documentation/CAP_PROJET.md` §5 |
| Nouveau paquet ou projet GPR | `documentation/CAP_PROJET.md` §5 (tableau des paquets / des projets) |
| Jalon terminé | `documentation/CAP_PROJET.md` §9 |
| Dette résolue ou découverte | `documentation/CAP_PROJET.md` §8.1 |
| Enseignement coûteux (piège, version cassée…) | `documentation/CAP_PROJET.md` §8.2 |
| Décision matérielle, achat, capteur | `documentation/GUIDE_MATERIEL.md` |
| **Un fichier ou un dossier bouge, naît ou disparaît** | `documentation/GUIDE_DEPOT.md` (la carte du dépôt) |
| Changement du cap ou du périmètre | `documentation/CAP_PROJET.md` §1 à §4 — **demander confirmation avant** |

Vérification rapide de cohérence avant de commiter : les chiffres de
`README.md` et de `documentation/CAP_PROJET.md` §5 doivent être identiques.

---

## Étape 6 — Proposer le commit, ne pas le faire d'office

1. Annoncer le **message de commit envisagé** : français **sans accents**,
   préfixe du dépôt (`docs :`, `tests :`, `CI :`, `fix :`, `perf :`, `feat :`)
   ou sujet direct (`Mode scan : ...`).
2. Demander explicitement lequel des trois : **commit seul**, **commit +
   push**, ou **rien pour l'instant**.
3. Ne jamais committer sans cette confirmation, même quand tout est vert.

---

## Interdits

- **Ne jamais versionner `REVUE_CRITIQUE_2026-07-02.md`** : il est
  volontairement hors GitHub (`.git/info/exclude`).
- **Ne pas créer un nouveau document** (R6) : le jeu est fixé à `README.md`,
  `CLAUDE.md` et les trois de `documentation/`. Une nouvelle analyse devient
  une **section** d'un document existant.
- **Ne pas committer les fichiers générés** : tout le dossier `out/` (déjà
  dans `.gitignore`). Exception : `docs/index.html` est la copie **publiée**
  volontairement versionnée pour GitHub Pages.
- **Ne pas confondre `docs/` et `documentation/`** : le premier est le site
  publié, le second la documentation du projet.
- **Ne pas mettre de logique métier dans le JavaScript** (R1).

---

## Repères techniques

Les quatre projets GPR, et pourquoi il y en a quatre :

| Projet | Compile | Sert à |
| ------ | ------- | ------ |
| `radar_fw.gpr` | l'application PC | l'exécutable principal (`track`, `map`, `live`, `scan`) |
| `radar_demo.gpr` | la démo Ravenscar | imposer le profil temps réel (n'importe **pas** la config AUnit : elle violerait `No_Calendar`) |
| `radar_core.gpr` | `src/processing` pour ARM | le garde-fou embarqué (R7) |
| `radar_fw_tests.gpr` | les suites AUnit | les tests |

Lancer les modes :

    alr run                          # track : rejeu du pistage
    alr exec -- ./bin/radar_fw map   # cartographie figee -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # veille temps reel -> localhost:8080
    alr exec -- ./bin/radar_fw scan  # cartographie progressive -> localhost:8080

Prochain jalon en cours : voir `documentation/CAP_PROJET.md` §9.
