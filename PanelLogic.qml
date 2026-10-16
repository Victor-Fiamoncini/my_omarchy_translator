import QtQuick

// Pure helpers behind Panel.qml (declared there as `PanelLogic { id: logic }`):
// no side effects, so test/qml/tst_panel_logic.qml can exercise them with qmltestrunner.
QtObject {
  // Regional variant to pick when a bare source code becomes the target.
  readonly property var preferredVariants: ({ EN: "EN-US", PT: "PT-BR", ZH: "ZH-HANS", ES: "ES" })

  readonly property var keyHints: ["Enter translate", "Shift+Enter newline", "Ctrl+Enter copy", "Esc close"]

  // One JSON object from the CLI's stdout, or null.
  function parseJson(text) {
    try {
      return JSON.parse(String(text ?? "").trim())
    } catch (e) {
      return null
    }
  }

  // {code: name} as dropdown options ("Portuguese (Brazil)  PT-BR"), by label.
  function toOptions(map) {
    return Object.entries(map ?? {})
      .map(([code, name]) => ({ value: code, label: `${name}  ${code}` }))
      .sort((a, b) => a.label.localeCompare(b.label))
  }

  // Every provider is offered, so the others can be discovered. The ones
  // without settings are dimmed in the picker, and picking one shows its setup hint.
  function toProviderOptions(providers) {
    return (providers ?? []).map(p => {
      const configured = p.configured === true
      const tooltip = configured ? `Translate with ${p.label}` : `${p.label} isn't set up yet`
      return { value: p.id, label: p.label, configured, tooltip }
    })
  }

  // The --status entry for a provider id, or null.
  function findProvider(providers, id) {
    return (providers ?? []).find(p => p.id === id) ?? null
  }

  function providerLabel(options, id) {
    return (options ?? []).find(o => o.value === id)?.label ?? ""
  }

  // The target option for a bare source code: exact code, preferred variant,
  // else the first variant of that language; "" if there is none.
  function matchTarget(base, targetOptions) {
    const values = (targetOptions ?? []).map(o => o.value)
    const preferred = preferredVariants[base]
    return values.find(v => v === base || v === preferred)
      ?? values.find(v => v.split("-")[0] === base)
      ?? ""
  }

  // The languages after a swap, as { source, target }, or null when there is no
  // concrete source (auto-detect with nothing detected) or no matching target.
  // Regional variants carry over both ways (every target is also a source).
  function swappedLanguages(sourceLang, detectedSource, targetLang, targetOptions) {
    const from = sourceLang || detectedSource
    if (!from) return null
    const target = matchTarget(from, targetOptions)
    if (!target) return null
    return { source: targetLang, target }
  }

  // The input after a swap: the translation moves into it only while it still
  // translates what is typed; otherwise the user's newer text stays.
  function swappedInput(inputText, resultText, resultInput) {
    return resultText && inputText.trim() === resultInput ? resultText : inputText
  }

  // The auto-detect option's label: names what was detected while a result is
  // shown, but the option stays auto, so the next text is detected again.
  function autoSourceLabel(detectedSource, sourceNames, hasResult) {
    if (!hasResult || !detectedSource) return "Auto-detect"
    return `Auto · ${sourceNames?.[detectedSource] ?? detectedSource}`
  }

  // Footer line: the provider used (when there is a choice), then key hints,
  // joined by " · ". Spaces inside a hint are non-breaking so a narrow panel
  // wraps between hints, not within one.
  function footerHints(resultProvider, hasResult, providerCount) {
    const via = hasResult && resultProvider && providerCount > 1 ? [`via ${resultProvider}`] : []
    return [...via, ...keyHints].map(h => h.replace(/ /g, " ")).join(" · ")
  }
}
