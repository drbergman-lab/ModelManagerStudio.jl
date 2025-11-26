import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts
import jlqml

ApplicationWindow {
    id: mainWindow

    property var fontSizeOfLevel: [20, 18, 14, 12, 10]

    title: "PhysiCellModelManager.jl GUI"
    width: 800
    height: 600
    visible: true

    // Add keyboard shortcut for Command+W to close the window
    Shortcut {
        sequences: [StandardKey.Close] // This maps to Cmd+W on macOS
        onActivated: mainWindow.close()
    }

    SystemPalette {
        id: syscolors

        colorGroup: SystemPalette.Active
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        anchors.margins: 10

        // Simulated tab bar
        Rectangle {
            color: guiproperties.color_top
            Layout.fillWidth: true
            Layout.preferredHeight: 40

            RowLayout {
                id: tabBar

                property int currentIndex: 0 // Track the currently selected tab index

                spacing: 0
                anchors.centerIn: parent

                Component {
                    id: tabButtonComponent

                    RoundButton {
                        id: button

                        property int index: -1 // Allow access to the index of the tab

                        text: "test"
                        font.bold: true
                        font.underline: index === tabBar.currentIndex // Underline the current tab
                        font.pixelSize: mainWindow.fontSizeOfLevel[2]
                        onClicked: {
                            tabBar.currentIndex = index; // Update the current index when clicked
                        }

                        background: Rectangle {
                            id: background

                            color: index === tabBar.currentIndex ? guiproperties.color_button : "#ffffff" // Change color based on current index
                            implicitWidth: 100
                            implicitHeight: 25
                            border.width: 2
                            border.color: index === tabBar.currentIndex ? "#000000" : "#a0a0a0" // Darker border for selected tab
                            radius: 4
                        }

                    }

                }

                Repeater {
                    model: ["Inputs", "Variations"]

                    delegate: Loader {
                        id: tabLoader

                        onLoaded: {
                            item.text = modelData; // Set the text based on the model data
                            item.index = index; // Set the index for the tab
                        }
                        sourceComponent: tabButtonComponent
                    }

                }

            }

        }

        // Content area
        StackLayout {
            id: stack

            currentIndex: tabBar.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Inputs tab
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#f0f0f0"

                ColumnLayout {
                    spacing: 10 // Reduced spacing for more compact vertical layout
                    anchors.centerIn: parent
                    anchors.fill: parent

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

                            signal comboChanged(string newText)

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

                                        onCurrentTextChanged: {
                                            // Update the varied state when the current text changes
                                            locationItem.isVaried = Julia.is_varied_location(locationItem.location, locationItem.comboBox.currentText);
                                            locationItem.comboChanged(currentText);
                                        }
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.preferredWidth: 180
                                        font.pixelSize: mainWindow.fontSizeOfLevel[level]
                                    }

                                }

                            }

                        }

                    }

                    // Required Locations
                    Text {
                        text: "Required Locations"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        font.underline: true
                        Layout.alignment: Qt.AlignCenter
                    }

                    GridLayout {
                        id: reqGridLayout

                        Layout.alignment: Qt.AlignCenter
                        rows: project_configuration_properties.req_n_rows
                        columns: project_configuration_properties.req_n_cols
                        flow: GridLayout.TopToBottom

                        Repeater {
                            id: requiredLocationsRepeater

                            model: reqLocModel

                            delegate: Loader {
                                id: requiredLocationLoader

                                sourceComponent: locationComponent
                                onLoaded: {
                                    item.labelText = labelText;
                                    item.location = location; // Convert to a suitable location name
                                    item.isVaried = false; // Set varied state
                                    item.isRequired = true; // Set required state
                                    item.comboChanged.connect(function(newText) {
                                        folder = newText; // Update the folder variable
                                    });
                                    item.comboBox.updateFolders(); // Update folders in the combo box
                                }
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
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                    }

                    GridLayout {
                        id: optGridLayout

                        Layout.alignment: Qt.AlignCenter
                        rows: project_configuration_properties.opt_n_rows
                        columns: project_configuration_properties.opt_n_cols
                        flow: GridLayout.TopToBottom

                        Repeater {
                            id: optionalLocationsRepeater

                            model: optLocModel

                            delegate: Loader {
                                id: optionalLocationLoader

                                sourceComponent: locationComponent
                                onLoaded: {
                                    item.labelText = labelText;
                                    item.location = location; // Convert to a suitable location name
                                    item.isVaried = false; // Set varied state
                                    item.isRequired = false; // Set required state
                                    item.comboChanged.connect(function(newText) {
                                        folder = newText; // Update the folder variable
                                    });
                                    item.comboBox.updateFolders(); // Update folders in the combo box
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
                            Julia.set_input_folders();
                            // Update the display to show current selections
                            requiredLocationsDisplay.updateFolderDisplay();
                            optionalLocationsDisplay.updateFolderDisplay();
                            // Hide the placeholder text and show the inputs display
                            inputsPlaceholderText.visible = false;
                            inputsDisplay.visible = true;
                            variedLocationComboBox.model = Julia.get_varied_locations();
                            currentVariationTargetText.updateVariationTarget(); // Update the target text
                            if (runSimulationButton.enabled === false) {
                                runSimulationButton.enabled = true; // Enable the run simulation button
                                runSimulationButton.disabledText = "Running...";
                            }
                        }
                    }

                    // Current inputs display
                    ColumnLayout {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.leftMargin: 50
                        Layout.rightMargin: 50

                        Text {
                            text: "Current Inputs"
                            font.bold: true
                            font.pixelSize: mainWindow.fontSizeOfLevel[1]
                            color: syscolors.text
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            // Layout.fillHeight: true
                            implicitHeight: inputsDisplay.implicitHeight + 20
                            color: "#fafafa"
                            radius: 6
                            border.color: "#a0a0a0"
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
                                        let temp_mod = [];
                                        for (let i = 0; i < requiredLocationsRepeater.count; ++i) {
                                            let item = requiredLocationsRepeater.itemAt(i).item;
                                            temp_mod.push({
                                                "name": item.labelText,
                                                "value": Julia.get_input_folder(item.location)
                                            });
                                        }
                                        requiredFoldersRepeater.model = temp_mod;
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
                                        let temp_mod = [];
                                        for (let i = 0; i < optionalLocationsRepeater.count; ++i) {
                                            let item = optionalLocationsRepeater.itemAt(i).item;
                                            temp_mod.push({
                                                "name": item.labelText,
                                                "value": Julia.get_input_folder(item.location)
                                            });
                                        }
                                        optionalFoldersRepeater.model = temp_mod;
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

            }

            // Variations tab
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#f0f0f0"

                ColumnLayout {
                    spacing: 10 // Reduced spacing for more compact vertical layout
                    anchors.centerIn: parent
                    anchors.fill: parent

                    Text {
                        text: "Variation target"
                        color: syscolors.text
                        font.bold: true
                        font.pixelSize: mainWindow.fontSizeOfLevel[1]
                        Layout.alignment: Qt.AlignLeft
                        Layout.leftMargin: 0
                    }

                    // Variation target box
                    Rectangle {
                        property int padding: 12

                        Layout.alignment: Qt.AlignCenter
                        Layout.fillWidth: true
                        color: "#fafafa"
                        radius: 6
                        border.color: "#a0a0a0"
                        border.width: 2
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
                                        id: comboRow

                                        spacing: 5

                                        ComboBox {
                                            id: variedLocationComboBox

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
                                                tokenComboBoxRepeater.itemAt(0).model = Julia.get_next_model(variedLocationComboBox.currentText);
                                                tokenComboBoxRepeater.itemAt(0).modelChanged(); // Force update in case the model is the same
                                            }

                                            Text {
                                                id: dummyTextItemLocation

                                                visible: false
                                                font: variedLocationComboBox.font
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
                                                    var tokens = [variedLocationComboBox.currentText];
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
                                color: "#ffffff"
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
                                            var tokens = [variedLocationComboBox.currentText];
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
                                        font.pixelSize: mainWindow.fontSizeOfLevel[3]
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
                            Layout.leftMargin: 0
                        }

                        // Variation values input box
                        Rectangle {
                            id: variationValuesRectangle

                            Layout.fillWidth: true
                            Layout.preferredHeight: variationValuesInput.implicitHeight + 24
                            Layout.topMargin: 0
                            color: "#ffffff"
                            border.color: "#dddddd"
                            border.width: 1
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
                                var tokens = [currentVariationTargetText.text, variationValuesInput.text];
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
                            text: "Current variations"
                            color: syscolors.text
                            font.bold: true
                            font.pixelSize: mainWindow.fontSizeOfLevel[1]
                            Layout.alignment: Qt.AlignLeft
                            Layout.leftMargin: 0
                        }

                        // Current variations rectangle
                        Flickable {
                            id: currentVariationsFlickable

                            property var currentVariations: Julia.get_current_variations()

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.fill: parent
                                color: "#fafafa"
                                radius: 6
                                border.color: "#a0a0a0"
                                border.width: 2

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

        }

        // Bottom bar with Run Simulation button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: guiproperties.color_bottom

            // Run Simulation
            Button {
                id: runSimulationButton

                property string disabledText: "Create inputs first..."

                anchors.centerIn: parent
                implicitHeight: 45
                implicitWidth: 200
                text: enabled ? "Run Simulation" : disabledText
                font.pixelSize: mainWindow.fontSizeOfLevel[1]
                font.bold: true
                enabled: false
                onClicked: {
                    // Call Julia function to run the simulation
                    // Disable button to prevent multiple clicks
                    enabled = false;
                    start_run_timer.start();
                }
            }

            Timer {
                id: start_run_timer

                running: false
                interval: 10 // 10 millisecond delay before running the simulation
                repeat: false
                onTriggered: Julia.run_simulation()
            }

        }

    }

    JuliaSignals {
        signal simulationFinished()

        onSimulationFinished: runSimulationButton.enabled = true
    }

    Timer {
        id: testingTimer

        running: testing.testing
        onTriggered: Qt.exit(0)
    }

}
