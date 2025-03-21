import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

Window {
    width: 1024
    height: 768
    visible: true
    title: qsTr("Nora the API explorer")

    ColumnLayout {
        anchors.fill: parent

        RowLayout {
            id: rowLayout
            Layout.fillWidth: true

            Text {
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
                    if (find(editText) === -1)
                        model.insertRow(model.rowCount())
                        model.setData(model.index(model.rowCount() -1, 0), editText, 0)
                    main.url = editText
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                id: rowLayout1
                Layout.fillHeight: true

                ScrollView {
                    Layout.fillHeight: true
                    implicitWidth: 150
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ListView {
                        id: listView
                        highlightFollowsCurrentItem: true
                        implicitWidth: contentItem.childrenRect.width
                        implicitHeight: contentItem.childrenRect.width
                        model: main.apiNames
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
                        }
                    }
                }
                Button {
                    text: "Run"
                    onClicked: main.run()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                GroupBox {
                    id: groupBox
                    Layout.fillWidth: true
                    implicitHeight: grid.height + 50
                    title: main.api
                    TableView {
                        id: grid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: childrenRect.height
                        selectionModel: ItemSelectionModel {}

                        model: main.params
                        columnWidthProvider: function (column) {
                            if (column == 2) {
                                return 640;
                            } else {
                                return 100;
                            }
                        }
                        delegate: Rectangle {
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: display
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
                    Layout.fillHeight: true
                    Layout.fillWidth: true
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
    }
}
