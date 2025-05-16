import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

ApplicationWindow {
    id: window
    width: 1024
    height: 768
    visible: true
    title: qsTr("Nora the API explorer")

    readonly property bool isPortrait: width < height

    menuBar: ToolBar {
        id: toolBar
        RowLayout {
            id: rowLayout
            anchors.fill: parent

            // Hamburger menu button
            Button {
                text: "\uE5D2"  // Unicode hamburger: ☰
                font.pixelSize: 16
                onClicked: leftDrawer.open()
                visible: leftDrawer.interactive
            }

            Label {
                id: text1
                text: "Endpoint: "
                font.pixelSize: 12
            }

            ComboBox {
                id: serverUrl
                editable: true
                selectTextByMouse: true
                Layout.fillWidth: true
                model: main.urls
                textRole: "display"
                onAccepted: {
                    print ("Server URL: " + editText)
                    if (find(editText) === -1)
                        model.insertRow(model.rowCount())
                        model.setData(model.index(model.rowCount() -1, 0), editText, 0)
                    main.url = editText
                }
                Binding {
                    target: main
                    property: "url"
                    value: serverUrl.currentText
                }

            }
            Button {
                text: "Run"
                onClicked: {
                    main.response = "";
                    main.run()
                }
            }
        }
    }

    Drawer {
        id: leftDrawer
        y: toolBar.height
        height: parent.height - toolBar.height
        edge: Qt.LeftEdge
        modal: false
        interactive: isPortrait
        visible: !isPortrait
        focus: true

        GroupBox {
            id: groupBox
            anchors.fill: parent
            anchors.margins: 5

            title: "API Explorer"

            ColumnLayout {
                id: rowLayout1
                anchors.fill: parent

                ScrollView {
                    Layout.fillHeight: true
                    implicitWidth: 150
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ListView {
                        id: listView
                        highlightFollowsCurrentItem: true
                        model: main.apiNames
                        onCurrentIndexChanged: {
                            main.response = "";
                        }
                        highlight: Rectangle {
                            color: "lightsteelblue"
                            radius: 5
                        }
                        focus: true
                        clip: true

                        Component.onCompleted: {
                            currentIndex = 0;
                        }
                        delegate: Text {
                            text: modelData

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    listView.currentIndex = index;
                                    main.api = modelData;
                                }
                            }
                            Component.onCompleted: {
                                if (index == ListView.view.currentIndex) {
                                    main.api = modelData;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SplitView {
        id: splitView
        anchors.fill: parent
        anchors.leftMargin: !leftDrawer.interactive ? leftDrawer.width + leftDrawer.x + 8 : 8
        anchors.rightMargin: 8
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        orientation: Qt.Vertical

        Page {
            SplitView.fillWidth: true
            SplitView.preferredHeight: grid.implicitHeight + 150
            SplitView.maximumHeight: parent.height - 150
            SplitView.minimumHeight: 200

            header: Frame {
                Label {
                    anchors.fill: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    text: main.api
                }
            }

            contentItem: TableView {
                id: grid

                selectionModel: ItemSelectionModel {}

                model: main.params
                columnWidthProvider: function (column) {
                    if (column == 2) {
                        return grid.width * 0.6;
                    } else {
                        return grid.width * 0.2;
                    }
                }
                delegate: Rectangle {
                    border.width: 1
                    implicitHeight: 30

                    required property bool editing
                    required property string display

                    Text {
                        anchors.centerIn: parent
                        text: display
                        visible: !editing
                    }

                    TableView.editDelegate: TextField {
                        anchors.fill: parent
                        text: display
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        Component.onCompleted: selectAll()

                        TableView.onCommit: {
                            display = text;
                        }
                    }
                }
            }
        }
                

        ScrollView {
            SplitView.fillHeight: true
            SplitView.fillWidth: true
            SplitView.maximumHeight: parent.height - 20
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            TextEdit {
                text: main.response
                readOnly: true
                selectByMouse: true
            }
        }
    }
}
