import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs
import qs.components
import qs.settings

PanelWindow {
    id: root

    required property PanelWindow barWindow
    required property Item anchorItem
    required property bool opened
    signal dismissed
    signal exited

    readonly property alias progress: entrance.progress
    PopoverMotion {
        id: entrance
        opened: root.opened
        origin: Theme.state.barAt === "top" && root.anchorItem ? root.triggerRect : null
    }
    function checkExit() { if (!opened && progress === 0) exited(); }
    onProgressChanged: if (!opened && progress === 0) Qt.callLater(checkExit)
    onOpenedChanged: if (!opened) Qt.callLater(checkExit)

    readonly property var items: opened || progress > 0 ? SystemTray.items.values : []
    property SystemTrayItem selectedItem: null
    property var submenus: []
    readonly property var itemMenu: selectedItem?.menu ?? null
    onItemsChanged: if (selectedItem && !items.includes(selectedItem)) selectedItem = null
    function resetSubmenus() { submenus = []; }
    onItemMenuChanged: Qt.callLater(resetSubmenus)

    function itemLabel(item) { return item?.tooltipTitle || item?.title || item?.id || ""; }
    function showMenu(item) { if (item.hasMenu) selectedItem = item; }
    function activateItem(item) {
        if (item.onlyMenu) {
            showMenu(item);
        } else {
            item.activate();
            dismissed();
        }
    }
    function back() {
        if (submenus.length) submenus = submenus.slice(0, -1);
        else selectedItem = null;
    }

    screen: barWindow?.screen ?? null
    visible: !!barWindow?.screen && !!anchorItem && (opened || progress > 0) && Theme.state.bar.includes("trayApps")
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: root.opened ? panel : null }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "galaga-tray"

    // Whitelist the invoking bar so another bar control can act on the first click.
    HyprlandFocusGrab {
        windows: root.barWindow ? [root, root.barWindow] : [root]
        active: root.opened && root.visible
        onCleared: if (root.opened) root.dismissed()
    }

    QsMenuOpener {
        id: opener
        menu: root.itemMenu ? root.submenus[root.submenus.length - 1] ?? root.itemMenu : null
    }

    TransformWatcher {
        id: anchorTransform
        a: root.barWindow?.contentItem ?? null
        b: root.anchorItem
    }

    // Keep both the animation and resting card aligned to the same bar item.
    readonly property rect triggerRect: {
        anchorTransform.transform;
        const anchor = root.anchorItem;
        return anchor ? anchor.mapToItem(anchorTransform.a, 0, 0, anchor.width, anchor.height)
            : Qt.rect(0, 0, 0, 0);
    }

    PopoverCard {
        id: panel
        motion: entrance

        readonly property bool topBar: Theme.state.barAt === "top"
        readonly property real gap: 8 * Theme.s
        readonly property real inset: (root.barWindow?.exclusiveZone ?? 0) + gap
        readonly property real triggerX: root.triggerRect.x + root.triggerRect.width / 2
        readonly property real triggerY: root.triggerRect.y + root.triggerRect.height / 2

        width: Math.max(1, Math.min(340 * Theme.s, parent.width - (topBar ? 2 * gap : inset + gap)))
        height: Math.max(1, Math.min(body.implicitHeight + 2 * gap,
            parent.height - (topBar ? inset + gap : 2 * gap)))
        x: topBar ? Math.max(gap, Math.min(triggerX - width / 2, parent.width - width - gap)) : inset
        y: topBar ? inset : Math.max(gap, Math.min(triggerY - height / 2, parent.height - height - gap))
        radius: Theme.corner(36) * Theme.s
        color: Theme.s1

        focus: true
        Keys.onEscapePressed: {
            if (root.itemMenu) root.back();
            else root.dismissed();
        }
        Keys.onDownPressed: nextItemInFocusChain(true).forceActiveFocus()
        Keys.onUpPressed: nextItemInFocusChain(false).forceActiveFocus()

        Flickable {
            id: viewport
            anchors.fill: parent
            anchors.margins: panel.gap
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            function resetFocus() {
                contentY = 0;
                panel.forceActiveFocus();
            }
            Connections {
                target: opener
                function onMenuChanged() { Qt.callLater(viewport.resetFocus); }
            }

            Column {
                id: body
                width: viewport.width
                spacing: 4 * Theme.s

                TrayRow {
                    label: root.itemMenu ? "‹  " + root.itemLabel(root.selectedItem) : "background apps"
                    sectionLabel: true
                    interactive: !!root.itemMenu
                    onPressed: root.back()
                }
                TrayRow {
                    visible: !root.itemMenu && !root.items.length
                    label: "no tray apps"
                    sectionLabel: true
                    interactive: false
                }
                Repeater {
                    model: root.itemMenu ? [] : root.items
                    Row {
                        id: appRow
                        required property SystemTrayItem modelData
                        readonly property bool hasMenu: modelData.hasMenu
                        width: body.width
                        TrayRow {
                            width: appRow.width - (appRow.hasMenu ? menuButton.width : 0)
                            label: root.itemLabel(appRow.modelData)
                            iconSource: appRow.modelData.icon
                            showIcon: true
                            menuAvailable: appRow.hasMenu
                            interactive: !appRow.modelData.onlyMenu || appRow.hasMenu
                            onPressed: root.activateItem(appRow.modelData)
                            onMenuRequested: root.showMenu(appRow.modelData)
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                enabled: appRow.hasMenu
                                onTapped: root.showMenu(appRow.modelData)
                            }
                        }
                        TrayRow {
                            id: menuButton
                            visible: appRow.hasMenu
                            width: 42 * Theme.s
                            label: "⋯"
                            Accessible.name: "menu for " + root.itemLabel(appRow.modelData)
                            onPressed: root.showMenu(appRow.modelData)
                        }
                    }
                }
                Repeater {
                    model: opener.children
                    TrayRow {
                        required property QsMenuEntry modelData
                        separator: modelData.isSeparator
                        label: modelData.text
                        suffix: {
                            if (modelData.hasChildren) return "›";
                            if (modelData.buttonType === QsMenuButtonType.RadioButton)
                                return modelData.checkState === Qt.Checked ? "●" : "○";
                            if (modelData.buttonType === QsMenuButtonType.CheckBox) {
                                if (modelData.checkState === Qt.PartiallyChecked) return "◩";
                                return modelData.checkState === Qt.Checked ? "☑" : "☐";
                            }
                            return "";
                        }
                        interactive: !separator && modelData.enabled
                        onPressed: {
                            if (modelData.hasChildren) {
                                root.submenus = root.submenus.concat([modelData]);
                            } else {
                                modelData.triggered();
                                root.dismissed();
                            }
                        }
                    }
                }
            }
        }
    }

    component TrayRow: Rectangle {
        id: row
        property string label
        property string suffix
        property string iconSource
        property bool showIcon: false
        property bool sectionLabel: false
        property bool interactive: true
        property bool separator: false
        property bool menuAvailable: false
        signal pressed
        signal menuRequested

        width: parent.width
        height: (separator ? 9 : 38) * Theme.s
        radius: Theme.corner(16) * Theme.s
        color: interactive && (hover.hovered || activeFocus) ? Theme.s2 : "transparent"
        activeFocusOnTab: interactive
        Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
        Accessible.name: label
        Accessible.onPressAction: if (interactive) pressed()
        onActiveFocusChanged: {
            if (!activeFocus) return;
            const y = mapToItem(body, 0, 0).y;
            if (y < viewport.contentY) viewport.contentY = y;
            if (y + height > viewport.contentY + viewport.height)
                viewport.contentY = y + height - viewport.height;
        }

        Rectangle {
            visible: row.separator
            anchors.centerIn: parent
            width: parent.width - 20 * Theme.s
            height: 1
            color: Theme.s2
        }
        Item {
            id: art
            visible: row.showIcon
            anchors { left: parent.left; leftMargin: 10 * Theme.s; verticalCenter: parent.verticalCenter }
            width: 22 * Theme.s
            height: width
            Image { id: icon; anchors.fill: parent; source: row.iconSource; fillMode: Image.PreserveAspectFit }
            Icon { anchors.centerIn: parent; visible: icon.status !== Image.Ready; text: "\u{F0128}"; font.pixelSize: 16 * Theme.s }
        }
        Loader {
            anchors {
                left: row.showIcon ? art.right : parent.left
                right: tail.left
                leftMargin: 10 * Theme.s
                rightMargin: 8 * Theme.s
                top: parent.top
                bottom: parent.bottom
            }
            visible: !row.separator
            active: visible
            sourceComponent: row.sectionLabel ? sectionCaption : itemCaption

            Component {
                id: sectionCaption
                Lb {
                    px: 12 * Theme.s
                    text: row.label
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Component {
                id: itemCaption
                Text {
                    textFormat: Text.PlainText
                    text: row.label
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    font { family: Theme.ui; pixelSize: 14 * Theme.s }
                    color: row.interactive ? Theme.fg : Theme.grey
                }
            }
        }
        Text {
            id: tail
            anchors { right: parent.right; rightMargin: 10 * Theme.s; verticalCenter: parent.verticalCenter }
            textFormat: Text.PlainText
            text: row.suffix
            font { family: Theme.ui; pixelSize: 14 * Theme.s }
            color: Theme.grey
        }
        HoverHandler { id: hover; enabled: row.interactive; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: row.interactive; onTapped: row.pressed() }
        Keys.onPressed: event => {
            if (!row.interactive) return;
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                row.nextItemInFocusChain(event.key === Qt.Key_Down).forceActiveFocus();
                event.accepted = true;
            } else if (row.menuAvailable && (event.key === Qt.Key_Menu
                || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)))) {
                row.menuRequested();
                event.accepted = true;
            } else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) {
                row.pressed();
                event.accepted = true;
            }
        }
    }
}
