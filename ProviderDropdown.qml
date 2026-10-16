pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Provider picker. qs.Ui's Dropdown only renders text, so this mirrors its
// trigger, popup and keys (same tokens, so it matches the language dropdowns)
// and adds each provider's logo. Providers without settings are dimmed and
// marked "not set up", but stay selectable: picking one shows its setup hint.
//
// `options` are PanelLogic.toProviderOptions() rows: { value, label, configured }.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true

  readonly property bool popupOpen: popup.opened
  readonly property var current: root.options.find(o => o.value === root.value) ?? null
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      objectName: "providerTrigger"
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered
      readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
      }

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          root.toggle()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close()
          event.accepted = true
        }
      }

      Row {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        spacing: Style.spacing.controlGap

        ProviderLogo {
          id: triggerLogo
          anchors.verticalCenter: parent.verticalCenter
          provider: root.value
          size: Style.font.body
          color: root.foreground
        }

        Text {
          objectName: "providerTriggerLabel"
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (triggerLogo.visible ? triggerLogo.width + parent.spacing : 0)
          textFormat: Text.PlainText
          text: root.current?.label ?? root.value
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          root.toggle()
        }
      }

      Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        width: trigger.width
        implicitHeight: Math.min(root.options.length * root.popupRowHeight + Math.max(0, root.options.length - 1) * Style.spacing.labelGap + Style.spacing.xxs,
                                 root.popupRowHeight * 8 + 7 * Style.spacing.labelGap + Style.spacing.xxs)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          optionList.currentIndex = Math.max(0, root.options.findIndex(o => o.value === root.value))
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          spacing: Style.spacing.labelGap

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
              popup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(root.options.length - 1, optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              optionList.selectCurrent()
              event.accepted = true
            }
          }
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length) return
            const v = root.options[currentIndex].value
            root.value = v
            root.changed(v)
            popup.close()
          }

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: row.index === optionList.currentIndex
            readonly property color contentColor: row.isCurrent
                ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
            objectName: `provider-${row.modelData.value}`
            width: optionList.width
            height: root.popupRowHeight
            color: row.isCurrent ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
                                   + (setupNote.visible ? setupNote.implicitWidth + Style.spacing.controlGap : 0)
              spacing: Style.spacing.controlGap
              opacity: row.modelData.configured ? 1 : 0.5

              ProviderLogo {
                id: rowLogo
                anchors.verticalCenter: parent.verticalCenter
                provider: row.modelData.value
                size: Style.font.body
                color: row.contentColor
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (rowLogo.visible ? rowLogo.width + parent.spacing : 0)
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.contentColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: row.modelData.value === root.value
                elide: Text.ElideRight
              }
            }

            Text {
              id: setupNote
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.spacing.controlPaddingX
              visible: !row.modelData.configured
              textFormat: Text.PlainText
              text: "not set up"
              color: Qt.darker(row.contentColor, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = row.index
              onClicked: {
                optionList.currentIndex = row.index
                optionList.selectCurrent()
              }
            }
          }
        }
      }
    }
  }
}
