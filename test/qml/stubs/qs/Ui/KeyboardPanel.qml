import QtQuick

// Test stand-in for qs.Ui.KeyboardPanel, which is a Wayland layer-shell
// PanelWindow: here the content is a plain Item, shown while `open`.
Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 280
  property int contentHeight: 200

  default property alias contentItem: holder.children

  function fittedContentWidth(width, cap) { return width }
  function fittedContentHeight(implicitHeight, cap) { return implicitHeight }
  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  visible: open
  width: contentWidth
  height: contentHeight

  Item {
    id: holder
    anchors.fill: parent
  }
}
