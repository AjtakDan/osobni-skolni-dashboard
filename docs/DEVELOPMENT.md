# Vývoj a vlastní sestavení Orbit

Školní dashboard pro macOS: rozvrh, známky, úkoly, poznámky a časovač. Swift/AppKit/WebKit, HTML/CSS/JavaScript a lokální Python konektor.

**Experimentální veřejná šablona zdrojového kódu.** Neobsahuje skutečné účty, školní data ani osobní Notion odkazy. Není to zatím hotový instalátor pro spolužáky: nastavení účtu vyžaduje lokální konfiguraci a sestavení.

## Náhled

```sh
python3 native/build.py --html-only
```

Otevři `out/Orbit.html`. Přímá synchronizace EduPage je dostupná pouze v nativní aplikaci.

## Sestavení pro Mac

Potřebuješ macOS 14+, Swift z Xcode/Command Line Tools a Python 3.9+.

1. Zkopíruj příklad konfigurace:

   ```sh
   cp native/Configuration.example.swift native/Configuration.local.swift
   ```

2. V lokálním souboru doplň `username` a `school` (pouze subdoménu před `.edupage.org`). **Heslo do souboru nepiš.** Lokální konfigurace se nesmí publikovat; Git ji ignoruje.
3. Sestav:

   ```sh
   python3 native/build.py
   ```

4. Otevři `out/Orbit.app`. V Nastavení doplň vlastní školní e-mail a adresu EduPage odpovídající konfiguraci. Pak spusť synchronizaci. Heslo se zadává do zabezpečeného pole a lze je uložit do Klíčenky. Konektor při prvním použití stáhne `edupage-api` do vlastního Python prostředí.

Aplikace používá oddělený identifikátor veřejné šablony. Sestavení není notarizované Applem. Distribuce hotové aplikace vyžaduje další testování a vyřešení podpisu.

## Co ještě není dokončené

- Automatický přenos Classroom do nativní aplikace.
- Obecný onboarding bez úprav lokální konfigurace a sestavení.
- Interaktivní CAPTCHA/2FA v konektoru EduPage.
- Obsahová synchronizace Notion; vlastní odkazy lze přidávat u předmětů.

Konektor EduPage je neoficiální a může přestat fungovat při změně služby. Časy zvonění a hranice odhadu známky v `web/core.js` je nutné ověřit pro konkrétní školu. Žádná výsledná školní známka není zaručená místním výpočtem.

## Testy

Spouštěj z kořene repozitáře. Potřebuješ Python a Node.js s ES moduly.

```sh
node tests/blocks.test.mjs
node tests/summary.test.mjs
node tests/edupage.test.mjs
python3 tests/grade_reader_test.py
python3 tests/adapter_test.py
python3 tests/slots_test.py
```

Testy používají syntetická data, ne skutečný účet, a neověřují grafické okno.

## Obsah repozitáře

- `web/` – rozhraní a logika, prázdná osobní data.
- `native/` – macOS obálka, konektor a sestavení.
- `tests/` – testy a syntetické příklady.
- `LICENSE` – GPL verze 3.
- `THIRD_PARTY_NOTICES.md` – závislosti a jejich licence.

## Soukromí

Nenahrávej původní osobní ZIP aplikace, složku Orbit Data, `state.json`, `previous.json`, zálohy ani vlastní `Configuration.local.swift`. `.gitignore` nechrání soubory ručně nahrané přes web GitHubu. Repozitář má obsahovat pouze tento vyčištěný zdrojový balíček.

## Licence

Veřejná varianta zdrojového kódu: GPL-3.0-or-later, viz [`LICENSE`](../LICENSE). Závislost `edupage-api` má vlastní autory a oznámení uvedené v [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md). Projekt není oficiální aplikací EduPage ani Google.
