import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.qmlmodels

ApplicationWindow {
    id: window
    width: 1024
    height: 768
    visible: true
    title: qsTr("nora • Web3 API Explorer")

    Material.theme: Material.Dark
    Material.primary: "black"
    Material.background: "black"
    Material.accent: "white"
    Material.roundedScale: Material.NotRounded
    Material.containerStyle: Material.Outlined

    readonly property bool isPortrait: width < height

    header: ToolBar {
        padding: 8
        background: Rectangle {
            color: Material.background
        }
        RowLayout {
            anchors.fill: parent

            // Hamburger menu button
            Button {
                id: hamburgerButton
                Material.roundedScale: Material.NotRounded
                text: "⋮"
                font.pixelSize: 18
                onClicked: smallLayout.toggle()
                visible: window.isPortrait
            }

            ToolButton {
                id: titleLabel
                Layout.fillWidth: true
                text: window.title
                font.bold: true
                onClicked: Qt.openUrlExternally("https://github.com/arnetheduck/nora-poc")
            }
            // Spacer
            Item {
                Layout.preferredWidth: hamburgerButton.width
                visible: hamburgerButton.visible
            }
        }
    }

    Page {
        id: apiSelector
        implicitWidth: 300
        padding: 8
        contentWidth: listView.implicitWidth
        header: Label {
            id: headerLabel
            text: "API Endpoints"
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        ListView {
            id: listView
            anchors.fill: parent
            highlightFollowsCurrentItem: true
            model: main.apiNames
            currentIndex: 0
            onCurrentIndexChanged: {
                main.response = "";
            }

            Binding {
                target: main
                property: "api"
                value: listView.model[listView.currentIndex]
            }
            clip: true
            delegate: ItemDelegate {
                highlighted: ListView.isCurrentItem
                width: listView.width
                contentItem: Label {
                    text: modelData
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    height: 30
                }

                onClicked: {
                    ListView.view.currentIndex = index
                    smallLayout.toggle()
                }
            }
        }
    }

    Page {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 16

        footer: ToolBar {
            padding: 16
            background: Rectangle {
                color: Material.background
            }
            RowLayout {
                id: rowLayout
                anchors.fill: parent
                Label {
                    text: "Endpoint: "
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }
                ComboBox {
                    id: serverUrl
                    editable: true
                    selectTextByMouse: true
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    model: main.urls
                    textRole: "display"
                    contentItem: TextField {
                        id: urlEdit
                        text: serverUrl.displayText
                        font: serverUrl.font
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        selectedTextColor: Material.primary
                        mouseSelectionMode: TextInput.SelectWords
                        background: Rectangle {
                            color: "transparent"
                        }
                        onEditingFinished: {
                            if (serverUrl.find(urlEdit.text) === -1) {
                                serverUrl.model.insertRow(serverUrl.model.rowCount());
                                serverUrl.model.setData(serverUrl.model.index(serverUrl.model.rowCount() - 1, 0), urlEdit.text, 0);
                            }
                        }

                        Binding {
                            target: main
                            property: "url"
                            value: urlEdit.text
                        }
                    }
                }
                Button {
                    Material.roundedScale: Material.NotRounded
                    Layout.fillHeight: true
                    text: !busyIndicator.running ? qsTr("Run") : ""
                    enabled: !busyIndicator.running
                    onClicked: {
                        main.response = "";
                        main.run()
                    }
                    BusyIndicator {
                        id: busyIndicator
                        anchors.fill: parent
                        padding: 16
                        visible: running
                        running: main.inflight > 0
                    }
                }
            }
        }
        SplitView {
            id: splitView
            anchors.fill: parent
            orientation: Qt.Vertical
            padding: 8

            Page {
                SplitView.fillWidth: true
                SplitView.preferredHeight: grid.implicitHeight + 150
                SplitView.maximumHeight: parent.height - 150
                SplitView.minimumHeight: 200

                header: RowLayout {
                    Label {
                        horizontalAlignment: Qt.AlignHCenter
                        verticalAlignment: Qt.AlignVCenter
                        text: qsTr("Parameters") + " (" + main.api + ")"
                        font.bold: true
                        elide: Text.ElideRight
                        wrapMode: Text.WordWrap
                    }
                }
                Component {
                    id: editableDelegate
                    TextField {
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        selectedTextColor: Material.primary
                        placeholderText: display

                        onTextChanged: {
                            if (text !== display) {
                                let index = grid.index(row, column)
                                grid.model.setData(index, text)
                            }
                        }
                    }
                }

                Component {
                    id: readonlyDelegate
                    Label {
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        text: display
                        font.bold: true
                    }
                }

                TableView {
                    id: grid
                    anchors.fill: parent
                    selectionModel: ItemSelectionModel {}

                    model: main.params

                    editTriggers: TableView.SingleTapped
                    columnWidthProvider: function (column) {
                        if (column == 2) {
                            return grid.width * 0.6;
                        } else {
                            return grid.width * 0.2;
                        }
                    }
                    delegate: FocusScope {
                        id: delegateItem
                        implicitHeight: 40

                        required property bool editing
                        required property string display
                        required property bool selected
                        required property bool current
                        required property int row
                        required property int column
                        property bool editable

                        Loader {
                            id: delegateLoader
                            property alias display: delegateItem.display
                            property alias row: delegateItem.row
                            property alias column: delegateItem.column
                            anchors.fill: parent
                            sourceComponent: editable ? editableDelegate : readonlyDelegate
                            Component.onCompleted: {
                                // one time only. Avoiding some weird animations on destruction
                                delegateItem.editable = grid.model.flags(grid.index(row, column)) & Qt.ItemIsEditable ? true : false
                            }
                        }
                    }
                }
            }

            Page {
                SplitView.fillHeight: true
                SplitView.fillWidth: true
                SplitView.maximumHeight: parent.height - 20
                header: Label {
                    text: qsTr("Response")
                    font.bold: true
                }
                ScrollView {
                    anchors.fill: parent
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    TextArea {
                        text: main.response
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextArea.Wrap
                        selectedTextColor: Material.primary
                    }
                }
            }
        }
    }

    LayoutChooser {
        id: layoutChooser
        anchors.fill: parent
        layoutChoices: [
            smallLayout,
            largeLayout
        ]
        criteria: [
            window.isPortrait,
            true
        ]

        property Item smallLayout: SwipeView {
            id: smallLayout
            anchors.fill: parent
            parent: layoutChooser
            padding: 8
            currentIndex: 0
            function toggle() {
                currentIndex = (currentIndex + 1) % count
            }
            Item {
                ColumnLayout {
                    id: rowLayout1
                    anchors.fill: parent
                    LayoutItemProxy { 
                        target: apiSelector
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
            }
            Item {
                ColumnLayout {
                    id: rowLayout2
                    anchors.fill: parent
                    LayoutItemProxy {
                        target: mainLayout
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
            }
        }

        property Item largeLayout: RowLayout {
            id: largeLayout
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            parent: layoutChooser

            LayoutItemProxy {
                target: apiSelector
                Layout.fillHeight: true
            }
            LayoutItemProxy {
                target: mainLayout
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}