# Omarchy Translator

A translator in your [Omarchy](https://omarchy.org) 4 bar, backed by the provider of
your choice: [DeepL](https://www.deepl.com) or [Claude](https://claude.com) (through the API
or your [Claude Code](https://claude.com/claude-code) login).
Click the 󰗊 icon, type, press Enter.

New to QML or curious how the pieces fit? Read **[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)**.

The UI is QML (it runs inside Omarchy's Quickshell bar and follows your theme).
The translation is done by a small Ruby CLI that uses only the standard library.

## Features

| Action | What happens |
|---|---|
| **Left click** | Opens the popup: source (auto-detect) → target language, multi-line text box, result |
| **Right click** | Translates the clipboard → notification; result is copied |
| **Middle click** | Select a screen region → OCR (tesseract) → translate → notification |

In the popup: <kbd>Enter</kbd> translates, <kbd>Shift</kbd>+<kbd>Enter</kbd> adds a new
line, <kbd>Ctrl</kbd>+<kbd>Enter</kbd> or the 󰆏 button copies the result (or select part
of it with the mouse), <kbd>Esc</kbd> closes, and 󰓡 swaps the languages. Once more
than one provider is configured, a dropdown above the languages switches between them.
The last provider and languages you used are remembered.

Text is cleaned up before it goes to the provider, whichever way it came in (popup, clipboard
or OCR). Line wraps inside a paragraph are joined, words hyphenated across a line break
are rejoined, and invisible characters (zero-width spaces, soft hyphens, NBSPs, control
characters) are dropped. Blank-line paragraph breaks, punctuation and accents are kept.

## Requirements

- Omarchy 4 (Quickshell bar)
- Ruby 4.0 (managed with [mise](https://mise.jdx.dev), see `mise.toml`)
- At least one provider (see [Providers](#providers)). The easiest start is a DeepL key:
  the [free plan](https://www.deepl.com/pro-api) gives 500k characters/month. If you
  already use [Claude Code](https://claude.com/claude-code), it works with no key at all.
- For middle-click OCR: `slurp`, `grim`, `tesseract` (all shipped with Omarchy)

## Install

```sh
git clone <this repo> ~/Projects/my_omarchy_translator
cd ~/Projects/my_omarchy_translator
mise install                      # Ruby from mise.toml

# 1. API key(s), kept outside the repo (see Providers below for the others;
#    skip this if you only use Claude Code)
mkdir -p ~/.config/omarchy
echo 'DEEPL_AUTH_KEY=your-key:fx' >> ~/.config/omarchy/translator.env
chmod 600 ~/.config/omarchy/translator.env

# 2. Register and place the widget
ln -sfn "$PWD" ~/.config/omarchy/plugins/local.translator
omarchy plugin enable local.translator --section right
```

Once it's pushed to a git host, the plugin can also be installed with
`omarchy plugin add <git-url>`.

### Optional hotkey

Add to `~/.config/hypr/bindings.conf`:

```
bindd = SUPER ALT, T, Translator, exec, omarchy-shell shell toggle local.translator
```

## CLI

The CLI also works without the bar:

```sh
bin/omarchy-translate --to PT-BR "Hello world"
echo "Bonjour tout le monde" | bin/omarchy-translate
bin/omarchy-translate --clipboard --notify
bin/omarchy-translate --json --to DE -- "Good morning"
bin/omarchy-translate --provider claude --to JA "See you tomorrow"
bin/omarchy-translate --status        # active provider and which ones are configured
bin/omarchy-translate --languages
bin/omarchy-translate --help
```

## Providers

Put the settings for any providers you want in `~/.config/omarchy/translator.env`
(an environment variable with the same name overrides the file). The popup lists
only the providers that are configured.

| Provider (`--provider`) | Settings | Notes |
|---|---|---|
| DeepL (`deepl`) | `DEEPL_AUTH_KEY` (`DEEPL_API_URL` optional) | Strong quality for European languages. Keys ending in `:fx` use the free endpoint (500k chars/month) |
| Claude (`claude`) | `ANTHROPIC_API_KEY` (`ANTHROPIC_MODEL`, `ANTHROPIC_API_URL` optional) | Defaults to `claude-opus-5-5` at low effort; set `ANTHROPIC_MODEL=claude-haiku-4-5` for faster, cheaper translations |
| Claude Code (`claude-code`) | None: needs the `claude` CLI on `PATH` and a login (`CLAUDE_CODE_BIN`, `CLAUDE_CODE_MODEL` optional) | Uses your Claude Code subscription instead of an API key, so translations count toward its usage limits. Each request starts the CLI (a few seconds). Uses Claude Code's default model at low effort; set `CLAUDE_CODE_MODEL=haiku` for speed |

Example:

```sh
DEEPL_AUTH_KEY=your-key:fx
ANTHROPIC_API_KEY=sk-ant-…
CLAUDE_CODE_MODEL=haiku       # optional: faster Claude Code translations
TRANSLATOR_PROVIDER=deepl     # optional: default before you pick one in the popup
```

Claude translates more freely than DeepL (it handles idioms and tone well, but
may rephrase), and each request takes a few seconds. Claude Code is listed
automatically when `claude` is installed; it runs `claude -p` with no tools and
no saved session, from a temporary directory so no project `CLAUDE.md` is read.

## Configuration

| What | Where |
|---|---|
| Provider keys and endpoints | `~/.config/omarchy/translator.env`, or env vars of the same name (see [Providers](#providers)) |
| Default provider | `TRANSLATOR_PROVIDER=…` in the same file (the last one used wins once you pick one) |
| Last used provider and languages | `~/.local/state/omarchy/translator.json` |
| OCR languages | `OMARCHY_OCR_LANGS`, e.g. `eng+por` |

## Development

```sh
mise run setup      # install dev gems (RuboCop, Minitest, Rake)
mise run check      # every quality gate — run before committing
mise run reload     # restart the Omarchy shell so QML edits show up
mise tasks          # list all tasks
```

`mise run check` runs these gates:

| Gate | Tool | Config |
|---|---|---|
| Ruby lint | RuboCop + `rubocop-minitest` + `rubocop-rake` | `.rubocop.yml` |
| QML lint | Qt 6 `qmllint` against the live shell's `qs.*` modules | `script/lint-qml` |
| Tests | Minitest: every provider client over a real local socket, config, and the CLI binary end to end | `test/`, `Rakefile` |
| QML tests | Qt 6 `qmltestrunner` (headless) on the popup's logic in `PanelLogic.js` | `test/qml/`, `script/test-qml` |
| Plugin manifest | `omarchy plugin validate` | `manifest.json` |

Tooling: the Ruby version and tasks are in `mise.toml` (the version is mirrored in
`.tool-versions` for asdf), and editor settings are in `.editorconfig`.

Ruby changes take effect right away, because the CLI starts fresh for each
request. QML changes need `mise run reload`: the shell doesn't hot-reload a
symlinked plugin (see [AGENTS.md](AGENTS.md) for the details). AI agents should
read AGENTS.md first.

## Project layout

```
manifest.json              Omarchy plugin manifest
BarWidget.qml / Panel.qml  Bar icon and popup (QML)
PanelLogic.js              The popup's pure logic (labels, options, swap), tested headless
bin/omarchy-translate      CLI
lib/omarchy_translator.rb  Language tables, text cleanup, provider registry
lib/omarchy_translator/    Config and one client per provider (providers/)
script/lint-qml            QML lint gate
script/test-qml            QML test gate (qmltestrunner)
test/                      Minitest suite (+ support/), QML tests in test/qml/
docs/HOW_IT_WORKS.md       QML primer and architecture
```
