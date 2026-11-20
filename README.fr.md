<p align="center">
  <img src="docs/icon.png" width="128" alt="Icône Valet Desktop">
</p>

<h1 align="center">Valet Desktop</h1>

<p align="center">
  Une petite appli macOS native, dans la barre de menus, pour piloter <a href="https://laravel.com/docs/valet">Laravel Valet</a> sans terminal.<br>
  <a href="README.md">English version</a>
</p>

---

Valet est l'environnement PHP local le plus léger sur macOS (nginx + dnsmasq + php-fpm, sans Docker ni VM), mais il ne s'utilise qu'en ligne de commande. Valet Desktop met les commandes courantes à un clic, sans rien alourdir :

- **SwiftUI natif**, DMG d'environ 560 Ko, universel (Apple Silicon + Intel), aucune dépendance.
- **Rien ne tourne en fond.** Pas de minuteur, pas de démon. L'état est relu à l'ouverture du menu et après chaque action. Une fois l'appli quittée, il ne reste aucun processus.
- **N'installe rien.** Si Valet est absent, l'appli l'affiche et donne la commande à lancer toi-même.

> Projet communautaire, non affilié à Laravel.

## Fonctions

| Domaine | Ce que tu peux faire | Commande Valet / Homebrew |
| --- | --- | --- |
| État | Voir démarré / arrêté / **non installé**, Start / Stop | `valet status`, `valet start`, `valet stop` |
| Sites | Lister les sites liés, les ouvrir dans le navigateur, les afficher dans le Finder | `valet links` |
| Link | Choisir un dossier et le lier | `valet link <nom>` |
| HTTPS | Activer / désactiver HTTPS pour un site | `valet secure`, `valet unsecure` |
| PHP | Changer la version de PHP globale | `valet use php@X` |
| PHP par site | Isoler un site sur une version de PHP, ou revenir au global | `valet isolate`, `valet unisolate` |
| Proxys | Rediriger `nom.test` vers un port local (Node, Vite…), le supprimer | `valet proxy <nom> http://127.0.0.1:<port> [--secure]`, `valet unproxy` |
| MariaDB | Démarrer / arrêter MariaDB Homebrew (s'il est installé) | `brew services start\|stop mariadb` |

L'appli prévient aussi si Yerd est présent (même ports 80/443 et même DNS `.test`).

## Prérequis

- macOS 14 Sonoma ou plus récent
- Homebrew (`/opt/homebrew` ou `/usr/local`)
- Laravel Valet installé via Composer :

```bash
composer global require laravel/valet
```

```bash
valet install
```

## Installation

1. Télécharge `ValetDesktop-x.y.z.dmg` depuis la [dernière version](https://github.com/aubinvan/valet-desktop/releases/latest).
2. Ouvre-le et glisse **Valet Desktop** dans **Applications**.
3. Premier lancement : l'appli est signée ad hoc mais **pas notarisée** (pas de compte Apple Developer payant), macOS la bloque donc une fois. Au choix :
   - lance-la, puis **Réglages Système → Confidentialité et sécurité → Ouvrir quand même** ;
   - ou retire l'attribut de quarantaine :

```bash
xattr -dr com.apple.quarantine "/Applications/Valet Desktop.app"
```

L'icône **V** apparaît dans la barre de menus (pas dans le Dock). **Quitter** (⌘Q) dans le menu ferme tout.

Vérifier le téléchargement avec le fichier `.sha256` joint à la version :

```bash
shasum -a 256 -c ValetDesktop-0.1.0.dmg.sha256
```

## Mot de passe administrateur (`sudo`)

Valet relance certaines commandes avec `sudo` (start, stop, use, secure, isolate…). L'appli n'a pas de terminal : elle fournit à `sudo` un *askpass*, une boîte de dialogue macOS standard qui demande ton mot de passe. Il va directement à `sudo`, l'appli ne le lit ni ne le garde. Si tu annules, un message clair s'affiche (bouton **Détails** pour la sortie complète).

Pour ne plus avoir d'invite : `valet trust` (règles sudoers pour `valet` et `brew`), à lancer toi-même si tu le souhaites.

## Compiler depuis les sources

Xcode 15.4+ ou les Command Line Tools (Swift 5.10+).

```bash
git clone https://github.com/aubinvan/valet-desktop.git && cd valet-desktop
```

```bash
./build.sh
```

```bash
open "build/Valet Desktop.app"
```

Créer le DMG (dans `build/`, avec son SHA-256) :

```bash
./scripts/make-dmg.sh
```

Lancer les tests :

```bash
swift test
```

Structure du code et procédure de publication : [CONTRIBUTING.md](CONTRIBUTING.md).

## Limites

- Pas notarisée (voir Installation).
- Testée uniquement sur Apple Silicon ; la version Intel (Homebrew dans `/usr/local`) n'est pas testée.
- Les dossiers « parked » (`valet park`) ne sont pas encore gérés.

## Licence

[MIT](LICENSE) : utiliser, copier, modifier, vendre, redistribuer, tout est permis. Seule condition : garder la mention de copyright.
