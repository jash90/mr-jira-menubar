# Notatki do strony GitHub Pages

Analiza repozytorium `jash90/mr-jira-menubar` (publiczne), z której powstała strona w `site/`.

## Czym jest aplikacja

Natywna aplikacja macOS działająca na pasku menu (agent app, `LSUIElement`, bez ikony w Docku).
Pokazuje liczniki pracy bieżącego użytkownika z trzech źródeł i odświeża je co 5 minut
(`StatusStore`, `interval = 300`), a na żądanie skrótem ⌘R.

| Źródło | Liczniki | Jak liczone (kod) |
| --- | --- | --- |
| GitLab | otwarte MR, gotowe do mergu | `scope=created_by_me&state=opened`; gotowe = ≥ 2 approve (`approvalThreshold`) |
| GitHub | otwarte PR, approved | Search API: `is:pr is:open author:@me archived:false` (+ `review:approved`) |
| Jira | backlog, w toku, w testach — czeka, zaakceptowane, odrzucone | JQL w `JiraClient` (statusy „To Do”, „Backlog”, „In Progress”, „Code review”, „Internal testing”) |

„Odrzucone” to licznik „od zawsze”: zadanie, które użytkownik przeniósł do „Internal testing”,
a następna zmiana statusu (wykonana przez kogoś innego) cofnęła je do „In Progress”. Przy
aktywnym GitLabie wymagany jest też MR użytkownika z kluczem zadania, utworzony przed cofnięciem
(`RejectedIssuesService`, spec `docs/superpowers/specs/2026-07-14-sticky-rejected-counter-design.md`).

Pozostałe funkcje: menu z linkami do widoków GitLab / GitHub / JQL, tooltip z podsumowaniem,
przełączniki źródeł GitLab/GitHub, osobne ukrywanie każdego z 9 liczników z paska, baner błędu
połączenia i czerwone symbole ostrzeżenia, komunikat o 401, sprawdzanie nowej wersji co 6 h
(GitHub Releases) z pobraniem DMG do Pobranych, autostart (`SMAppService`), dane logowania
w Keychainie jako jeden wpis zaszyfrowany AES-GCM (klucz z „pieprzu” w binarce — zaciemnienie,
nie dodatkowa ochrona).

## Odbiorca i ton

Programiści pracujący z GitLabem/GitHubem i Jirą w wersji Server/Data Center (token PAT jako
Bearer, REST API v2), prawdopodobnie w zespole z etapem „Internal testing”. Interfejs aplikacji
jest wyłącznie po polsku (brak i18n). Ton strony: konkretny, techniczny, z sekcją dla developerów.

## Typ projektu i stack

Aplikacja desktopowa macOS 13+. Swift 5.9, Swift Package Manager, AppKit (`NSStatusItem`),
SwiftUI (okno ustawień), CryptoKit, ServiceManagement, XCTest. Brak zależności zewnętrznych.
Moduły: `Sources/MenuBarCore` (logika, tylko Foundation, testy), `Sources/MRJiraMenuBar` (UI).

Uruchomienie: `swift run MRJiraMenuBar`; testy: `swift test`; paczka: `scripts/build-app.sh`.
Brak zmiennych środowiskowych — hosty i tokeny wpisuje się w oknie ustawień. Zależności
zewnętrzne w runtime: API GitLaba, GitHuba, Jiry i GitHub Releases (aktualizacje).

## CTA, repo, identyfikacja

- Brak adresu produkcyjnego (to aplikacja desktopowa) → CTA: `releases/latest` (DMG v1.4.0).
- DMG v1.4.0 jest podpisany ad hoc (`codesign -dv`: `Signature=adhoc`, `spctl`: rejected) —
  strona uczciwie opisuje obejście Gatekeepera zamiast twierdzić, że build ma Developer ID.
- Repo: `jash90/mr-jira-menubar`, strona: `https://jash90.github.io/mr-jira-menubar/`, brak CNAME.
- Brak pliku LICENSE, brak danych kontaktowych w repo → w stopce link do Issues.
- Logo: `assets/AppIcon.png` (gradient niebieski `#3351FC` → fiolet `#7945FF` → magenta `#AD27F3`,
  biały glif). Font aplikacji: systemowy SF Pro → na stronie systemowy stos fontów.

## Pages

Brak wcześniejszej strony, gałęzi `gh-pages` i workflow Pages. `docs/` zawiera dokumentację
projektową (`docs/superpowers`), więc strona trafiła do `site/`, a deploy robi
`.github/workflows/pages.yml` (upload katalogu `site/`).

## Zrzuty ekranu

`scripts/screenshots.sh` kompiluje harness z niezmienionych plików UI aplikacji
(`StatusItemController`, `SettingsView`, `SettingsWindowController`) i
`scripts/screenshots/main.swift`, który podaje im fikcyjne liczniki i hosty `*.example.com`
(bez sieci, Keychaina i UserDefaults). Okna są przechwytywane `screencapture`, a
`scripts/screenshots/process.py` (Pillow) tnie je do WebP i składa obraz hero / OG.

Ograniczenia: menu paska stanu zawsze przyjmuje wygląd systemowego paska menu, więc na Macu
w trybie ciemnym powstają tylko ciemne zrzuty menu (okno ustawień jest w obu motywach).
Zrzuty mają skalę 1× (główny monitor nie był Retiną). Brak ujęć mobilnych — aplikacja jest
wyłącznie na macOS; responsywność sprawdzono dla samej strony.
