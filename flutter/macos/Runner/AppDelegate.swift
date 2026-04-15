import Cocoa
import FlutterMacOS
import AVFoundation

@main
class AppDelegate: FlutterAppDelegate {
  var audioManager: NezAudioManager?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.nez/audio", binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "start":
        self?.audioManager = NezAudioManager()
        self?.audioManager?.start()
        result(nil)
      case "stop":
        self?.audioManager?.stop()
        self?.audioManager = nil
        result(nil)
      case "pushSamples":
        if let args = call.arguments as? FlutterStandardTypedData {
          self?.audioManager?.pushSamples(args.data)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Simple audio manager that plays PCM int16 samples at 44100 Hz.
class NezAudioManager {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let sampleRate: Double = 44100
  private let format: AVAudioFormat

  init() {
    // Use float32 format — macOS AVAudioEngine doesn't reliably support int16 on all connections
    format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
  }

  func start() {
    do {
      try engine.start()
      playerNode.play()
    } catch {
      print("NEZ Audio: failed to start engine: \(error)")
    }
  }

  func stop() {
    playerNode.stop()
    engine.stop()
  }

  func pushSamples(_ data: Data) {
    guard !data.isEmpty else { return }
    let sampleCount = data.count / 2  // input is Int16 = 2 bytes each

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else { return }
    buffer.frameLength = AVAudioFrameCount(sampleCount)

    // Convert Int16 -> Float32
    let floatPtr = buffer.floatChannelData![0]
    data.withUnsafeBytes { rawPtr in
      let int16Ptr = rawPtr.bindMemory(to: Int16.self)
      for i in 0..<sampleCount {
        floatPtr[i] = Float(int16Ptr[i]) / 32768.0
      }
    }

    playerNode.scheduleBuffer(buffer, completionHandler: nil)
  }
}
