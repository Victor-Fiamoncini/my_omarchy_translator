pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.translator"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property string cli: ""

  // Filled from `omarchy-translate --status` / `--languages`.
  property bool configured: true
  property string keyFile: "~/.config/omarchy/translator.env"
  property string targetLang: "PT-BR"
  property string sourceLang: "EN"
  property string provider: ""
  property var providers: []
  property var providerOptions: []
  property string setupHint: ""
  property var targetOptions: []
  property var sourceLanguageOptions: []
  property var sourceNames: ({})
  readonly property var sourceOptions: [{
    value: "", label: logic.autoSourceLabel(root.detectedSource, root.sourceNames, root.resultText !== "")
  }].concat(root.sourceLanguageOptions)

  property string resultText: ""
  // The (trimmed) input that resultText translates, and the one in flight.
  property string resultInput: ""
  property string requestInput: ""
  property string detectedSource: ""
  property string resultProvider: ""
  property string errorText: ""
  property bool busy: false
  property bool copied: false
  // A language change while a request is in flight re-runs it afterwards.
  property bool pendingTranslate: false

  readonly property bool dropdownOpen: sourceDropdown.popupOpen || targetDropdown.popupOpen

  function open() { openFromHotkey() }

  function openFromHotkey() {
    root.controller.show()
    statusProc.running = true
    if (root.targetOptions.length === 0) languagesProc.running = true
    Qt.callLater(() => {
      inputField.forceActiveFocus()
      inputField.selectAll()
    })
  }

  function close() {
    sourceDropdown.close()
    targetDropdown.close()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  PanelLogic {
    id: logic
  }

  function translate() {
    const text = inputField.text.trim()
    if (text === "" || root.cli === "") return
    if (root.busy) {
      root.pendingTranslate = true
      return
    }
    root.busy = true
    root.pendingTranslate = false
    root.errorText = ""
    root.copied = false
    root.requestInput = text
    const command = [root.cli, "--json", "--to", root.targetLang, "--from", root.sourceLang || "AUTO"]
    if (root.provider !== "") command.push("--provider", root.provider)
    translateProc.command = command.concat(["--", text])
    translateProc.running = true
    watchdog.restart()
  }

  function finishTranslate(response) {
    watchdog.stop()
    root.busy = false
    if (!response) {
      root.errorText = "Translator returned no output"
    } else if (response.ok) {
      // Only the provider still selected is known to work: a reply that lands after
      // switching to an unset provider must not hide that provider's setup hint.
      if (response.provider === root.provider) root.configured = true
      root.resultText = response.text
      root.resultInput = root.requestInput
      root.detectedSource = response.detectedSource || ""
      root.resultProvider = logic.providerLabel(root.providerOptions, response.provider)
    } else {
      root.errorText = response.error
      if (response.needsSetup === true) root.configured = false
    }
    if (root.pendingTranslate) Qt.callLater(root.translate)
  }

  // A provider without settings shows its setup hint instead of translating.
  function selectProvider(id) {
    const p = logic.findProvider(root.providers, id)
    root.provider = id
    root.configured = p?.configured !== false
    root.setupHint = p?.setupHint ?? ""
    root.errorText = ""
    if (root.configured) root.translate()
  }

  // Swapping needs a concrete source; with auto-detect, use what the provider detected.
  function swapLanguages() {
    const swapped = logic.swappedLanguages(root.sourceLang, root.detectedSource, root.targetLang, root.targetOptions)
    if (!swapped) return
    root.sourceLang = swapped.source
    root.targetLang = swapped.target
    const input = logic.swappedInput(inputField.text, root.resultText, root.resultInput)
    if (input !== inputField.text) inputField.text = input
    root.resultText = ""
    root.detectedSource = ""
    root.translate()
  }

  function copyResult() {
    if (root.resultText === "") return
    Quickshell.execDetached(["wl-copy", "--", root.resultText])
    root.copied = true
    copiedTimer.restart()
  }

  Process {
    id: statusProc
    command: [root.cli, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const s = logic.parseJson(text)
        if (!s) return
        root.configured = s.configured === true
        root.keyFile = s.keyFile || root.keyFile
        root.setupHint = s.setupHint || ""
        root.provider = s.provider || ""
        root.providers = s.providers || []
        root.providerOptions = logic.toProviderOptions(root.providers)
        root.targetLang = s.target || root.targetLang
        root.sourceLang = s.source ?? root.sourceLang
      }
    }
  }

  Process {
    id: languagesProc
    command: [root.cli, "--languages"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const l = logic.parseJson(text)
        if (!l) return
        root.targetOptions = logic.toOptions(l.targets)
        root.sourceNames = l.sources || {}
        root.sourceLanguageOptions = logic.toOptions(l.sources)
      }
    }
  }

  Process {
    id: translateProc
    stdout: StdioCollector {
      waitForEnd: true
      // Stopping a timed-out request still ends its stream; the watchdog already answered it.
      onStreamFinished: if (root.busy) root.finishTranslate(logic.parseJson(text))
    }
  }

  // Providers give up on their own (HTTP: 10s, 30s for LLMs, each for connect
  // and read; Claude Code CLI: 60s). If the process still hasn't answered (or
  // never started), stop showing "Translating…".
  Timer {
    id: watchdog
    interval: 65000
    // Answer first (busy = false), then stop the process: its stream may end
    // right away, and onStreamFinished ignores it once nothing is busy.
    onTriggered: {
      root.pendingTranslate = false
      root.finishTranslate({ ok: false, error: "Translation timed out" })
      translateProc.running = false
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.copied = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: inputField
    contentWidth: panel.fittedContentWidth(Style.space(480))
    // Leave room below the language row for a dropdown's 8-row popup.
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, Style.space(380)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: inputField.activeFocus || root.dropdownOpen
      onCloseRequested: root.close()
      onTabRequested: direction => root.switchPanel(direction)

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // Provider picker. qs.Ui's ButtonGroup only takes font glyphs as icons,
        // so each chip is its Button (themed fill, border, tooltip) around a
        // logo + name; providers without settings are dimmed.
        Row {
          id: providerRow
          width: parent.width
          spacing: Style.space(8)
          visible: root.providerOptions.length > 1

          Repeater {
            model: root.providerOptions

            delegate: Button {
              id: chip
              required property var modelData
              readonly property color contentColor: chip.selected
                  ? Style.selectedStateColor(root.barForeground, Color.accent) : root.barForeground
              width: (providerRow.width - providerRow.spacing * (root.providerOptions.length - 1))
                     / root.providerOptions.length
              implicitHeight: Style.spacing.controlHeight
              bordered: true
              selected: chip.modelData.value === root.provider
              tooltipText: chip.modelData.tooltip
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.selectProvider(chip.modelData.value)

              Row {
                anchors.centerIn: parent
                spacing: Style.spacing.controlGap
                opacity: chip.modelData.configured ? 1 : 0.5

                ProviderLogo {
                  id: logo
                  anchors.verticalCenter: parent.verticalCenter
                  provider: chip.modelData.value
                  size: Style.font.body
                  color: chip.contentColor
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, chip.width - logo.width - Style.spacing.controlPaddingX * 3)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: chip.modelData.label
                  color: chip.contentColor
                  font.family: chip.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: chip.selected
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Dropdown {
            id: sourceDropdown
            width: (parent.width - swapButton.width - parent.spacing * 2) / 2
            showLabel: false
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            options: root.sourceOptions
            // Dropdown assigns its own `value` on selection, which would break a plain
            // `value:` binding; a Binding object survives that and keeps swaps visible.
            Binding on value { value: root.sourceLang }
            onChanged: v => { root.sourceLang = v; root.translate() }
          }

          PanelActionButton {
            id: swapButton
            anchors.verticalCenter: sourceDropdown.verticalCenter
            iconText: "󰓡"
            tooltipText: "Swap languages"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            enabled: root.sourceLang !== "" || root.detectedSource !== ""
            onClicked: root.swapLanguages()
          }

          Dropdown {
            id: targetDropdown
            width: sourceDropdown.width
            showLabel: false
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            options: root.targetOptions
            Binding on value { value: root.targetLang }
            onChanged: v => { root.targetLang = v; root.translate() }
          }
        }

        // Multi-line input. qs.Ui only ships a single-line TextField, so this
        // borrows its styling: the border lives on the ScrollView, so it stays
        // put while long text scrolls inside. The CLI joins the line wraps.
        ScrollView {
          id: inputScroll
          readonly property var borderSpec: Border.controlSpec(inputField.activeFocus ? "focus"
              : (inputField.hovered ? "hover-cursor" : "normal"), root.barForeground, Color.accent)
          readonly property real chrome: inputField.topPadding + inputField.bottomPadding
          width: parent.width
          height: Math.min(Math.max(inputField.implicitHeight, inputMetrics.lineSpacing * 6 + chrome),
                           inputMetrics.lineSpacing * 14 + chrome)
          contentWidth: availableWidth
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

          background: BorderSurface {
            color: Style.controlFill(inputField.activeFocus, inputField.hovered, root.barForeground, Color.accent)
            borderSpec: inputScroll.borderSpec
            radius: Style.cornerRadius
          }

          TextArea {
            id: inputField
            placeholderText: "Type or paste text · Enter to translate"
            wrapMode: TextArea.Wrap
            textFormat: TextEdit.PlainText
            color: root.barForeground
            selectionColor: Style.selectionFillFor(root.barForeground, Color.accent)
            selectedTextColor: root.barForeground
            placeholderTextColor: Qt.darker(root.barForeground, 1.6)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            leftPadding: Style.spacing.controlPaddingX + Border.left(inputScroll.borderSpec)
            rightPadding: Style.spacing.controlPaddingX + Border.right(inputScroll.borderSpec)
            topPadding: Style.spacing.inputPaddingY + Border.top(inputScroll.borderSpec)
            bottomPadding: Style.spacing.inputPaddingY + Border.bottom(inputScroll.borderSpec)
            background: null

            Keys.onPressed: event => {
              if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Shift+Enter falls through to TextArea and inserts a newline.
                if (event.modifiers & Qt.ShiftModifier) return
                if (event.modifiers & Qt.ControlModifier) root.copyResult()
                else root.translate()
                event.accepted = true
              }
            }
          }
        }

        FontMetrics {
          id: inputMetrics
          font: inputField.font
        }

        // Result card. The text stays selectable for partial copies; the
        // button (or Ctrl+Enter) copies all of it.
        Rectangle {
          width: parent.width
          height: Math.max(Style.space(96), resultEdit.implicitHeight + Style.space(24))
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.barForeground, Color.accent)

          TextEdit {
            id: resultEdit
            anchors.fill: parent
            anchors.margins: Style.space(12)
            anchors.rightMargin: copyButton.width + Style.space(16)
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.errorText !== "" ? Color.urgent : root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            text: root.busy ? "Translating…"
                : root.errorText !== "" ? root.errorText
                : !root.configured ? (root.setupHint || "Add a provider API key to " + root.keyFile)
                : root.resultText
            opacity: root.busy ? 0.6 : 1
          }

          PanelActionButton {
            id: copyButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(8)
            visible: root.resultText !== "" && !root.busy && root.errorText === ""
            iconText: root.copied ? "󰄬" : "󰆏"
            tooltipText: "Copy translation"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.copyResult()
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignRight
          // Wraps only between hints: each hint's own spaces are non-breaking.
          wrapMode: Text.Wrap
          color: Qt.darker(root.barForeground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          text: root.copied ? "Copied to clipboard"
              : logic.footerHints(root.resultProvider, root.resultText !== "", root.providerOptions.length)
        }
      }
    }
  }
}
