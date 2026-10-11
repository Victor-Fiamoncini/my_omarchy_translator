import QtQuick
import QtTest
import "../../PanelLogic.js" as Logic

// The popup's pure logic (PanelLogic.js), run by script/test-qml.
TestCase {
  name: "PanelLogic"

  readonly property var targets: [
    { value: "DE", label: "German  DE" },
    { value: "EN-GB", label: "English (UK)  EN-GB" },
    { value: "EN-US", label: "English (US)  EN-US" },
    { value: "PT-BR", label: "Portuguese (Brazil)  PT-BR" },
    { value: "PT-PT", label: "Portuguese (Portugal)  PT-PT" },
    { value: "ZH-HANT", label: "Chinese (Traditional)  ZH-HANT" }
  ]

  function test_parse_json() {
    compare(Logic.parseJson(' {"ok":true}\n'), { ok: true })
    compare(Logic.parseJson("nope"), null)
    compare(Logic.parseJson(""), null)
    compare(Logic.parseJson(undefined), null)
  }

  function test_to_options_sorts_by_label() {
    compare(Logic.toOptions({ PT: "Portuguese", DE: "German" }),
            [{ value: "DE", label: "German  DE" }, { value: "PT", label: "Portuguese  PT" }])
    compare(Logic.toOptions({}), [])
  }

  readonly property var providers: [
    { id: "deepl", label: "DeepL", configured: false, setupHint: "Add DEEPL_AUTH_KEY" },
    { id: "claude", label: "Claude", configured: true, setupHint: "Add ANTHROPIC_API_KEY" }
  ]

  function test_provider_options_list_every_provider_and_flag_unset_ones() {
    compare(Logic.toProviderOptions(providers), [
      { value: "deepl", label: "DeepL", configured: false, tooltip: "DeepL isn't set up yet" },
      { value: "claude", label: "Claude", configured: true, tooltip: "Translate with Claude" }
    ])
    compare(Logic.toProviderOptions(undefined), [])
  }

  function test_find_provider() {
    compare(Logic.findProvider(providers, "deepl").setupHint, "Add DEEPL_AUTH_KEY")
    compare(Logic.findProvider(providers, "nope"), null)
    compare(Logic.findProvider(undefined, "deepl"), null)
  }

  function test_provider_label() {
    const options = [{ value: "claude-code", label: "Claude Code" }]
    compare(Logic.providerLabel(options, "claude-code"), "Claude Code")
    compare(Logic.providerLabel(options, "deepl"), "")
  }

  function test_match_target_prefers_exact_then_preferred_then_first_variant() {
    compare(Logic.matchTarget("DE", targets), "DE")
    compare(Logic.matchTarget("EN", targets), "EN-US")
    compare(Logic.matchTarget("PT", targets), "PT-BR")
    compare(Logic.matchTarget("ZH", targets), "ZH-HANT")
    compare(Logic.matchTarget("JA", targets), "")
  }

  function test_swap_uses_chosen_or_detected_source() {
    compare(Logic.swappedLanguages("DE", "", "EN-US", targets), { source: "EN-US", target: "DE" })
    compare(Logic.swappedLanguages("", "PT", "EN-US", targets), { source: "EN-US", target: "PT-BR" })
    compare(Logic.swappedLanguages("PT-BR", "", "DE", targets), { source: "DE", target: "PT-BR" })
  }

  function test_swap_needs_a_source_with_a_target() {
    compare(Logic.swappedLanguages("", "", "EN-US", targets), null)
    compare(Logic.swappedLanguages("JA", "", "EN-US", targets), null)
  }

  function test_swap_moves_the_result_into_the_input_it_translates() {
    compare(Logic.swappedInput("Hello\n", "Olá", "Hello"), "Olá")
  }

  function test_swap_keeps_text_typed_after_the_result() {
    compare(Logic.swappedInput("Good morning", "Olá", "Hello"), "Good morning")
    compare(Logic.swappedInput("Good morning", "", ""), "Good morning")
  }

  function test_auto_source_label_names_the_detected_language() {
    const names = { PT: "Portuguese" }
    compare(Logic.autoSourceLabel("PT", names, true), "Auto · Portuguese")
    compare(Logic.autoSourceLabel("XX", names, true), "Auto · XX")
  }

  function test_auto_source_label_without_a_result() {
    compare(Logic.autoSourceLabel("PT", { PT: "Portuguese" }, false), "Auto-detect")
    compare(Logic.autoSourceLabel("", {}, true), "Auto-detect")
    compare(Logic.autoSourceLabel("PT", undefined, true), "Auto · PT")
  }

  function test_footer_hints_only_break_between_hints() {
    const footer = Logic.footerHints("", false, 1)
    compare(footer.split(" · ").length, 4)
    compare(footer.split(" · ")[0], "Enter\u00a0translate")
    verify(footer.replace(/ · /g, "").indexOf(" ") === -1, "a plain space inside a hint")
  }

  function test_footer_names_the_provider_only_when_there_is_a_choice() {
    compare(Logic.footerHints("Claude Code", true, 2).split(" · ")[0], "via\u00a0Claude\u00a0Code")
    compare(Logic.footerHints("Claude Code", true, 1).indexOf("via"), -1)
    compare(Logic.footerHints("Claude Code", false, 2).indexOf("via"), -1)
    compare(Logic.footerHints("", true, 2).indexOf("via"), -1)
  }
}
