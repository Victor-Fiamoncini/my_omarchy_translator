import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// The real popup (Panel.qml) driven like a user: keys into the input, clicks
// on the provider chips and buttons. Quickshell is stubbed (test/qml/stubs):
// FakeProcesses answers the CLI calls, so these tests check what the popup
// sends and how it shows each kind of reply. Run by script/test-qml.
TestCase {
  id: testCase
  name: "Panel"
  width: 640
  height: 800
  // TestCase is hidden by default, and hidden items get no mouse events.
  visible: true
  when: windowShown

  readonly property string cli: "/fake/bin/omarchy-translate"

  readonly property var status: ({
    configured: true, provider: "deepl", setupHint: "", target: "PT-BR", source: "EN", keyFile: "/fake/translator.env",
    providers: [
      { id: "deepl", label: "DeepL", configured: true, setupHint: "Add DEEPL_AUTH_KEY" },
      { id: "gemini", label: "Gemini", configured: false, setupHint: "No Gemini API key. Add GEMINI_API_KEY" }
    ]
  })

  readonly property var languages: ({
    targets: { "DE": "German", "EN-US": "English (US)", "PT-BR": "Portuguese (Brazil)" },
    sources: { "DE": "German", "EN": "English", "PT": "Portuguese", "EN-US": "English (US)", "PT-BR": "Portuguese (Brazil)" }
  })

  // What `--json` answers; a test may replace it (null = the CLI hangs).
  property var reply: null

  property var panel: null

  function respond(argv) {
    if (argv[0] !== cli) return null
    if (argv[1] === "--status") return JSON.stringify(status)
    if (argv[1] === "--languages") return JSON.stringify(languages)
    const r = reply ? reply(argv) : null
    return r === null ? null : JSON.stringify(r)
  }

  function translated(text) {
    return { ok: true, text, detectedSource: "EN", target: "PT-BR", provider: "deepl" }
  }

  function translateCommands() {
    return FakeProcesses.commands.filter(argv => argv[1] === "--json")
  }

  function child(name) {
    const item = findChild(panel, name)
    verify(item, `no item named ${name}`)
    return item
  }

  function type(text) {
    for (const ch of text) keyClick(ch)
  }

  function init() {
    FakeProcesses.reset()
    Quickshell.reset()
    reply = argv => translated("Olá")
    FakeProcesses.respond = argv => respond(argv)
    panel = createTemporaryObject(Qt.createComponent(Qt.resolvedUrl("../../Panel.qml")), testCase, { cli })
    verify(panel, "Panel.qml did not load")
    panel.openFromHotkey()
    tryVerify(() => panel.targetOptions.length === 3 && panel.providers.length === 2)
    tryVerify(() => child("inputField").activeFocus)
  }

  function test_opening_asks_for_status_and_languages() {
    compare(FakeProcesses.commands.filter(argv => argv[0] === cli),
            [[cli, "--status"], [cli, "--languages"]])
    compare(panel.provider, "deepl")
    verify(child("provider-gemini"))
  }

  function test_enter_translates_what_was_typed() {
    type("Hello")
    keyClick(Qt.Key_Return)

    tryCompare(child("resultText"), "text", "Olá")
    compare(translateCommands(),
            [[cli, "--json", "--to", "PT-BR", "--from", "EN", "--provider", "deepl", "--", "Hello"]])
  }

  function test_shift_enter_adds_a_line_instead_of_translating() {
    type("Hello")
    keyClick(Qt.Key_Return, Qt.ShiftModifier)
    type("there")

    compare(child("inputField").text, "Hello\nthere")
    compare(translateCommands(), [])
  }

  function test_shows_translating_while_the_cli_runs() {
    reply = null
    type("Hello")
    keyClick(Qt.Key_Return)

    compare(child("resultText").text, "Translating…")
    verify(panel.busy)
  }

  function test_error_reply_is_shown_verbatim() {
    reply = argv => ({ ok: false, error: "DeepL character quota exceeded" })
    type("Hello")
    keyClick(Qt.Key_Return)

    tryCompare(child("resultText"), "text", "DeepL character quota exceeded")
    verify(!child("copyButton").visible)
  }

  function test_needs_setup_reply_marks_the_provider_unconfigured() {
    reply = argv => ({ ok: false, error: "No DeepL API key", needsSetup: true })
    type("Hello")
    keyClick(Qt.Key_Return)

    tryCompare(panel, "configured", false)
    compare(child("resultText").text, "No DeepL API key")
  }

  function test_unconfigured_provider_shows_its_setup_hint_without_translating() {
    type("Hello")
    mouseClick(child("provider-gemini"))

    compare(panel.provider, "gemini")
    compare(child("resultText").text, "No Gemini API key. Add GEMINI_API_KEY")
    compare(translateCommands(), [])
  }

  function test_configured_provider_translates_right_away() {
    type("Hello")
    mouseClick(child("provider-gemini"))
    mouseClick(child("provider-deepl"))

    tryCompare(child("resultText"), "text", "Olá")
    compare(translateCommands().length, 1)
  }

  function test_swap_moves_the_translation_into_the_input() {
    type("Hello")
    keyClick(Qt.Key_Return)
    tryCompare(child("resultText"), "text", "Olá")
    reply = argv => translated("Hello")

    mouseClick(child("swapButton"))

    compare(child("inputField").text, "Olá")
    compare([panel.sourceLang, panel.targetLang], ["PT-BR", "EN-US"])
    tryCompare(child("resultText"), "text", "Hello")
    compare(translateCommands()[1].slice(2, 6), ["--to", "EN-US", "--from", "PT-BR"])
  }

  function test_ctrl_enter_copies_the_translation() {
    type("Hello")
    keyClick(Qt.Key_Return)
    tryCompare(child("resultText"), "text", "Olá")

    keyClick(Qt.Key_Return, Qt.ControlModifier)

    compare(Quickshell.detached, [["wl-copy", "--", "Olá"]])
    compare(child("footer").text, "Copied to clipboard")
  }

  function test_footer_names_the_provider_used() {
    type("Hello")
    keyClick(Qt.Key_Return)

    tryVerify(() => child("footer").text.startsWith("via DeepL · "))
  }

  function test_escape_closes_the_popup() {
    keyClick(Qt.Key_Escape)

    verify(!panel.opened)
  }
}
