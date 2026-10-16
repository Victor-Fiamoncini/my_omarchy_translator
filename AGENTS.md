# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, OpenCode, …) working in this
repository. Humans should start with [README.md](README.md); the architecture
is explained in depth in [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

## What this is

An **Omarchy 4 bar widget** that translates text with a provider the user picks
(**DeepL**, Claude through the API or the local Claude Code CLI, or Google
**Gemini**). Omarchy 4 no longer uses Waybar: the desktop shell is a single
long-running [Quickshell](https://quickshell.org/) (Qt/QML) process, and
every bar item is a plugin. This repository root *is* the plugin —
`manifest.json` must stay at the top level.

Two halves, split on purpose:

| Layer | Files | Language | Role |
|---|---|---|---|
| UI | `BarWidget.qml`, `Panel.qml`, `ProviderDropdown.qml`, `ProviderLogo.qml`, `PanelLogic.qml` | QML | Bar icon + popup. Runs inside `omarchy-shell`. |
| Logic | `lib/`, `bin/omarchy-translate` | Ruby 4.0 | Provider clients + CLI. Run by the UI as a subprocess. |

The QML never talks to the network. It runs `bin/omarchy-translate --json …` via
Quickshell `Process` and parses one JSON object from stdout.

## Layout

```
manifest.json              Omarchy plugin manifest (id: local.translator)
BarWidget.qml              Bar pill: left=popup, right=clipboard, middle=OCR region
Panel.qml                  Popup: provider dropdown, language dropdowns, multi-line input, result card
ProviderDropdown.qml       Provider picker: qs.Ui Dropdown's look and keys, plus logos and "not set up" rows
ProviderLogo.qml           Provider logo (Simple Icons SVG path via QtQuick.Shapes, theme-tinted)
PanelLogic.qml             Popup's pure logic (options, labels, footer, swap), declared in Panel as `logic`
bin/omarchy-translate      CLI entry point (OptionParser)
bin/ci                     Every quality gate in order, with a summary (like Rails' bin/ci)
lib/omarchy_translator.rb  Language tables, normalize, PROVIDERS registry (id => class)
lib/omarchy_translator/config.rb       Config: env-file settings, active provider, remembered choices
lib/omarchy_translator/providers/      Provider base (HTTP + errors), LLMTranslation, one file per provider
script/lint-qml            qmllint gate against the running shell's qs.* modules
script/test-qml            qmltestrunner gate (headless) for test/qml/tst_*.qml
script/qs-imports          Sourced by both: lays out the shell's qs.* modules (+ test stubs) in a temp dir
script/check-format        .editorconfig gate for the files RuboCop doesn't cover
test/                      Minitest: one *_test per provider, config_test, cli_test, normalize_test
test/support/fake_api.rb   Stdlib TCPServer standing in for a provider API (FakeAPI, FakeDeepL)
test/support/fake_claude.rb  Executable script standing in for the `claude` CLI (FakeClaude)
test/support/coverage.rb   SimpleCov setup (COVERAGE=1), also inside the CLI child processes
test/qml/                  QML TestCase files: PanelLogic unit tests, Panel and BarWidget component tests
test/qml/stubs/            Quickshell, Quickshell.Io (Process → FakeProcesses) and qs.Ui KeyboardPanel stand-ins
docs/HOW_IT_WORKS.md       QML/Quickshell primer + architecture walkthrough
```

## Runtime contract (keep stable — the QML depends on it)

- `omarchy-translate --json [--to LANG] [--from LANG|AUTO] [--provider ID] -- TEXT`
  → `{"ok":true,"text":"…","detectedSource":"EN","target":"PT-BR","provider":"deepl"}`
  or `{"ok":false,"error":"…"}` (exit 1), plus `"needsSetup":true` when the
  provider isn't configured. **Every failure path must still print one JSON
  object** — the popup shows `error` verbatim. `detectedSource` may be null.
- `--status` → `{"configured":bool,"provider":"…","providers":[{"id","label","configured","setupHint"}],
  "setupHint":"…","target":"…","source":"…","keyFile":"…"}` (`configured` and
  `setupHint` refer to the active provider).
- `--languages` → `{"targets":{code:name},"sources":{code:name}}`
- `--clipboard` reads `wl-paste`; `--notify` shows `omarchy-notification-send`
  and copies with `wl-copy`. Without TEXT it reads stdin.
- TEXT is normalized (`OmarchyTranslator.normalize`: line wraps joined, invisible
  chars removed, paragraphs kept) before it is sent, on every input path.
- Invalid options: usage on stderr, exit 2.

If you change any of these, update `Panel.qml` / `BarWidget.qml` and
`test/cli_test.rb` in the same change.

## Rules

- **Runtime Ruby is stdlib only.** The widget runs `bin/omarchy-translate`
  directly (no `bundle exec`), so `lib/` and `bin/` must not require gems.
  Gems in the `Gemfile` are dev tools only.
- **Never put secrets in this folder.** Settings live in
  `~/.config/omarchy/translator.env` (`DEEPL_AUTH_KEY`, `ANTHROPIC_API_KEY`,
  … — the full table is in README.md); the process environment overrides the
  file. Every HTTP provider has a `*_URL` override so tests can point it at `FakeAPI`;
  the Claude Code provider has `CLAUDE_CODE_BIN` for `FakeClaude` instead (CLI tests
  set it to a missing path so the developer's real `claude` is never run).
- **Providers**: subclass `Provider`, define `ID`, `LABEL`, `configured?`,
  `setup_hint`, `from_config` and `translate`, register the class in `PROVIDERS`,
  and keep the canonical (DeepL-style) language codes at the boundary: map them
  with `wire_code` on the way out and `canonical_source` on the way back. Add the
  new env vars to `PROVIDER_VARS` in `test/cli_test.rb`.
- **No symlinks inside the repo, and no `vendor/bundle`.**
  `omarchy plugin validate` rejects any symlink in a plugin folder. Install gems
  to the mise Ruby's gem path. (The repo itself *is* symlinked into
  `~/.config/omarchy/plugins/`, which is allowed.)
- **Plugin id** must not use the reserved `omarchy.*` namespace.
- **QML**: follow the first-party widgets. Use `qs.Commons` (`Style`, `Color`)
  and `qs.Ui` (`BarWidget`, `Panel`, `KeyboardPanel`, `TextField`, `Dropdown`,
  `PanelActionButton`, …) so the widget follows the user's theme. Never hardcode
  colors or font sizes. Build subprocess commands as **argv arrays**, never
  interpolated shell strings. The reference implementation is the weather widget
  at `/usr/share/omarchy/shell/plugins/panels/weather/`.
- **Popup logic goes in `PanelLogic.qml`**, not in `Panel.qml` functions: anything
  that computes a value from plain inputs (labels, options, hints, swap rules)
  is a pure function there, with a test in `test/qml/tst_panel_logic.qml`.
  `Panel.qml` keeps the state, bindings, `Process` calls and side effects.
  No `.js` files: the UI is QML only.
- **Behaviour of the popup and the bar pill** (what a key or click does, what
  argv reaches the CLI, how each reply is shown) is tested in
  `test/qml/tst_panel.qml` / `tst_bar_widget.qml`. They load the real QML with
  the real `qs.Commons` / `qs.Ui` controls; `test/qml/stubs` replaces only what
  needs the running shell: Quickshell's plugin (built into the `quickshell`
  binary, so `qmltestrunner` can't load it), `Process` (answered by
  `FakeProcesses.respond`) and the layer-shell `KeyboardPanel`. Find items by
  `objectName`; a hidden `TestCase` gets no mouse events, so keep `visible: true`.
  If the panel starts using another Quickshell type, add a stub for it.
  Layout (wrapping, sizes, theme) is still checked by eye after `mise run reload`.
- **JS style** (in `PanelLogic.qml` and QML handlers): `const`/`let`, arrow
  functions, template literals, `?.` and `??`. Qt's JS engine lacks some newer
  built-ins (e.g. `String.prototype.replaceAll`; use `replace(/…/g, …)`), so
  rely on `mise run test:qml` to confirm.
- **Ruby style**: RuboCop defaults (single quotes, `frozen_string_literal`),
  120-column lines. Raise `OmarchyTranslator::Error` with a user-facing message.
- **Tests hit a real socket, not mocks.** Use `FakeAPI` (or `FakeDeepL`) for anything HTTP,
  `FakeClaude` for the Claude Code CLI, and
  run the real executable through `Open3` for CLI behaviour. Tests must isolate
  `XDG_CONFIG_HOME` / `XDG_STATE_HOME`, and pass `desktop_env` (stub `wl-paste`,
  `wl-copy` and `omarchy-notification-send` first on `PATH`) to any run that uses
  `--clipboard` or `--notify`, which would otherwise read the real clipboard or pop a
  real desktop notification.

## Quality gates — run before finishing any change

```sh
bin/ci              # = mise run check: RuboCop, format, qmllint, gem audit, Minitest + coverage, QML tests, manifest
```

`bin/ci` runs every step even after a failure and ends with a summary;
`--fail-fast` stops at the first one, and a word filters steps (`bin/ci tests`).
Individually: `mise run lint` (`lint:fix` autocorrects), `mise run format`,
`mise run lint:qml`, `mise run audit`, `mise run test` (`test:coverage` with
coverage), `mise run test:qml`, `mise run validate`. First time: `mise run setup`.

Coverage has a floor in `test/support/coverage.rb` (line and branch). New code
needs tests that keep it there; raise the floor when coverage goes up, never
lower it. CLI tests must pass `CoverageSupport.env` to the child process, as
`run_cli` does, or the CLI's lines don't count.

`script/lint-qml` also lints `test/qml` (tests and stubs) with `--bare`, so the
stubs aren't shadowed by the real Quickshell; there every warning fails. For the
plugin's own QML it ignores `[missing-property]` on purpose: Omarchy's host
objects (`bar`, `Loader.item`) are dynamically typed, so qmllint can't see their
members (the first-party widgets produce the same warning). Any other category
(`unqualified`, `import`, `incompatible-type`, …) fails the gate. `qmlformat` is
**not** enforced — Omarchy's own QML doesn't follow its style; match the
surrounding code instead.

## Trying changes in the running desktop

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/local.translator   # once
omarchy plugin enable local.translator --section right      # once
mise run reload                                             # after every QML edit
omarchy-shell shell toggle local.translator                 # open/close the popup
quickshell log -i "$(ls -t /run/user/$UID/quickshell/by-id | head -1)" | grep -i translator
```

**There is no working hot reload for this setup.** The shell's file watcher
(`inotifywait -r`) does not follow the symlink into this repo, and even a
forced plugin reload (re-creating the link, or `omarchy-shell shell
rescanPlugins`) serves the *cached* `Panel.qml`, because it is loaded through a
`Loader`. `mise run reload` (`omarchy-restart-shell`) is the reliable way.
Ruby changes need no reload — the CLI is spawned fresh for every request.

To exercise the popup end to end without a real key, point a provider at the
fake server: run a `FakeDeepL` in the background and put `DEEPL_AUTH_KEY=anything`
plus `DEEPL_API_URL=<its url>` in `~/.config/omarchy/translator.env` — and
delete that file afterwards if the user has no real key there.

Ignore the pre-existing `IpcHandler … another handler is registered` warnings
from built-in widgets.
