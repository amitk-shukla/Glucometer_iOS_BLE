//
//  BLE.swift
//  Glucometer
//  This class is the driver for the Bluetooth Low Energy BLE interface to a glucometer
//
//  Created by Devendra on 10/15/18.
//  This code is provided for the purpose of demonstration. Use is entirely at your own risk. No warranty is provided. No license for use in a commercial product.
//

import Foundation
import CoreBluetooth

// Protocol to allow BLE event notification in ViewController
protocol BLEProtocol {
    func BLEactivated(state: Bool)
    func BLEfoundPeripheral(device: CBPeripheral, rssi: Int)
    func BLEready(RACPcharacteristic: CBCharacteristic )
    func BLEdataRx(data:[ ([Int], [Int], String) ])
}


struct  ExtPeripheral {
    var name:String
    var manufacturaName:String
    var lastRSSI:NSNumber
    var peripheral:CBPeripheral
}

private enum BlueToothGATTServices: UInt16 {
    case BatteryService         = 0x180F
    case DeviceInformation      = 0x180A
    case HeartRate              = 0x180D
    case CyclingPower           = 0x1818
    case CyclingSpeedandCadence = 0x1816
    case RunningSpeedandCadence = 0x1814
    case ManufacturaNameString  = 0x2A29
    
    var UUID: CBUUID {
        return CBUUID(string: String(self.rawValue, radix: 16, uppercase: true))
    }
}


enum Bit: UInt8, CustomStringConvertible {
    case zero, one

    var description: String {
        switch self {
        case .one:
            return "1"
        case .zero:
            return "0"
        }
    }
}


let supportedServicesWeAreInterestedIn = [
    BlueToothGATTServices.DeviceInformation.UUID, BlueToothGATTServices.CyclingSpeedandCadence.UUID
]

class BLE: NSObject {
    
    let tempDeviceID: String = "tempDeviceIDValue"
    
    var delegate: BLEProtocol?
    
    // Members to interact with the Model
    var dataReceived: ([Int], [Int], String) = ([], [],"") // tuple for a single glucose reading
    var receivedDataSet: [ ([Int], [Int], String) ] = [] // Array of tuples with (measurement, context, device ID) as the payload
 
    // Members related to BLE
    let glucoseServiceCBUUID = CBUUID(string: "0x1808")
    private var isScanning = false
    let glucoseMeasurementCharacteristicCBUUID = CBUUID(string: "0x2A18")
    let glucoseMeasurementContextCharacteristicCBUUID = CBUUID(string: "0x2A34")
    let glucoseFeatureCharacteristicCBUUID = CBUUID(string: "0x2A51")
    let recordAccessControlPointCharacteristicCBUUID = CBUUID(string: "0x2A52")
    private var activePeripherals = Dictionary<String,ExtPeripheral>()
    private var discoveredPeripherals:[ExtPeripheral]?
    private var onlyConnectWithoutDataAccess = false
    var updateList: ((_ list:[ExtPeripheral])->())?
    var updateConnectionStatus: ((_ peripheralState:CBPeripheralState)->())?
    // Members
    var centralManager: CBCentralManager!
    var glucosePeripheral: CBPeripheral?
    
    static let shared = BLE()
    
    override init() {
        super.init()
        activePeripherals = [:]
       // self.startBLE()
        
    }
    
    
    func startBLE() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func scan() {
        self.discoveredPeripherals = []
        self.isScanning = true
        centralManager.scanForPeripherals(withServices: [glucoseServiceCBUUID]) // [glucoseServiceCBUUID]if BLE is powered, kick off scan for BGMs
    }
    
    func connect(peripheral: CBPeripheral) {
        centralManager.stopScan()
        centralManager.connect(peripheral)
    }
    
//    public func startScanForDevices() {
//
//        self.discoveredPeripherals = []
//        self.isScanning = true
//        self.updateList?(self.discoveredPeripherals!)
//
//
//        //check to be in power on state
//        if (centralManager.state==CBManagerState.poweredOn) {
//            //centralManager.scanForPeripherals(withServices:supportedServicesWeAreInterestedIn, options: nil)
//            centralManager.scanForPeripherals(withServices:nil, options: nil)
//        }  else {
//            // wait 2 seconds and try again
//            // todo check if this is needed
//            let _ = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
//                self.centralManager.scanForPeripherals(withServices:nil, options: nil)
//            }
//        }
//    }
    
    func getListOfConnectedPeripherals() -> [String:ExtPeripheral] {
        let services = [BlueToothGATTServices.DeviceInformation.UUID]
        let conDev = self.centralManager.retrieveConnectedPeripherals(withServices:  services)
        conDev.forEach{ item in
            let identifier = item.identifier.uuidString
            if activePeripherals[identifier] == nil {  // ask if already existing
                activePeripherals[identifier] = ExtPeripheral(name: item.name ?? "", manufacturaName : "", lastRSSI: 0, peripheral: item)
            }
        }
        return activePeripherals
    }
    
    public func tryToConnectToPeripheral (uuid : UUID) {
        self.onlyConnectWithoutDataAccess = true
       print("BTManager: try to connect to =>> \(uuid)")
        for p:AnyObject in self.centralManager.retrievePeripherals(withIdentifiers: [uuid]) {
            if p is CBPeripheral {
                //self.powerMonitor = p as? CBPeripheral
                //if (self.powerMonitor != nil) {
                //    self.centralManager.connect(self.powerMonitor!, options: nil)
                //}
                if let sensor = p as? CBPeripheral {
                    sensor.delegate = self
                    self.centralManager.connect(sensor, options: nil)
                }
            }
        }
    }
    
    // Write 1 byte message to the BLE peripheral
    func doWrite(peripheral: CBPeripheral, characteristic: CBCharacteristic, message: [UInt8]) {
        
        let data = NSData(bytes: message, length: message.count)
        peripheral.writeValue(data as Data, for: characteristic, type: .withResponse)
    }
    
    public func stopScanning() {
        if (self.isScanning) {
            self.isScanning = false
            self.centralManager.stopScan()
        }
    }
    
    
    public func getRegisteredPeripheral() -> UUID? {
        let defaults = UserDefaults(suiteName: "group.plan2peak.com.aw.userdefaults")
        if let storedPeripheralUUID = defaults?.string(forKey: "activeBtPeripheralUUID") {
            return (NSUUID(uuidString:storedPeripheralUUID) as UUID?)
        } else {
            return nil
        }
    }
    
    public func registerPeripheralAsPowerSensor(_ per : ExtPeripheral) {
        let defaults = UserDefaults(suiteName: "group.plan2peak.com.aw.userdefaults")
        defaults?.set(per.peripheral.identifier.uuidString, forKey: "activeBtPeripheralUUID")
        defaults?.set(per.manufacturaName, forKey: "manufacturaName")
    }
    
}

// Delegate functions to manage Central
extension BLE: CBCentralManagerDelegate {
    
    // This is the delegate when starting centralManager
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        let state: Bool = central.state == .poweredOn ? true : false
        delegate?.BLEactivated(state: state)
    }
    
    // Scan found a peripheral delegate
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {

        glucosePeripheral = peripheral
        glucosePeripheral?.delegate = self
        delegate?.BLEfoundPeripheral(device: peripheral, rssi: RSSI.intValue)
        for (index, foundPeripheral) in discoveredPeripherals!.enumerated(){
            if foundPeripheral.peripheral.identifier == peripheral.identifier{
                discoveredPeripherals![index].lastRSSI = RSSI
                return
            }
        }
        
        let sensorName:String
        if let localName:String = advertisementData[CBAdvertisementDataLocalNameKey] as! String? {
            sensorName = localName
        } else if let localName:String = peripheral.name{
            sensorName = localName
        } else {
            sensorName = "No Device Name"
        }
        
        let displayPeripheral:ExtPeripheral = ExtPeripheral(name: sensorName, manufacturaName : "", lastRSSI: RSSI, peripheral: peripheral)
        discoveredPeripherals!.append(displayPeripheral)
        self.updateList?(self.discoveredPeripherals!)
        
    }
    
    
    // Triggered when Connection happens to peripheral delegate function
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        glucosePeripheral?.discoverServices([glucoseServiceCBUUID]) // Now look for glucose services offered by the glucometer
    }
    
}


// Delegate functions to manage Peripheral
extension BLE: CBPeripheralDelegate {
    
    // Discovered services
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service) // Now find the Characteristics of these Services
            
        }
    }
    
    // Discovered characteristics for a service
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        
        guard let characteristics = service.characteristics else { return }
        
        // Set notifications for glucose measurement and context
        // 0x2a18 is glucose measurement, 0x2a34 is context, 0x2a52 is RACP
        for characteristic in characteristics {
            
            if (characteristic.uuid == glucoseMeasurementCharacteristicCBUUID ||
                characteristic.uuid == glucoseMeasurementContextCharacteristicCBUUID ||
                characteristic.uuid == recordAccessControlPointCharacteristicCBUUID) {
                
                peripheral.setNotifyValue(true, for: characteristic)
            }
            
            if (characteristic.uuid == recordAccessControlPointCharacteristicCBUUID) {
                delegate?.BLEready(RACPcharacteristic: characteristic)
            }
        }
        
    }
    
    
    // For notified characteristics, here's the triggered method when a value comes in from the Peripheral
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        
        if let dataBuffer: Data = characteristic.value {
            let buffLen: Int = dataBuffer.count
            
            var dataInArray = [UInt8](repeating:0, count:buffLen)
            dataBuffer.copyBytes(to: &dataInArray, count: buffLen)
            
            // Turn input stream of UInt8 to an array of Ints so that can use standard methods in Model
            var outputDataArray:[Int] = []
            
            for byte in dataInArray {
                outputDataArray.append(Int(byte))
            }
            
            
            switch characteristic.uuid {
                
            case glucoseMeasurementCharacteristicCBUUID:
                // Glucose measurement value
                dataReceived.0 = outputDataArray
                dataReceived.2 = tempDeviceID
                
                if (outputDataArray[0] & 0b10000) == 0 {
                    // No context attached, just do the write
                    receivedDataSet.append(dataReceived)
                    dataReceived = ([],[], "") // reset the received tuple
                }
                
            case glucoseMeasurementContextCharacteristicCBUUID:
                // Glucose context value
                dataReceived.1 = outputDataArray
                receivedDataSet.append(dataReceived)
                dataReceived = ([],[], "") // reset the received tuple
                
            case recordAccessControlPointCharacteristicCBUUID:
                // RACP. Transfer complete. Write to Model.
                
                delegate?.BLEdataRx(data: receivedDataSet)
                
            default:
                print ("Default")
            }
            
        }
        
    }
    
}
