## DBRecent Prices for Thaumaturgy Mats
Updated automatically every +/- 10m when the Blizzard API is updated.  
See timestamp in bottom of DBRecent.csv file for last update (UTC Timezone).

Note that these DBRecent values, while very close to TSM DBRecent values are not always exactly the same. These data points for DBRecent AH values can be used in spreadsheets or others places where DBRecent data is more useful than DBMarket values.
TSM Does not currently export DBRecent data on their website or API. Only In-Game via their desktop app.  

Formula for DBrecent data was taken from the [TSM Blog Post](https://support.tradeskillmaster.com/tsm-addon-documentation/auctiondb-market-value)

#### Example google apps script to automatically use this DBRecent data in your spreadsheet:  

```
function onOpen(e) {
  var ui = SpreadsheetApp.getUi();
  ui.createMenu("Update Thaumaturgy 👉️")
    .addItem("Import DBRecent Prices", "importCSVFromUrl")
    .addToUi();

  autoUpdateData();
}

// valid minutes are 1, 5, 10, 15 or 30
function autoUpdateData() {
  // Delete any existing triggers to avoid duplicates
  const triggers = ScriptApp.getProjectTriggers();
  triggers.forEach(trigger => {
    if (trigger.getHandlerFunction() === 'importCSVFromUrl') {
      ScriptApp.deleteTrigger(trigger);
    }
  });

  // Create a new trigger that runs every x minutes
  ScriptApp.newTrigger('importCSVFromUrl')
    .timeBased()
    .everyMinutes(10)
    .create();
}

// Displays an alert as a Toast message
function displayToastAlert(message) {
  SpreadsheetApp.getActive().toast(message, "⚠️ Alert"); 
}

function writeDataToSheet(data) {
  var ss = SpreadsheetApp.getActive().getSheetByName("Import");
  ss.getRange(1, 1, data.length, data[0].length).setValues(data);
  return ss.getName();
}

function importCSVFromUrl() {
  var url = "https://raw.githubusercontent.com/ninthwalker/wow_thaumaturgy/refs/heads/main/DBRecent.csv"
  var contents = Utilities.parseCsv(UrlFetchApp.fetch(url));
  var sheetName = writeDataToSheet(contents);
   displayToastAlert("DBRecent prices were successfully updated");
  //displayToastAlert(contents);
}
```
