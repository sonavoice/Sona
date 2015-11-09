import UIKit
import QuartzCore
import Alamofire
import AudioToolbox
import CoreLocation
import AVFoundation

class HomeViewController: UIViewController, SpeechKitDelegate, SKRecognizerDelegate, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
  
  /* Mutables */
  var voiceSearch = SKRecognizer()
  var tts = TextToSpeech()
  var isListening: Bool = false
  var apps = [String]()
  var lang = "eng-USA"
  var isConfirmation: Bool = false
  var storedParameters = [String: AnyObject]()
  var userLocation = CLLocation()
  var previousTranscript = String()
  var requiresConfirmation = Bool()
  
  /* Constants */
  let userId = UIDevice.currentDevice().identifierForVendor!.UUIDString
  let appManager = AppManager()
  let locationManager = CLLocationManager()

  
  /* UI */
  @IBOutlet var transcript: UILabel!
  @IBOutlet var recordButton: RecordButton!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    self.navigationController?.navigationBar.setBackgroundImage(UIImage(), forBarMetrics: UIBarMetrics.Default)
    self.navigationController?.navigationBar.shadowImage = UIImage()
    self.navigationController?.navigationBar.translucent = true
    self.navigationController?.view.backgroundColor = UIColor.clearColor()
    
    if revealViewController() != nil {
      revealViewController().rearViewRevealWidth = 100
      
      let burgerButton = HamburgerButton(frame: CGRectMake(0, 0, 40, 40))
      burgerButton.addTarget(revealViewController(), action: "revealToggle:", forControlEvents: .TouchUpInside)
      
      self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: burgerButton)
      
      view.addGestureRecognizer(self.revealViewController().panGestureRecognizer())
    }
    
    let langMan = LanguageManager()
    let langres = langMan.getCurrentLang()
    self.lang = langres[1]
    
    transcript.numberOfLines = 0
    transcript.sizeToFit()
    
    self.tts.speaker.delegate = self
    
    /* Add Button functionality */
    createMicButtonPressFunctionality()
    
    /* Configure SpeechKit Server */
    configureNuance()
    
    /* Establish location */
    locate()
    
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  func startListening() {
    /* There are alternate options for these:
    
    detectionType(s):
    - SKLongEndOfSpeechDetection (long utterances)
    - SKShortEndOfSpeechDetection - good for search look up and short small pause utterances
    
    recoType(s):
    - SKSearchRecognizerType
    - SKTvRecognizerType - good for pauses occasionally and for messages/dictation
    - SKDictationRecognizerType - Long utterances for dictation
    
    landType(s):
    - "fr_FR"
    - "de_DE"
    
    */
    if !self.isListening {
      self.voiceSearch = SKRecognizer(type: SKDictationRecognizerType, detection: UInt(SKShortEndOfSpeechDetection), language:self.lang, delegate: self)
      self.isListening = true
    } else {
      self.voiceSearch.cancel()
      self.isListening = false
    }
  }
  
  func createMicButtonPressFunctionality() {
    self.recordButton.addTarget(self, action: "startListening", forControlEvents: .TouchUpInside)
  }
  
  func processCommand(transcript: String) {
    if (!isConfirmation) {
      if (!isValidExtension(transcript)) {
        return
      }
      let transcriptAsArray = transcript.componentsSeparatedByString(" ")
      let extensionName = appManager.scan(transcriptAsArray)
      let passport = appManager.getPassport(extensionName!)!
      
      let authDict = ["passport": passport]
      
      /* Configure final object to be sent to server as JSON */
      self.storedParameters = ["transcript": transcript, "auth": authDict, "confirmed": false, "location": self.userLocation]
    } else {
      if transcript.lowercaseString.rangeOfString("no") != nil || transcript.lowercaseString.rangeOfString("don't") != nil {
        self.tts.speak("Aborted the command.")
        return
      }
      self.storedParameters["confirmed"] = true
    }
    
    isConfirmation = false
    
    self.postCommandToServer()
  }
  
  func postCommandToServer() {
    print("posting command to server")
    Alamofire.request(.POST, "https://sonavoice.com/command", parameters: self.storedParameters as [String: AnyObject], encoding: .JSON)
      .responseJSON { response in
        switch response.result {
        case .Success:
          if let JSON = response.result.value {
            if let feedback = JSON["feedback"] as? String {
              if let requiresConfirmation = JSON["requiresConfirmation"] as? Bool {
                if let previousTranscript = JSON["previousTranscript"] as? String {
                  // feedback, requiresConfirmation, and previousTranscript extracted
                  self.processResponse(feedback, requiresConfirmation: requiresConfirmation, previousTranscript: previousTranscript)
                  return
                }
              }
            }
            print("Error extracting all arguments")
            self.tts.speak("Unable to properly parse response")
          }
          else {
            self.tts.speak("Received invalid JSON")
          }

        case .Failure:
          if let JSON = response.result.value {
            if let feedback = JSON["feedback"] as? String {
              self.tts.speak(feedback)
              return
            }
          }
          self.tts.speak("Please send help")
        }
      }

  }
  
  func processResponse(feedback: String, requiresConfirmation: Bool, previousTranscript: String) {
    self.tts.speak(feedback)
    
    if requiresConfirmation {
      self.isConfirmation = true
    } else {
      self.isConfirmation = false
    }
  }
  
  func isValidExtension(transcript: String) -> Bool {
    let transcriptAsArray = transcript.componentsSeparatedByString(" ")
    let extensionName = appManager.scan(transcriptAsArray)
    
    if extensionName == nil {
      self.tts.speak("Couldn't find anything.")
      return false
    }
    
    return true
  }
  
  /*** Nuance ***/
  func configureNuance() {
    
    SpeechKit.setupWithID("NMDPTRIAL_garrettmaring_gmail_com20151023221408", host: "sslsandbox.nmdp.nuancemobility.net", port: 443, useSSL: true, delegate: self)
    
    let earconStart = SKEarcon.earconWithName("start_listening.wav") as! SKEarcon
    let earconStop = SKEarcon.earconWithName("start_listening.wav") as! SKEarcon
    let earconCancel = SKEarcon.earconWithName("start_listening.wav") as! SKEarcon
    SpeechKit.setEarcon(earconStart, forType: UInt(SKStartRecordingEarconType))
    SpeechKit.setEarcon(earconStop, forType: UInt(SKStopRecordingEarconType))
    SpeechKit.setEarcon(earconCancel, forType: UInt(SKCancelRecordingEarconType))
  }
  
  func recognizerDidBeginRecording(recognizer: SKRecognizer!) {
    NSLog("I have started recording")
  }
  
  func recognizerDidFinishRecording(recognizer: SKRecognizer!) {
    NSLog("I have finished recording")
    voiceSearch.stopRecording()
    /* Ends animation on end of listening */
    self.recordButton.animating = false
  }
  
  func recognizer(recognizer: SKRecognizer!, didFinishWithResults results: SKRecognition!) {
    NSLog("Some results! \n %@", results.results)
    let res = results.firstResult()
    if res == nil {
      self.tts.speak("I can't hear you")
    } else {
      transcript.text! = "\"" + res + "\""
      processCommand(res)
    }
  }
  
  func recognizer(recognizer: SKRecognizer!, didFinishWithError error: NSError!, suggestion: String!) {
    NSLog("I errorred out with the following error: %@", error)
  }
  
  func audioSessionReleased() {
    self.isListening = false
    NSLog("Audio session released")
  }
  
  func handlePowerMeter() {
    /* Get power level */
  }
  
  /* Location functions and delegate */
  func locate() {
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.requestAlwaysAuthorization()
    locationManager.startUpdatingLocation()
  }
  
  func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    self.userLocation = locations[0]
  }
  
  /* SpeechSynthesizer Delegates */
  func speechSynthesizer(synthesizer: AVSpeechSynthesizer, didFinishSpeechUtterance utterance: AVSpeechUtterance) {
    if self.isConfirmation {
      self.startListening()
    }
  }
  
}
