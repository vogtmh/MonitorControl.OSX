//
//  AppDelegate.swift
//  MonitorControl.OSX
//
//  Created by Mathew Kurian on 9/26/16.
//  Copyright © 2016 Mathew Kurian. All rights reserved.
//

import Cocoa
import Foundation

struct Display {
    var id: CGDirectDisplayID
    var name: String
    var serial: String
}

var app: AppDelegate! = nil
let prefs = UserDefaults.standard

func ddcctl(monitor: CGDirectDisplayID, command: Int32, value: Int) {
    var wrcmd = DDCWriteCommand(control_id: UInt8(command), new_value: UInt8(value))
    DDCWrite(monitor, &wrcmd)
    print(value)
}

class SliderHandler : NSObject {
    var display : Display
    var command : Int32 = 0

    public init(display: Display, command: Int32) {
        self.display = display
        self.command = command
    }

    func valueChanged(slider: NSSlider) {
        let snapInterval = 25
        let snapThreshold = 3

        var value = slider.integerValue

        let closest = (value + snapInterval / 2) / snapInterval * snapInterval
        if abs(closest - value) <= snapThreshold {
            value = closest
            slider.integerValue = value
        }

        ddcctl(monitor: display.id, command: command, value: value)

        prefs.setValue(value, forKey: "\(command)-\(display.serial)")
        prefs.synchronize()
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var window: NSWindow!
    
    let statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)

    var monitorItems: [NSMenuItem] = []
    var displays: [Display] = []
    var sliderHandlers: [SliderHandler] = []

    var defaultDisplay: Display! = nil
    var defaultBrightnessSlider: NSSlider! = nil
    var defaultVolumeSlider: NSSlider! = nil

    @IBAction func quitClicked(_ sender: AnyObject) {
        NSApplication.shared().terminate(self)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        app = self

        //statusItem.title = "♨"
        let icon = NSImage(named: "statusIcon")
        icon?.isTemplate = true // best for dark mode
        statusItem.image = icon
        statusItem.menu = statusMenu

        acquirePrivileges()

        CGDisplayRegisterReconfigurationCallback({_,_,_ in app.updateDisplays()}, nil)
        updateDisplays()

        NSEvent.addGlobalMonitorForEvents(
            matching: NSEventMask.keyDown, handler: {(event: NSEvent) in
                if self.defaultDisplay == nil {
                    return
                }

                let modifiers = NSEventModifierFlags.init(rawValue: NSEventModifierFlags.command.rawValue |
                    NSEventModifierFlags.control.rawValue |
                    NSEventModifierFlags.option.rawValue |
                    NSEventModifierFlags.shift.rawValue)
                var flags = event.modifierFlags.intersection(modifiers)

                if !flags.contains(NSEventModifierFlags.command) {
                    return
                }
                flags.subtract(NSEventModifierFlags.command)

                var rel = 0
                if event.keyCode == 27 {
                    rel = -5
                } else if event.keyCode == 24 {
                    rel = +5
                } else {
                    return
                }

                var command = Int32()
                var slider: NSSlider! = nil
                if flags == NSEventModifierFlags.option {
                    command = AUDIO_SPEAKER_VOLUME
                    slider = self.defaultVolumeSlider
                } else {
                    return
                }

                let k = "\(command)-\(self.defaultDisplay.serial)"
                let value = max(0, min(100, prefs.integer(forKey: k) + rel))

                prefs.setValue(value, forKey: k)
                prefs.synchronize()
                slider.intValue = Int32(value)

                ddcctl(monitor: self.defaultDisplay.id, command: command, value: value)
        })
    }

    func makeLabel(text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isBordered = false
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        return label
    }

    func addSliderItem(menu: NSMenu, isDefaultDisplay: Bool, display: Display, command: Int32, title: String, shortcut: String) -> NSSlider {
        let item = NSMenuItem()

        let view = NSView(frame: NSRect(x: 0, y: 5, width: 250, height: 40))

        let label = makeLabel(text: title, frame: NSRect(x: 20, y: 19, width: 130, height: 20))

        let labelKeyCode = makeLabel(text: shortcut, frame: NSRect(x: 120, y: 19, width: 100, height: 20))
        labelKeyCode.isHidden = !isDefaultDisplay
        labelKeyCode.alignment = NSTextAlignment.right

        let handler = SliderHandler(display: display, command: command)
        sliderHandlers.append(handler)

        let slider = NSSlider(frame: NSRect(x: 20, y: 0, width: 200, height: 19))
        slider.target = handler
        slider.minValue = 0
        slider.maxValue = 100
        slider.integerValue = prefs.integer(forKey: "\(command)-\(display.serial)")
        slider.action = #selector(SliderHandler.valueChanged)

        view.addSubview(label)
        view.addSubview(labelKeyCode)
        view.addSubview(slider)

        item.view = view

        menu.addItem(item)
        menu.addItem(NSMenuItem.separator())

        return slider
    }
    
    func addVerticalSliderItem(menu: NSMenu, isDefaultDisplay: Bool, display: Display, command: Int32, title: String, shortcut: String) -> NSSlider {
        let item = NSMenuItem()
        
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 250))
        
        //let label = makeLabel(text: title, frame: NSRect(x: 20, y: 19, width: 130, height: 20))
        
        //let labelKeyCode = makeLabel(text: shortcut, frame: NSRect(x: 120, y: 19, width: 100, height: 20))
        //labelKeyCode.isHidden = !isDefaultDisplay
        //labelKeyCode.alignment = NSTextAlignment.right
        
        let handler = SliderHandler(display: display, command: command)
        sliderHandlers.append(handler)
        
        let slider = NSSlider(frame: NSRect(x: 15, y: 0, width: 20, height: 250))
        slider.target = handler
        slider.minValue = 0
        slider.maxValue = 100
        slider.integerValue = prefs.integer(forKey: "\(command)-\(display.serial)")
        slider.action = #selector(SliderHandler.valueChanged)
        
        //view.addSubview(label)
        //view.addSubview(labelKeyCode)
        view.addSubview(slider)
        
        item.view = view
        
        menu.addItem(item)
        //menu.addItem(NSMenuItem.separator())
        
        return slider
    }

    func updateDisplays() {
        defaultDisplay = nil
        defaultBrightnessSlider = nil
        defaultVolumeSlider = nil

        /*
        for m in monitorItems {
            statusMenu.removeItem(m)
        }
        */
        // Removes all previous sliders to prevent multiple ones
        statusMenu.removeAllItems()
        // Recreates Quit Button
        let quitMenu = NSMenuItem(title: "Q", action: "quitClicked:", keyEquivalent: "")
        statusMenu.addItem(quitMenu)
        monitorItems = []
        displays = []
        sliderHandlers = []
        sleep(1)

        for s in NSScreen.screens()! {
            let id = s.deviceDescription["NSScreenNumber"] as! CGDirectDisplayID
            if CGDisplayIsBuiltin(id) != 0 {
                continue
            }

            var edid = EDID()
            if !EDIDTest(id, &edid) {
                continue
            }

            let name = getDisplayName(edid)
            let serial = getDisplaySerial(edid)

            let isDefaultDisplay = defaultDisplay == nil

            let d = Display(id: id, name: name, serial: serial)
            displays.append(d)

            let volumeSlider = addVerticalSliderItem(menu: statusMenu, isDefaultDisplay: isDefaultDisplay, display: d, command: AUDIO_SPEAKER_VOLUME, title: "Volume", shortcut: "")

            let defaultMonitorItem = NSMenuItem()
            let defaultMonitorView = NSView(frame: NSRect(x: 0, y: 5, width: 250, height: 25))

            let defaultMonitorSelectButtom = NSButton(frame: NSRect(x: 25, y: 0, width: 200, height: 25))
            defaultMonitorSelectButtom.title = isDefaultDisplay ? "Default" : "Set as default"
            defaultMonitorSelectButtom.bezelStyle = NSRoundRectBezelStyle
            defaultMonitorSelectButtom.isEnabled = !isDefaultDisplay

            defaultMonitorView.addSubview(defaultMonitorSelectButtom)

            defaultMonitorItem.view = defaultMonitorView

        }

    }
    
    func acquirePrivileges() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessibilityEnabled {
            print("You need to enable the keylogger in the System Prefrences")
        }
        
        return
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func edidString(_ d: descriptor) -> String {
        var s = ""
        for (_, b) in Mirror(reflecting: d.text.data).children {
            let b = b as! Int8
            let c = Character(UnicodeScalar(UInt8(bitPattern: b)))
            if c == "\0" || c == "\n" {
                break
            }
            s.append(c)
        }
        return s
    }

    func getDescriptorString(_ edid: EDID, _ type: UInt8) -> String? {
        for (_, d) in Mirror(reflecting: edid.descriptors).children {
            let d = d as! descriptor
            if d.text.type == UInt8(type) {
                return edidString(d)
            }
        }

        return nil
    }

    func getDisplayName(_ edid: EDID) -> String {
        return getDescriptorString(edid, 0xFC) ?? "Display"
    }

    func getDisplaySerial(_ edid: EDID) -> String {
        return getDescriptorString(edid, 0xFF) ?? "Unknown"
    }
}
