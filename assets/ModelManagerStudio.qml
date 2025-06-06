import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts
import org.julialang

ApplicationWindow {
    id: mainWindow

    property var fontSizeOfLevel: [20, 18, 14, 12, 10]

    title: "PCVCT GUI"
    width: 1400
    height: 600
    visible: true

    // Add keyboard shortcut for Command+W to close the window
    Shortcut {
        sequences: [StandardKey.Close] // This maps to Cmd+W on macOS
        onActivated: mainWindow.close()
    }

    Component {
        id: locationComponent

        Item {
            // Use Item as the root to properly handle layout
            id: locationItem

            property int level: 2 // level of the item, used for font size
            property string labelText: "Default Text"
            property string location: "default_location"
            property bool isVaried: false
            property bool isRequired: false
            property alias comboBox: locationComboBox
            property alias label: labelTextItem // These layout properties will be applied when used in a Layout

            Layout.alignment: Qt.AlignCenter
            width: rect.width
            height: rect.height

            // The actual rectangle with background color
            Rectangle {
                id: rect

                width: columnLayout.implicitWidth + 10
                height: columnLayout.implicitHeight + 10 // padding/margin
                color: locationItem.isVaried ? "#d0e8ff" : "transparent"
                radius: 4
                border.width: 1
                border.color: color === "transparent" ? "transparent" : Qt.darker(color, 1.2)

                ColumnLayout {
                    id: columnLayout

                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        id: labelTextItem

                        text: labelText
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                    }

                    // ComboBox for selecting folder locations
                    ComboBox {
                        id: locationComboBox

                        // Function to update folders when location or variation state changes
                        function updateFolders() {
                            model = Julia.get_folders(locationItem.location, locationItem.isRequired);
                        }

                        Layout.alignment: Qt.AlignBottom
                        Layout.preferredWidth: 180
                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                    }

                }

            }

        }

    }

    SystemPalette {
        id: syscolors

        colorGroup: SystemPalette.Active
    }

    // Main layout for the application
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16 // Increased margins for better spacing
        spacing: 12 // Adjusted spacing between main sections

        // Things needed for the simulation to run
        RowLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 16 // Maintain spacing between columns

            // The inputs column
            ColumnLayout {
                spacing: 10 // Reduced spacing for more compact vertical layout
                Layout.preferredWidth: parent.width * 0.45
                Layout.alignment: Qt.AlignTop

                Text {
                    Layout.alignment: Qt.AlignCenter
                    text: "Inputs"
                    color: syscolors.text
                    font.bold: true
                    font.underline: true
                    font.pointSize: mainWindow.fontSizeOfLevel[0]
                }

                // Required Locations
                Text {
                    Layout.alignment: Qt.AlignCenter
                    text: "Required Locations"
                    color: syscolors.text
                    font.bold: true
                    font.underline: true
                    font.pointSize: mainWindow.fontSizeOfLevel[1]
                }

                GridLayout {
                    Layout.alignment: Qt.AlignCenter
                    columns: 2

                    Loader {
                        id: configLocationLoader

                        sourceComponent: locationComponent
                        onLoaded: {
                            item.labelText = "Config folder";
                            item.location = "config";
                            item.isRequired = true;
                            item.isVaried = true;
                            item.comboBox.updateFolders();
                        }
                    }

                    // Custom code folders
                    Loader {
                        id: customCodeLocationLoader

                        sourceComponent: locationComponent
                        onLoaded: {
                            item.labelText = "Custom code folder";
                            item.location = "custom_code";
                            item.isVaried = false;
                            item.isRequired = true;
                            item.comboBox.updateFolders();
                        }
                    }

                }

                // Optional Locations
                Text {
                    Layout.alignment: Qt.AlignCenter
                    text: "Optional Locations"
                    color: syscolors.text
                    font.bold: true
                    font.underline: true
                    font.pointSize: mainWindow.fontSizeOfLevel[1]
                }

                RowLayout {
                    // Row for optional locations
                    Layout.alignment: Qt.AlignCenter
                    spacing: 2 // Maintain spacing between items

                    // non-IC optional locations
                    GridLayout {
                        Layout.alignment: Qt.AlignCenter
                        rows: 2

                        // Rules folder - First row, first column
                        Loader {
                            id: rulesLocationLoader

                            Layout.row: 0
                            Layout.column: 0
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "Rules folder";
                                item.location = "rulesets_collection";
                                item.isRequired = false;
                                item.isVaried = true;
                                item.comboBox.updateFolders();
                            }
                        }

                        // Intracellular folder - First row, second column
                        Loader {
                            id: intracellularLocationLoader

                            Layout.row: 1
                            Layout.column: 0
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "Intracellular folder";
                                item.location = "intracellular";
                                item.isVaried = true;
                                item.isRequired = false;
                                item.comboBox.updateFolders();
                            }
                        }

                    }

                    Item {
                        Layout.alignment: Qt.AlignCenter
                        implicitHeight: parent.height
                        Layout.preferredWidth: 10

                        Rectangle {
                            anchors.centerIn: parent
                            height: parent.height
                            width: 2
                            color: syscolors.text
                        }

                    }

                    // IC optional locations
                    GridLayout {
                        Layout.alignment: Qt.AlignCenter
                        rows: 2
                        columns: 2

                        // IC cell folder - first row, first column
                        Loader {
                            id: icCellLocationLoader

                            Layout.row: 0
                            Layout.column: 0
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "IC cell folder";
                                item.location = "ic_cell";
                                item.isVaried = true;
                                item.isRequired = false;
                                item.comboBox.updateFolders();
                            }
                        }

                        // IC ECM folder - Second row, first column
                        Loader {
                            id: icEcmLocationLoader

                            Layout.row: 1
                            Layout.column: 0
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "IC ECM folder";
                                item.location = "ic_ecm";
                                item.isVaried = true;
                                item.isRequired = false;
                                item.comboBox.updateFolders();
                            }
                        }

                        // IC substrate folder - first row, second column
                        Loader {
                            id: icSubstrateLocationLoader

                            Layout.row: 0
                            Layout.column: 1
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "IC substrate folder";
                                item.location = "ic_substrate";
                                item.isVaried = false;
                                item.isRequired = false;
                                item.comboBox.updateFolders();
                            }
                        }

                        // IC DC folder - Second row, second column
                        Loader {
                            id: icDcLocationLoader

                            Layout.row: 1
                            Layout.column: 1
                            sourceComponent: locationComponent
                            onLoaded: {
                                item.labelText = "IC DC folder";
                                item.location = "ic_dc";
                                item.isVaried = false;
                                item.isRequired = false;
                                item.comboBox.updateFolders();
                            }
                        }

                    }

                }

                // Button to create inputs
                Button {
                    Layout.alignment: Qt.AlignCenter
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 40
                    text: "Create Inputs"
                    font.pixelSize: mainWindow.fontSizeOfLevel[2]
                    onClicked: {
                        // Set input folders in Julia
                        Julia.set_input_folders(configLocationLoader.item.comboBox.currentText, customCodeLocationLoader.item.comboBox.currentText, rulesLocationLoader.item.comboBox.currentText, intracellularLocationLoader.item.comboBox.currentText, icCellLocationLoader.item.comboBox.currentText, icEcmLocationLoader.item.comboBox.currentText, icSubstrateLocationLoader.item.comboBox.currentText, icDcLocationLoader.item.comboBox.currentText);
                        // Update the display to show current selections
                        requiredLocationsDisplay.updateFolderDisplay();
                        optionalLocationsDisplay.updateFolderDisplay();
                        // Hide the placeholder text and show the inputs display
                        inputsPlaceholderText.visible = false;
                        inputsDisplay.visible = true;
                        locationComboBox.model = Julia.get_varied_locations();
                        currentVariationTargetText.updateVariationTarget(); // Update the target text
                    }
                }

                // Current inputs display
                ColumnLayout {
                    Layout.fillHeight: true

                    Text {
                        text: "Current Inputs"
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        color: syscolors.text
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#f0f0f0"
                        radius: 6
                        border.color: "#dddddd"
                        border.width: 2

                        Text {
                            id: inputsPlaceholderText

                            anchors.centerIn: parent
                            text: "Inputs will be displayed here after creation"
                            horizontalAlignment: Text.AlignHCenter
                            font.italic: true
                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                            color: "#888888"
                            visible: true
                        }

                        RowLayout {
                            id: inputsDisplay

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            anchors.fill: parent
                            spacing: 10
                            visible: false // Initially hidden, will be shown when inputs are created

                            // Display required locations
                            ColumnLayout {
                                id: requiredLocationsDisplay

                                // Function to update the text values with current selections
                                function updateFolderDisplay() {
                                    // The Repeater will handle displaying each item
                                    requiredFoldersRepeater.model = [{
                                        "name": "Config folder",
                                        "value": Julia.get_input_folder("config")
                                    }, {
                                        "name": "Custom code folder",
                                        "value": Julia.get_input_folder("custom_code")
                                    }];
                                }

                                Layout.alignment: Qt.AlignTop
                                Layout.margins: 5

                                Text {
                                    text: "Required Locations"
                                    color: syscolors.text
                                    font.bold: true
                                    font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                }

                                Repeater {
                                    id: requiredFoldersRepeater

                                    RowLayout {
                                        Layout.leftMargin: 20
                                        spacing: 5

                                        Text {
                                            text: modelData.name + ":"
                                            color: syscolors.text
                                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                            horizontalAlignment: Text.AlignRight
                                            width: 120 // Fixed width for alignment
                                        }

                                        Text {
                                            text: modelData.value
                                            color: syscolors.text
                                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                            horizontalAlignment: Text.AlignLeft
                                        }

                                    }

                                }

                            }

                            // Display optional locations
                            ColumnLayout {
                                id: optionalLocationsDisplay

                                // This function will force the repeater to reevaluate its values
                                function updateFolderDisplay() {
                                    optionalFoldersRepeater.model = [{
                                        "name": "Rules folder",
                                        "value": Julia.get_input_folder("rulesets_collection")
                                    }, {
                                        "name": "Intracellular folder",
                                        "value": Julia.get_input_folder("intracellular")
                                    }, {
                                        "name": "IC Cell folder",
                                        "value": Julia.get_input_folder("ic_cell")
                                    }, {
                                        "name": "IC ECM folder",
                                        "value": Julia.get_input_folder("ic_ecm")
                                    }, {
                                        "name": "IC Substrate folder",
                                        "value": Julia.get_input_folder("ic_substrate")
                                    }, {
                                        "name": "IC DC folder",
                                        "value": Julia.get_input_folder("ic_dc")
                                    }];
                                }

                                Layout.alignment: Qt.AlignTop
                                Layout.margins: 5

                                Text {
                                    text: "Optional Locations"
                                    color: syscolors.text
                                    font.bold: true
                                    font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                }

                                // Use a Repeater to generate optional folder displays
                                Repeater {
                                    id: optionalFoldersRepeater

                                    RowLayout {
                                        Layout.leftMargin: 20
                                        spacing: 5
                                        visible: modelData.value !== "--NONE--"

                                        Text {
                                            text: modelData.name + ":"
                                            color: syscolors.text
                                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                            horizontalAlignment: Text.AlignRight
                                            Layout.preferredWidth: 120 // Fixed width for alignment
                                        }

                                        Text {
                                            text: modelData.value
                                            color: syscolors.text
                                            font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                            horizontalAlignment: Text.AlignLeft
                                        }

                                    }

                                }

                            }

                        }

                    }

                }

            }

            // Main separator with gradient effect
            Item {
                Layout.fillHeight: true
                Layout.fillWidth: true

                Rectangle {
                    anchors.centerIn: parent
                    height: parent.height * 0.9
                    width: 2
                    radius: 2

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: "transparent"
                        }

                        GradientStop {
                            position: 0.1
                            color: syscolors.text
                        }

                        GradientStop {
                            position: 0.9
                            color: syscolors.text
                        }

                        GradientStop {
                            position: 1
                            color: "transparent"
                        }

                    }

                }

            }

            // The variations column
            ColumnLayout {
                spacing: 10 // Reduced spacing for more compact vertical layout
                Layout.preferredWidth: parent.width * 0.45
                Layout.alignment: Qt.AlignTop

                Text {
                    Layout.alignment: Qt.AlignCenter
                    text: "Variations"
                    color: syscolors.text
                    font.bold: true
                    font.underline: true
                    font.pointSize: mainWindow.fontSizeOfLevel[0]
                }

                Text {
                    text: "Variation target"
                    color: syscolors.text
                    font.bold: true
                    font.pixelSize: mainWindow.fontSizeOfLevel[1]
                    Layout.alignment: Qt.AlignLeft
                }

                // Variation target box
                Rectangle {
                    property int padding: 12

                    Layout.alignment: Qt.AlignCenter
                    Layout.fillWidth: true
                    color: "#f0f0f0"
                    radius: 6
                    border.color: "#dddddd"
                    border.width: 1
                    implicitHeight: variationTargetColumnLayout.implicitHeight + 2 * padding

                    ColumnLayout {
                        id: variationTargetColumnLayout

                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: parent.padding

                        RowLayout {
                            id: variationRowLayout

                            // Simple helper function to determine item type
                            function getItemType(item) {
                                if (!item)
                                    return "default";

                                try {
                                    const substrates = Julia.get_substrate_names();
                                    if (substrates.includes(item))
                                        return "substrate";

                                    const cellTypes = Julia.get_cell_type_names();
                                    if (cellTypes.includes(item))
                                        return "cell_type";

                                    if (item.toString().startsWith("custom:"))
                                        return "custom";

                                } catch (e) {
                                    console.log("Error determining item type:", e);
                                }
                                return "default";
                            }

                            Layout.fillWidth: true
                            Layout.preferredHeight: comboRow.implicitHeight + 20 // Add some padding
                            Layout.alignment: Qt.AlignTop

                            // Simple delegate for ComboBox items with basic styling
                            Component {
                                id: coloredItemDelegate

                                ItemDelegate {
                                    property int level: 2 // Level of the item, used for font size

                                    contentItem: Text {
                                        text: modelData
                                        color: {
                                            const itemType = variationRowLayout.getItemType(modelData);
                                            if (itemType === "substrate")
                                                return "#2060A0";

                                            // Blue for substrates
                                            if (itemType === "cell_type")
                                                return "#206020";

                                            // Green for cell types
                                            if (itemType === "custom")
                                                return "#A02020";

                                            // Red for custom tags
                                            return "#000000";
                                        }
                                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                                        font.bold: variationRowLayout.getItemType(modelData) !== "default"
                                        font.italic: variationRowLayout.getItemType(modelData) === "custom"
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                }

                            }

                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentWidth: comboRow.implicitWidth
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true

                                Row {
                                    // ComboBox {
                                    //     id: tokenComboBoxOne
                                    //     property int longestTextWidth: 0
                                    //     function updateLongestTextWidth() {
                                    //         let longest = "";
                                    //         for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                    //             longest = model[i];
                                    //         }
                                    //         dummyTextItemOne.text = longest;
                                    //         longestTextWidth = dummyTextItemOne.implicitWidth;
                                    //     }
                                    //     width: longestTextWidth + 50
                                    //     model: []
                                    //     // Layout.preferredWidth: 120
                                    //     Layout.fillWidth: true
                                    //     // Use the colored delegate
                                    //     delegate: coloredItemDelegate
                                    //     onModelChanged: updateLongestTextWidth()
                                    //     onCurrentTextChanged: {
                                    //         // Update the token combo boxes based on the selected location
                                    //         // Prevent updates while changing location
                                    //         tokenComboBoxTwo.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText);
                                    //         tokenComboBoxThree.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText);
                                    //         tokenComboBoxFour.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText);
                                    //         currentVariationTargetText.updateVariationTarget(); // Update the target text
                                    //     }
                                    //     visible: model.length > 0 // Enable only if there are tokens available
                                    //     Text {
                                    //         id: dummyTextItemOne
                                    //         visible: false
                                    //         font: tokenComboBoxOne.font
                                    //     }
                                    // }
                                    // ComboBox {
                                    //     id: tokenComboBoxTwo
                                    //     property int longestTextWidth: 0
                                    //     function updateLongestTextWidth() {
                                    //         let longest = "";
                                    //         for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                    //             longest = model[i];
                                    //         }
                                    //         dummyTextItemTwo.text = longest;
                                    //         longestTextWidth = dummyTextItemTwo.implicitWidth;
                                    //     }
                                    //     width: longestTextWidth + 50
                                    //     model: []
                                    //     // Layout.preferredWidth: 120
                                    //     Layout.fillWidth: true
                                    //     // Use the colored delegate
                                    //     delegate: coloredItemDelegate
                                    //     onModelChanged: updateLongestTextWidth()
                                    //     onCurrentTextChanged: {
                                    //         // Update the token combo boxes based on the selected location
                                    //         // Prevent updates while changing location
                                    //         tokenComboBoxThree.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText);
                                    //         tokenComboBoxFour.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText);
                                    //         currentVariationTargetText.updateVariationTarget(); // Update the target text
                                    //     }
                                    //     visible: model.length > 0 // Enable only if there are tokens available
                                    //     Text {
                                    //         id: dummyTextItemTwo
                                    //         visible: false
                                    //         font: tokenComboBoxTwo.font
                                    //     }
                                    // }
                                    // ComboBox {
                                    //     id: tokenComboBoxThree
                                    //     property int longestTextWidth: 0
                                    //     function updateLongestTextWidth() {
                                    //         let longest = "";
                                    //         for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                    //             longest = model[i];
                                    //         }
                                    //         dummyTextItemThree.text = longest;
                                    //         longestTextWidth = dummyTextItemThree.implicitWidth;
                                    //     }
                                    //     width: longestTextWidth + 50
                                    //     model: []
                                    //     // Layout.preferredWidth: 120
                                    //     Layout.fillWidth: true
                                    //     // Use the colored delegate
                                    //     delegate: coloredItemDelegate
                                    //     onModelChanged: updateLongestTextWidth()
                                    //     onCurrentTextChanged: {
                                    //         // Update the token combo boxes based on the selected location
                                    //         // Prevent updates while changing location
                                    //         tokenComboBoxFour.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText);
                                    //         currentVariationTargetText.updateVariationTarget(); // Update the target text
                                    //     }
                                    //     visible: model.length > 0 // Enable only if there are tokens available
                                    //     Text {
                                    //         id: dummyTextItemThree
                                    //         visible: false
                                    //         font: tokenComboBoxThree.font
                                    //     }
                                    // }
                                    // ComboBox {
                                    //     id: tokenComboBoxFour
                                    //     property int longestTextWidth: 0
                                    //     function updateLongestTextWidth() {
                                    //         if (model === undefined)
                                    //             return 0;
                                    //         let longest = "";
                                    //         for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                    //             longest = model[i];
                                    //         }
                                    //         dummyTextItemFour.text = longest;
                                    //         longestTextWidth = dummyTextItemFour.implicitWidth;
                                    //     }
                                    //     width: longestTextWidth + 50
                                    //     model: Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText)
                                    //     // Layout.preferredWidth: 120
                                    //     Layout.fillWidth: true
                                    //     // Use the colored delegate
                                    //     delegate: coloredItemDelegate
                                    //     onModelChanged: updateLongestTextWidth()
                                    //     onCurrentTextChanged: currentVariationTargetText.updateVariationTarget()
                                    //     visible: model ? model.length > 0 : false // Enable only if there are tokens available
                                    //     Text {
                                    //         id: dummyTextItemFour
                                    //         visible: false
                                    //         font: tokenComboBoxFour.font
                                    //     }
                                    // }

                                    id: comboRow

                                    spacing: 5

                                    ComboBox {
                                        // tokenComboBoxOne.model = Julia.get_tokens(locationComboBox.currentText);
                                        // tokenComboBoxTwo.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText);
                                        // tokenComboBoxThree.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText);
                                        // tokenComboBoxFour.model = Julia.get_tokens(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText);
                                        // currentVariationTargetText.updateVariationTarget(); // Update the target text

                                        id: locationComboBox

                                        property int longestTextWidth: 0

                                        function updateLongestTextWidth() {
                                            if (model === undefined) {
                                                longestTextWidth = 0;
                                                return ;
                                            }
                                            let longest = "";
                                            for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                                longest = model[i];
                                            }
                                            dummyTextItemLocation.text = longest;
                                            longestTextWidth = dummyTextItemLocation.implicitWidth;
                                        }

                                        width: longestTextWidth + 50
                                        model: []
                                        // Use the colored delegate
                                        delegate: coloredItemDelegate
                                        onModelChanged: updateLongestTextWidth()
                                        onCurrentTextChanged: {
                                            // Update the token combo boxes based on the selected location
                                            // Prevent updates while changing location
                                            tokenComboBoxRepeater.itemAt(0).model = Julia.get_next_model(locationComboBox.currentText);
                                        }

                                        Text {
                                            id: dummyTextItemLocation

                                            visible: false
                                            font: locationComboBox.font
                                        }

                                    }

                                    Repeater {
                                        id: tokenComboBoxRepeater

                                        model: 100

                                        delegate: ComboBox {
                                            id: tokenComboBox

                                            property int longestTextWidth: 0

                                            function updateLongestTextWidth() {
                                                let longest = "";
                                                for (let i = 0; i < model.length; ++i) if (model[i].length > longest.length) {
                                                    longest = model[i];
                                                }
                                                dummyTextItem.text = longest;
                                                longestTextWidth = dummyTextItem.implicitWidth;
                                            }

                                            function updateNextComboBox() {
                                                var tokens = [locationComboBox.currentText];
                                                for (let i = 0; i <= index; ++i) {
                                                    tokens.push(tokenComboBoxRepeater.itemAt(i).currentText);
                                                }
                                                let next_model = Julia.get_next_model.apply(Julia, tokens);
                                                if (next_model !== undefined && next_model.length > 0) {
                                                    tokenComboBoxRepeater.itemAt(index + 1).model = next_model;
                                                } else {
                                                    for (let i = index + 1; i < tokenComboBoxRepeater.count; ++i) {
                                                        tokenComboBoxRepeater.itemAt(i).model = [];
                                                    }
                                                    currentVariationTargetText.allowUpdates = true; // Allow updates to the target text
                                                    currentVariationTargetText.updateVariationTarget();
                                                }
                                            }

                                            font.pixelSize: mainWindow.fontSizeOfLevel[2]
                                            width: longestTextWidth + 50
                                            model: []
                                            // Layout.preferredWidth: 120
                                            Layout.fillWidth: true
                                            // Use the colored delegate
                                            delegate: coloredItemDelegate
                                            onModelChanged: {
                                                if (model === undefined || model.length === 0) {
                                                    longestTextWidth = 0;
                                                    return ;
                                                }
                                                updateLongestTextWidth();
                                                updateNextComboBox();
                                            }
                                            onCurrentTextChanged: {
                                                if (model === undefined || model.length === 0)
                                                    return ;

                                                updateNextComboBox();
                                            }
                                            visible: model ? model.length > 0 : false // Enable only if there are tokens available

                                            Text {
                                                id: dummyTextItem

                                                visible: false
                                                font: tokenComboBox.font
                                            }
                                            // Enable only if there are tokens available

                                        }

                                    }

                                }

                                ScrollBar.horizontal: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }

                            }

                        }

                        Text {
                            text: "Current target"
                            color: syscolors.text
                            font.pixelSize: mainWindow.fontSizeOfLevel[1]
                            font.bold: true
                            Layout.alignment: Qt.AlignLeft
                        }

                        // Display current variation target
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: currentVariationTargetText.implicitHeight + 24
                            color: "white"
                            border.color: "#dddddd"
                            border.width: 1
                            radius: 4
                            anchors.margins: 5

                            Flickable {
                                id: flickable

                                anchors.fill: parent
                                contentWidth: currentVariationTargetText.paintedWidth + 20
                                contentHeight: parent.height
                                clip: true
                                interactive: currentVariationTargetText.paintedWidth > width
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.HorizontalFlick

                                Text {
                                    id: currentVariationTargetText

                                    property bool allowUpdates: false // Flag to control updates

                                    function updateVariationTarget() {
                                        if (!currentVariationTargetText.allowUpdates)
                                            return ;

                                        // Skip updates if flag is false
                                        // currentVariationTargetText.text = Julia.get_target_path(locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText, tokenComboBoxFour.currentText);
                                        var tokens = [locationComboBox.currentText];
                                        for (let i = 0; i < tokenComboBoxRepeater.count; ++i) {
                                            let text = tokenComboBoxRepeater.itemAt(i).currentText;
                                            if (text === "")
                                                break;

                                            tokens.push(text);
                                        }
                                        currentVariationTargetText.text = Julia.get_target_path.apply(Julia, tokens);
                                        allowUpdates = false;
                                    }

                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: ""
                                    color: "#888888"
                                    font.pointSize: mainWindow.fontSizeOfLevel[3]
                                    width: implicitWidth
                                    onTextChanged: {
                                        createVariationButton.text = Julia.variation_exists(currentVariationTargetText.text) ? "Edit Variation" : "Create Variation";
                                    }
                                }

                                ScrollBar.horizontal: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }

                            }

                        }

                    }

                }

                // Variation values and create variation row
                RowLayout {
                    // Variation values header
                    Text {
                        id: variationValuesHeaderText

                        text: "Variation values"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        Layout.alignment: Qt.AlignLeft
                    }

                    // Variation values input box
                    Rectangle {
                        id: variationValuesRectangle

                        Layout.fillWidth: true
                        Layout.preferredHeight: variationValuesInput.implicitHeight + 24
                        Layout.topMargin: 0
                        color: "white"
                        border.color: "#cccccc"
                        radius: 4

                        ScrollView {
                            anchors.fill: parent
                            contentWidth: variationValuesInput.width + 20
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                            Item {
                                anchors.fill: parent

                                TextInput {
                                    id: variationValuesInput

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                    text: ""
                                    wrapMode: TextInput.NoWrap
                                    color: "black"
                                    clip: true // ensures text doesn't spill over bounds
                                    selectByMouse: true
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    // anchors.fill: parent
                                    anchors.leftMargin: 10
                                    text: "e.g. 0.1:0.2:0.5, [1.0, 1.2, 1.5]"
                                    color: "#888888"
                                    font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                    verticalAlignment: Text.AlignVCenter
                                    visible: variationValuesInput.text === "" // Show hint text when input is empty
                                }

                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: variationValuesInput.forceActiveFocus()
                            onDoubleClicked: variationValuesInput.selectAll()
                            // Set to false so it doesn't block text input
                            // (only used to grab focus when clicking the background)
                            hoverEnabled: true
                            preventStealing: true
                            propagateComposedEvents: true
                        }

                    }

                    // Create variation button
                    Button {
                        id: createVariationButton

                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 40
                        text: "Create Variation"
                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                        enabled: currentVariationTargetText.text !== "" && variationValuesInput.text !== ""
                        onClicked: {
                            // Call Julia function to create variation
                            // Julia.create_variation(currentVariationTargetText.text, variationValuesInput.text, locationComboBox.currentText, tokenComboBoxOne.currentText, tokenComboBoxTwo.currentText, tokenComboBoxThree.currentText, tokenComboBoxFour.currentText);
                            var tokens = [currentVariationTargetText.text, variationValuesInput.text]
                            for (let i = 0; i < tokenComboBoxRepeater.count; ++i) {
                                let text = tokenComboBoxRepeater.itemAt(i).currentText;
                                if (text === "")
                                    break;

                                tokens.push(text);
                            }
                            Julia.create_variation.apply(Julia, tokens);
                            currentVariationsFlickable.currentVariations = Julia.get_current_variations();
                            text = "Edit Variation"; // Change button text to indicate edit mode
                        }
                    }

                }

                // Display current variations
                ColumnLayout {
                    id: currentVariationsColumn

                    Text {
                        text: "Current Variations"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        Layout.alignment: Qt.AlignLeft
                    }

                    // Current variations rectangle
                    Flickable {
                        id: currentVariationsFlickable

                        property var currentVariations: Julia.get_current_variations()

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.fill: parent
                            color: "#f0f0f0"
                            radius: 6
                            border.color: "#dddddd"
                            border.width: 2
                            anchors.margins: 5

                            ColumnLayout {
                                id: currentVariationPairsColumn

                                property int maxLHSWidth: 0 // <- tracks the widest LHS

                                anchors.fill: parent
                                spacing: 16

                                // Display each variation
                                Repeater {
                                    model: currentVariationsFlickable.currentVariations

                                    Item {
                                        Layout.fillWidth: true

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 5
                                            anchors.leftMargin: 10

                                            Text {
                                                id: lhsText

                                                Layout.alignment: Qt.AlignRight
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData[0].toString() + " ⇒ "
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                // This updates the maxLHSWidth dynamically
                                                Component.onCompleted: {
                                                    if (lhsText.implicitWidth > currentVariationPairsColumn.maxLHSWidth)
                                                        currentVariationPairsColumn.maxLHSWidth = lhsText.implicitWidth;

                                                }
                                                Layout.preferredWidth: currentVariationPairsColumn.maxLHSWidth
                                            }

                                            Text {
                                                text: modelData[1].toString()
                                                font.pixelSize: mainWindow.fontSizeOfLevel[3]
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                            }

                                        }

                                    }

                                }

                                Item {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                }

                            }

                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        ScrollBar.horizontal: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                    }

                }

            }

        }

        // Run Simulation
        Button {
            // Julia.run_simulation();

            id: runSimulationButton

            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: 200
            Layout.preferredHeight: 45
            text: "Run Simulation"
            font.pixelSize: mainWindow.fontSizeOfLevel[1]
            font.bold: true
            enabled: true
            onClicked: {
                // Call Julia function to run the simulation
                // Disable button to prevent multiple clicks
                runSimulationButton.enabled = false;
                runSimulationButton.text = "Running...";
                Qt.callLater(function() {
                    Julia.run_simulation();
                });
            }
        }

    }

    JuliaSignals {
        signal simulationFinished()

        onSimulationFinished: function() {
            runSimulationButton.enabled = true;
            runSimulationButton.text = "Run Simulation";
        }
    }

}
