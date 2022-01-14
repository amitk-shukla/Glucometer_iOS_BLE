Glucometer POC


Project Name: Glucometer POC

Objective- App scan for the Glucometer device once connected it will allow to sync data to Healthkit
Reference- Have implemented with Bluetooth Forum developed  standard “GATT” profile for BGMs 
Requirement- min device support is iOS 14.2
and will require user to allow bluetooth and healthkit access on device

Flow
- On first launch it will ask for Bluetooth access and healthkit access.
- Once allowed it will try to scan glucoseService enabled device
- Device scanned with glucoseService will be listed in picker shown at the bottom.
- Select device and press done button on right side of picker.
- After device is connected  Sync button on top will be enabled
- Press Sync button to sync data to healthkit.

In case any problem you can check Logs shown on the textfield in between



Component Description:
Have created POC with following classes:
ViewController - for showing UI with Sync button for syncing glucose to healthkit, Textfield for showing logs, and Picker for scanned devices
GlucoseRecord - For getting/calculating data from bluetooth
HealthKitManager - For Authorization and handling healthkit query.
BLE - For handling Bluetooth scan delegates

Configuration(if any):
Will need to add bluetooth and healthkit access description info in plist.

Last Updated:
4June2021