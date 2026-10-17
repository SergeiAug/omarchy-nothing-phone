// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
import "../plugins/spacewar.runtime/input" as SW
Item {
  width:540; height:1200
  SW.EdgeInput { id:input; anchors.fill:parent }
  SignalSpy { id:began; target:input; signalName:"began" }
  SignalSpy { id:ended; target:input; signalName:"ended" }
  TestCase {
    name:"EdgeTouch"; when:windowShown
    function init() { began.clear(); ended.clear() }
    function test_release() {
      var touch=touchEvent(input)
      touch.press(0,input,270,1188).commit()
      tryCompare(began,"count",1)
      touch.move(0,input,270,1000).commit()
      touch.release(0,input,270,1000).commit()
      tryCompare(ended,"count",1)
      compare(ended.signalArguments[0][0],false)
      compare(input.tracking,false)
    }
    function test_second_finger() {
      var touch=touchEvent(input)
      touch.press(0,input,270,1188).commit()
      tryCompare(began,"count",1)
      touch.stationary(0).press(1,input,300,1180).commit()
      tryCompare(ended,"count",1)
      compare(ended.signalArguments[0][0],true)
      compare(input.tracking,false)
      touch.release(1,input,300,1180).stationary(0).commit()
      touch.release(0,input,270,1188).commit()
      compare(ended.count,1)
      touch.press(0,input,270,1188).commit()
      tryCompare(began,"count",2)
      touch.release(0,input,270,1188).commit()
    }
    function test_disable_cancels() {
      var touch=touchEvent(input)
      touch.press(0,input,270,1188).commit()
      tryCompare(began,"count",1)
      input.enabled=false
      tryCompare(ended,"count",1)
      compare(ended.signalArguments[0][0],true)
      touch.release(0,input,270,1188).commit()
      input.enabled=true
    }
  }
}
