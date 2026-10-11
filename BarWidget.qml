import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar pill for the translator. Left click toggles the popup, right click
// translates the clipboard straight into a notification (and copies the
// result), middle click OCRs a screen region and translates it.
BarWidget {
  id: root
  moduleName: "local.translator"

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-translate")).replace(/^file:\/\//, ""))

  function injectPanel() {
    const target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("cli" in target) target.cli = root.cli
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Run the CLI through a login shell with argv kept literal, the same way
  // Util.execArgv does, so PATH (mise ruby, wl-copy) matches a terminal.
  function runCli(args) {
    Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash", root.cli].concat(args))
  }

  // Same slurp + grim + tesseract pipeline as omarchy-capture-text, but piped
  // into the CLI so a cancelled selection never translates a stale clipboard.
  function translateScreenRegion() {
    Quickshell.execDetached(["bash", "-lc",
      'sel=$(slurp 2>/dev/null) || exit 0; '
      + 'grim -g "$sel" - | tesseract stdin stdout --oem 1 --psm 6 -l "${OMARCHY_OCR_LANGS:-eng}" --dpi 300 2>/dev/null '
      + '| "$0" --notify', root.cli])
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗊"
    slotSize: Style.bar.statusSlot
    tooltipText: root.opened ? "" : "Translate · right: clipboard · middle: screen"

    onPressed: b => {
      if (!root.bar) return
      if (b === Qt.RightButton) root.runCli(["--clipboard", "--notify"])
      else if (b === Qt.MiddleButton) root.translateScreenRegion()
      else root.togglePanel()
    }
  }
}
