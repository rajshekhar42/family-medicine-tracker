Medicine Tracker App — Requirements Document

A personalized medicine tracker that helps users log and manage their own medications, and lets family members monitor each other's adherence across locations. The core value proposition (Phase 3) is a cross-border care system — e.g., a parent logs their medication, and their child in another location can log in and check adherence in real time.
1. First Time Launch Screen
Logo
Tagline: "Track every medicine dose—for yourself, your family, and your loved ones"
User Input:
Profile Name
Select Time Zone
On Save:
Store Profile Name and Time Zone in Profile table in local data store
Navigate to Home Screen
Note: Refer here for Profile table schema. 

2. Home Screen
2.1 Header
Profile icon (left top)
"Today" title (center top) — changes based on date selected in Weekly Date Strip. Other possible values: "Tomorrow", "Yesterday", or a specific date (format: 28 July)
Calendar icon (right top) — opens full calendar view
On selecting a date in the full calendar view, that date becomes the center of the Weekly Date Strip, displaying its corresponding week
2.2 Weekly Date Strip
Shows 7 days: Sun–Sat
Each day displays the date number below the day name
Today's date is centered and highlighted with a circle — next 3 days to the right, previous 3 days to the left
Tap on any day to switch the selected date
2.3 Time-Grouped Medication List
Blank state: shows centered message — "Tap the plus button below to add a medicine to your schedule"
Medications are grouped by dose time (e.g., 10 AM, 2 PM)
Each medication card shows:
"Skip" action button on the left (or swipe left to skip)
Medication icon beside medication name (tablet, capsule, syrup, powder, cream)
Medication name + dosage (e.g., "7.5 mg")
Frequency (e.g., "Daily")
Quantity/form (e.g., "1 Tab", "1 cap")
"Take" action button on the right (or swipe right to take)
On clicking "Take" or "Skip", the action is stored in the MedicineLog table accordingly
2.4 Floating Action Button
"+" button anchored bottom-right
Opens "Add Medication Screen" to create a new medication entry
3. Add Medication Screen
3.1 Medication Details
Medicine Name
Select Type
(Optional) mg — only if selected Type is Tablet or Capsule
Quantity — quantity unit populated based on selected Type
Select Frequency
3.2 Schedules
Time Slot 1 — (based on Frequency selected, capture that many number of time slots)
Duration:
Start Date
End Date — optional; displays "Continuous" if no end date is selected
Save Medication button
3.3 Possible Types
Tablet
Capsule
Syrup
Powder
Cream
Injection

3.4 Possible Frequencies
Once a Day
2 times, Daily
3 times, Daily
X times, Daily
Once a Week
X times a Week
Once a Month
X times a Month

X -> is input entered by user

3.5 Type → Quantity Unit Mapping, Dosage Unit Mapping
On selecting the Type, the unit auto-fills in both the dosage section and quantity section. The user only inputs the dosage value and quantity (where applicable); the unit/extension populates automatically.Maintain Type and unit mapping with below configuration which will be provided via Firebase Remote Config->
{
  "medTypeUnits": [
    {
      "id": "tablet",
      "displayName": "Tablet",
      "fields": {
        "dosage": {
          "enabled": true,
          "units": ["mg", "mcg", "g"]
        },
        "quantity": {
          "enabled": true,
          "units": ["tab"]
        }
      }
    },
    {
      "id": "capsule",
      "displayName": "Capsule",
      "fields": {
        "dosage": {
          "enabled": true,
          "units": ["mg", "mcg", "g"]
        },
        "quantity": {
          "enabled": true,
          "units": ["cap"]
        }
      }
    }
  ]
}


3.6 Save Behavior
On Save:
Save medication and schedule data in Medicines and Schedule tables respectively (local store)
If logged in via Google OAuth and Google Drive access is granted, sync the same medication and schedule data to the Medicines and Schedule sheets in the Google Spreadsheet
Note: Refer here for Medicines and Schedule table schema, and Google Spreadsheet schema. (see Section 6 below)

4. Medicines List Screen
Should show All medicines (active + inactive)
Have ability to edit medicines.
This screen will list medicines for the current profile only. 
Medicine List for family member's profile will be different from the logged in profile.

5. View History Screen
View history by date
View history by Medicine


6. Profile Menu
Opens on click of Profile icon. Menu items:
6.1 Menu Item,Type,Notes
Raj shekhar,Label,Profile name
MedicineList,Clickable,Opens Medicines List Screen
ViewHistory,Clickable,Opens View History Screen
Track Family members,Divider,Section separator
Login,Clickable,Google OAuth + Google Drive access functionality
Nana,Clickable,Profile name — shown if this profile exists in Google Drive
    Medicine log for that profile - Sub menu - opens the same as View History Screen
    Medicine schedule - Sub menu - opens the same as View Medicine Screen
    List of medicines - Sub menu - opens the same as View Medicine List Screen

Brother,Clickable,Profile name — shown if this profile exists in Google Drive
    Medicine log for that profile - Sub menu - opens the same as View History Screen
    Medicine schedule - Sub menu - opens the same as View Medicine Screen
    List of medicines - Sub menu - opens the same as View Medicine List Screen

Settings,Clickable - opens the settings page


6.2 Login and sync -> 
Login via Firebase Authentication using Google OAuth, requesting the Google Drive scope.
Why Google drive
The spreadsheet acts as the application's cloud datastore.App will sync all the local data to the google spreadsheet.
On first login and google drive access, the app creates a dedicated folder(MedicineTrackerApp) if it does not exist + also creates Google SpreadSheet inside this folder with the name of the profile.
 Family Monitoring (Core Differentiator)
A family member (e.g., a child) logs in with the same Google account.
It will sync all the profiles data (medicines, schedule, log) in the local data store on first login and on subsequent logins, it will sync only the data that is changed.
It should create respective tables with suffix _profileName (e.g., Medicines_nana, Schedule_nana, MedicineLog_nana, Profiles_nana, etc)

So there are 2 types of sync->
1.Sync from localdatabase to cloud storage -> whenever there is an add/update medicine, take/skip medicine or to mark skip after configured time.
2.Sync from cloud storage data to local data store for family members data


The app lists all profiles found in that Google Drive account under the 'Track Family members' in profile menu.
Selecting a profile shows:
List of medicines
Medicine schedule
Medicine log for that profile
The viewer can also add/update medicine details and schedules for that profile.
7. Data Model (Google Sheets as Data Store)
7.1 Sheet: Medicines
Primary key: MedicineID
MedicineID,Name,Type,Dosage,Quantity,Frequency,Start Date,End Date,Notes,Active
M001,Prednisol,Tablet,7.5 mg,1,1,01-Jul-26,,After breakfast,TRUE
M002,Benadryl DR,Syrup,10 ml,,2,01-Jul-26,,,TRUE
M003,Vit-D,Powder,,1,1,01-Jul-26,,,TRUE
M004,Lozisoft,Cream,,,3,01-Jul-26,,Apply externally,TRUE

7.2 Sheet: Schedule
Primary key: ScheduleID · Foreign key: MedicineID
ScheduleID,MedicineID,Time
S001,M001,10:00 AM
S002,M002,2:00 PM
S003,M002,10:00 PM
S004,M003,5:00 PM
S005,M004,9:00 AM
S006,M004,3:00 PM
S007,M004,11:00 PM

7.3 Sheet: MedicineLog
Primary key: LogID · Foreign key: ScheduleID
LogID,Date,ScheduleID,Status,Taken At
L001,01-Jul-26,S001,Taken,10:05 AM
L002,01-Jul-26,S002,Skipped,
L003,01-Jul-26,S005,Taken,9:02 AM

7.4 Sheet: Profile
Primary key: ProfileId · Unique key: ProfileName
ProfileId,ProfileName,TimeZone,LastSync

8.Settings
8.1 Notifications
Reminder Time
Reminder Sound
Snooze Duration

8.2 Account
Sign Out

8.3 Application
App Version
Privacy Policy
