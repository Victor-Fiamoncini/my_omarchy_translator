import QtQuick
import QtTest
import "../.."

// The popup's pure logic (PanelLogic.qml), run by script/test-qml.
TestCase {
  name: "PanelLogic"

  PanelLogic {
    id: logic
  }

  readonly property var targets: [
    { value: "DE", label: "German  DE" },
    { value: "EN-GB", label: "English (UK)  EN-GB" },
    { value: "EN-US", label: "English (US)  EN-US" },
    { value: "PT-BR", label: "Portuguese (Brazil)  PT-BR" },
    { value: "PT-PT", label: "Portuguese (Portugal)  PT-PT" },
    { value: "ZH-HANT", label: "Chinese (Traditional)  ZH-HANT" }
  ]

  function test_parse_json() {
    compare(logic.parseJson(' {"ok":true}\n'), { ok: true })
    compare(logic.parseJson("nope"), null)
    compare(logic.parseJson(""), null)
    compare(logic.parseJson(undefined), null)
  }

  function test_to_options_sorts_by_label() {
    compare(logic.toOptions({ PT: "Portuguese", DE: "German" }),
            [{ value: "DE", label: "German  DE" }, { value: "PT", label: "Portuguese  PT" }])
    compare(logic.toOptions({}), [])
  }

  readonly property var providers: [
    { id: "deepl", label: "DeepL", configured: false, setupHint: "Add DEEPL_AUTH_KEY" },
    { id: "claude", label: "Claude", configured: true, setupHint: "Add ANTHROPIC_API_KEY" }
  ]

  function test_provider_options_list_every_provider_and_flag_unset_ones() {
    compare(logic.toProviderOptions(providers), [
      { value: "claude", label: "Claude", configured: true },
      { value: "deepl", label: "DeepL", configured: false }
    ])
    compare(logic.toProviderOptions(undefined), [])
  }

  function test_provider_options_put_set_up_ones_first_in_status_order() {
    const status = ["a", "b", "c", "d"].map((id, i) => ({ id, label: id, configured: i % 2 === 1 }))
    compare(logic.toProviderOptions(status).map(o => o.value), ["b", "d", "a", "c"])
  }

  function test_find_provider() {
    compare(logic.findProvider(providers, "deepl").setupHint, "Add DEEPL_AUTH_KEY")
    compare(logic.findProvider(providers, "nope"), null)
    compare(logic.findProvider(undefined, "deepl"), null)
  }

  function test_provider_label() {
    const options = [{ value: "claude-code", label: "Claude Code" }]
    compare(logic.providerLabel(options, "claude-code"), "Claude Code")
    compare(logic.providerLabel(options, "deepl"), "")
  }

  function test_match_target_prefers_exact_then_preferred_then_first_variant() {
    compare(logic.matchTarget("DE", targets), "DE")
    compare(logic.matchTarget("EN", targets), "EN-US")
    compare(logic.matchTarget("PT", targets), "PT-BR")
    compare(logic.matchTarget("ZH", targets), "ZH-HANT")
    compare(logic.matchTarget("JA", targets), "")
  }

  function test_swap_uses_chosen_or_detected_source() {
    compare(logic.swappedLanguages("DE", "", "EN-US", targets), { source: "EN-US", target: "DE" })
    compare(logic.swappedLanguages("", "PT", "EN-US", targets), { source: "EN-US", target: "PT-BR" })
    compare(logic.swappedLanguages("PT-BR", "", "DE", targets), { source: "DE", target: "PT-BR" })
  }

  function test_swap_needs_a_source_with_a_target() {
    compare(logic.swappedLanguages("", "", "EN-US", targets), null)
    compare(logic.swappedLanguages("JA", "", "EN-US", targets), null)
  }

  function test_swap_moves_the_result_into_the_input_it_translates() {
    compare(logic.swappedInput("Hello\n", "Olá", "Hello"), "Olá")
  }

  function test_swap_keeps_text_typed_after_the_result() {
    compare(logic.swappedInput("Good morning", "Olá", "Hello"), "Good morning")
    compare(logic.swappedInput("Good morning", "", ""), "Good morning")
  }

  function test_auto_source_label_names_the_detected_language() {
    const names = { PT: "Portuguese" }
    compare(logic.autoSourceLabel("PT", names, true), "Auto · Portuguese")
    compare(logic.autoSourceLabel("XX", names, true), "Auto · XX")
  }

  function test_auto_source_label_without_a_result() {
    compare(logic.autoSourceLabel("PT", { PT: "Portuguese" }, false), "Auto-detect")
    compare(logic.autoSourceLabel("", {}, true), "Auto-detect")
    compare(logic.autoSourceLabel("PT", undefined, true), "Auto · PT")
  }

  function test_footer_hints_only_break_between_hints() {
    const footer = logic.footerHints("", false, 1)
    compare(footer.split(" · ").length, 4)
    compare(footer.split(" · ")[0], "Enter\u00a0translate")
    verify(footer.replace(/ · /g, "").indexOf(" ") === -1, "a plain space inside a hint")
  }

  function test_footer_names_the_provider_only_when_there_is_a_choice() {
    compare(logic.footerHints("Claude Code", true, 2).split(" · ")[0], "via\u00a0Claude\u00a0Code")
    compare(logic.footerHints("Claude Code", true, 1).indexOf("via"), -1)
    compare(logic.footerHints("Claude Code", false, 2).indexOf("via"), -1)
    compare(logic.footerHints("", true, 2).indexOf("via"), -1)
  }
}
