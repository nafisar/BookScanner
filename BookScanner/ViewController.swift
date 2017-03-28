//
//  ViewController.swift
//  BookScanner
//
//  Created by Nafisa Rahman on 3/23/17.
//  Copyright © 2017 Nafisa. All rights reserved.
//

import UIKit
import AVFoundation
import Speech
import AlamofireImage
import Alamofire

class ViewController: UIViewController,AVCaptureMetadataOutputObjectsDelegate,SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var bookCover: UIImageView!
    @IBOutlet weak var microPhone: UIButton!
    @IBOutlet weak var isbn: UILabel!
    
    //flags
    var isScanning = false
    var isListening = false
    var isbnNo = ""
    
    //scan
    var captureSession : AVCaptureSession!
    var scanBarView:UIView?
    var scanPreviewLayer : AVCaptureVideoPreviewLayer?
    
    //speech
    let speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-AU"))
    var scanRequest : SFSpeechAudioBufferRecognitionRequest?
    var speechRecognicationTask : SFSpeechRecognitionTask?
    
    
    //provides audio input
    let audioEngine = AVAudioEngine()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        microPhone.backgroundColor = UIColor.green
        
        guard let speechRecognizer = speechRecognizer else {
            return
        }
        
        speechRecognizer.delegate = self
        
        //request authorization
        SFSpeechRecognizer.requestAuthorization({ (auth) in
            
            switch(auth) {
                
            case .authorized:
                print("start scanning")
                self.microPhone.isHidden = false
            case .denied:
                print("denied")
            case .notDetermined:
                print("not determined")
            case .restricted:
                print("restricted")
                
            }
            
        })
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func microPhoneClicked(_ sender: UIButton) {
        
        if !isListening {
            
            microPhone.backgroundColor = UIColor.red
            recognizeSpeech()
            isListening = true
            
        }else {
            
            microPhone.backgroundColor = UIColor.green
            stopMicroPhone()
            isListening = false
        }
        
    }
    
    //MARK:- speech recognication
    func recognizeSpeech(){
        
        //cancel previous speech recognication
        if let speechRecognicationTask = speechRecognicationTask {
            speechRecognicationTask.cancel()
            self.speechRecognicationTask = nil
        }
        
        //set audio context
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSessionCategoryRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
            
        } catch {
            print("error in setting audio session properties.")
        }
        
        //speech recognication request to recognize live speech through device microphone
        scanRequest = SFSpeechAudioBufferRecognitionRequest()
        
        
        guard let inputNode = audioEngine.inputNode else {
            return
        }
        
        guard let scanRequest = scanRequest else {
            return
        }
        
        scanRequest.shouldReportPartialResults = true
        
        //add audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            
            self.scanRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        }
        catch{
            print("audio engine couldn't start")
        }
        
        //recognize speech from audio source
        speechRecognicationTask = speechRecognizer?.recognitionTask(with: scanRequest, resultHandler: {(result, error) in
            
            if result != nil   {
                
                if let command = result?.bestTranscription.formattedString {
                    
                    let commands = command.components(separatedBy: " ")
                    
                    
                    guard let lastCommand =  commands.last?.lowercased()  else {
                        return
                    }
                    
                    print(lastCommand)
                    if lastCommand == "start"  {
                        
                        //remove image from imageview
                        if self.bookCover.image != nil {
                            self.bookCover.image = nil
                        }
                        
                        print("started")
                        if !self.isScanning {
                            self.scanBookISBN()
                            self.isScanning = true
                        }
                        
                    }
                        
                    else if lastCommand == "stop" && self.isScanning  {
                        
                        print("inside stop")
                        
                        self.stopScanning()
                    }
                    
                }
                
            }
        })
        
    }
    
    func stopMicroPhone(){
        self.audioEngine.stop()
        
        self.audioEngine.inputNode?.removeTap(onBus: 0)
        
        self.scanRequest = nil
        self.speechRecognicationTask = nil
        
        if isScanning {
            stopScanning()
        }
        
    }
    
    
    
    //MARK:- scanning
    
    func scanBookISBN(){
        
        let scanningDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        do{
            let input = try AVCaptureDeviceInput(device: scanningDevice)
            
            captureSession = AVCaptureSession()
            captureSession.addInput(input)
            
            //configure meta data output
            let capturedMetaData = AVCaptureMetadataOutput()
            captureSession.addOutput(capturedMetaData)
            
            capturedMetaData.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            capturedMetaData.metadataObjectTypes = [AVMetadataObjectTypeEAN13Code]
            
            
            //video preview layer
            scanPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            scanPreviewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            scanPreviewLayer?.frame = self.view.frame
            scanPreviewLayer?.zPosition = -1
            view.layer.addSublayer(scanPreviewLayer!)
            
            
            //green bar when an EAN13 bar code is scanned
            scanBarView = UIView()
            
            if let scanBarView = scanBarView {
                
                scanBarView.layer.borderColor = UIColor.green.cgColor
                scanBarView.layer.borderWidth = 5
                view.addSubview(scanBarView)
                view.bringSubview(toFront: scanBarView)
            }
            
            //clear previous captured ISBN
            isbn.text = "ISBN "
            
            //start capture
            captureSession.startRunning()
            
        }catch {
            print(error)
        }
        
    }
    
    
    
    //MARK: decode scanned code
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        
        
        if metadataObjects == nil || metadataObjects.isEmpty {
            
            scanBarView?.frame = CGRect.zero
            print("No barcode is detected")
            return
        }
        
        //get metadata
        let metadata = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        if metadata.type == AVMetadataObjectTypeEAN13Code {
            
            let barCodeObject = scanPreviewLayer?.transformedMetadataObject(for: metadata)
            scanBarView?.frame = barCodeObject!.bounds
            
            if metadata.stringValue != nil {
                print(metadata.stringValue)
                isbnNo = metadata.stringValue
                isbn.text = "ISBN: " + isbnNo
                
                
            }
        }
        
    }
    
    func stopScanning(){
        
        isScanning = false
        captureSession.stopRunning()
        scanPreviewLayer?.removeFromSuperlayer()
        
        if let scanBarView = scanBarView {
            
            scanBarView.frame = CGRect.zero
        }
        
        //get book cover image
        getBookCoverImage()
        
    }
    
    //MARK:- get book cover image from openlibrary.org using AlamofireImage
    func getBookCoverImage(){
        
        if !isbnNo.isEmpty{
            
            let bookCoverURL = "http://covers.openlibrary.org/b/isbn/" + isbnNo + "-L.jpg"
            
            Alamofire.request(bookCoverURL).responseImage { response in
                
                //if there is no image in openlibrary a blank image is sent
                if let image = response.result.value {
                    print("image downloaded: \(image)")
                    self.bookCover.image = image
                    self.bookCover.contentMode = .scaleAspectFit
                    
                }
            }
            
            
        }
        
    }
}

