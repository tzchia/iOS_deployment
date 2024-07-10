import UIKit
import AVKit
import Vision
import Accelerate

@available(iOS 15.0, *)
class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Main view for showing camera content.
    @IBOutlet weak var previewView: UIView?
    
    // AVCapture variables to hold sequence data
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()
    
    // Layer UI for drawing Vision results
    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    var detectedFaceLandmarksShapeLayer: CAShapeLayer?
    var predictionTextLayer: CATextLayer?
    
    // output layer
    var rotatedCroppedLayer: CALayer?
    
    // Vision requests
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    // alignment
    var angle: CGFloat = 0.0
    
    // face anti-spoofing model
    var predictionText = "live or\n spoof?"
    private var model: _0708_mcl_run0?
    
    // face detection confidence
    var Confidence: Float = 0.0
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            // Initialize the model
            model = try _0708_mcl_run0(configuration: MLModelConfiguration())
        } catch {
            // Handle initialization error
            print("Error initializing model: \(error)")
        }
        
        // Initialize rotatedCroppedLayer
        rotatedCroppedLayer = CALayer()
        
        self.session = self.setupAVCaptureSession()
        
        self.prepareVisionRequest()
        
        // Global Queue
//        DispatchQueue.global(qos: .background).async {
//        self.session?.startRunning()
//        }
        
        // Custom Queue
        let backgroundQueue = DispatchQueue(label: "com.yourapp.capturesession")
        backgroundQueue.async { [weak self] in
            self?.session!.startRunning()
        }
        
        // Add a new layer for displaying rotated and cropped content on the bottom half of the screen
        if let rotatedCroppedLayer = self.rotatedCroppedLayer {
            rotatedCroppedLayer.backgroundColor = UIColor.black.cgColor
            rotatedCroppedLayer.frame = CGRect(x: 0, y: 0, width: 224, height: 224)
            self.view.layer.addSublayer(rotatedCroppedLayer)
        } else {
            print("Error: rotatedCroppedLayer is nil.")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    // MARK: AVCapture Setup
    
    /// - Tag: CreateCaptureSession
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        do {
            let inputDevice = try self.configureFrontCamera(for: captureSession)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            self.designatePreviewLayer(for: captureSession)
            return captureSession
        } catch let executionError as NSError {
            self.presentError(executionError)
        } catch {
            self.presentErrorAlert(message: "An unexpected failure has occured")
        }
        
        self.teardownAVCapture()
        
        return nil
    }
    
    /// - Tag: ConfigureDeviceResolution
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "ViewController", code: 1, userInfo: nil)
    }
    
    /// - Tag: CreateSerialDispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured.
        // A serial dispatch queue must be used to guarantee that video frames will be delivered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VisionFaceTrack")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        
        if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        
        self.videoDataOutput = videoDataOutput
        self.videoDataOutputQueue = videoDataOutputQueue
        
        self.captureDevice = inputDevice
        self.captureDeviceResolution = resolution
    }
    
    /// - Tag: DesignatePreviewLayer
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer = videoPreviewLayer
        
        videoPreviewLayer.name = "CameraPreview"
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        if let previewRootLayer = self.previewView?.layer {
            self.rootLayer = previewRootLayer

            previewRootLayer.masksToBounds = true
            videoPreviewLayer.frame = previewRootLayer.bounds

            previewRootLayer.addSublayer(videoPreviewLayer) // display the content of frontal camera to screen
        }
    }
    
    // Removes infrastructure for AVCapture as part of cleanup.
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
        
        if let previewLayer = self.previewLayer {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
        }
    }
    
    // MARK: Helper Methods for Error Presentation
    
    fileprivate func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        self.present(alertController, animated: true)
    }
    
    fileprivate func presentError(_ error: NSError) {
        self.presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
    }
    
    // MARK: Helper Methods for Handling Device Orientation & EXIF
    
    fileprivate func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .unknown:
            return .right // .rightMirrored
        default:
            return .right
        }
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    // MARK: Performing Vision Requests
    
    /// - Tag: WriteCompletionHandler
    fileprivate func prepareVisionRequest() {
        
        self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
            
            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                  let results = faceDetectionRequest.results else {
                return
            }
            DispatchQueue.main.async {
                requests = []
                // Add the observations to the tracking list
                for observation in results { // results.count <= 1
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest) // requests.count growing
                }
                self.trackingRequests = requests
            }
        })
        
        // Start with detection.  Find face, then track it.
        self.detectionRequests = [faceDetectionRequest]
        self.sequenceRequestHandler = VNSequenceRequestHandler()
        self.setupVisionDrawingLayers()
    }
    
    // MARK: Drawing Vision Observations
    
    fileprivate func setupVisionDrawingLayers() {
        let captureDeviceResolution = self.captureDeviceResolution
        
        let captureDeviceBounds = CGRect(x: 0,
                                         y: 0,
                                         width: captureDeviceResolution.width,
                                         height: captureDeviceResolution.height)
        
        let captureDeviceBoundsCenterPoint = CGPoint(x: captureDeviceBounds.midX,
                                                     y: captureDeviceBounds.midY)
        
        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)
        
        guard let rootLayer = self.rootLayer else {
            self.presentErrorAlert(message: "view was not property initialized")
            return
        }
        
        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.anchorPoint = normalizedCenterPoint
        overlayLayer.bounds = captureDeviceBounds // (3088, 2316)
        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        
        let faceRectangleShapeLayer = CAShapeLayer()
        faceRectangleShapeLayer.name = "RectangleOutlineLayer"
        faceRectangleShapeLayer.bounds = captureDeviceBounds
        faceRectangleShapeLayer.anchorPoint = normalizedCenterPoint
        faceRectangleShapeLayer.position = captureDeviceBoundsCenterPoint
        faceRectangleShapeLayer.fillColor = nil
        faceRectangleShapeLayer.strokeColor = UIColor.green.withAlphaComponent(0.7).cgColor
        faceRectangleShapeLayer.lineWidth = 5
        faceRectangleShapeLayer.shadowOpacity = 0.7
        faceRectangleShapeLayer.shadowRadius = 5
        
        let faceLandmarksShapeLayer = CAShapeLayer()
        faceLandmarksShapeLayer.name = "FaceLandmarksLayer"
        faceLandmarksShapeLayer.bounds = captureDeviceBounds
        faceLandmarksShapeLayer.anchorPoint = normalizedCenterPoint
        faceLandmarksShapeLayer.position = captureDeviceBoundsCenterPoint
        faceLandmarksShapeLayer.fillColor = nil
        faceLandmarksShapeLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.7).cgColor
        faceLandmarksShapeLayer.lineWidth = 3
        faceLandmarksShapeLayer.shadowOpacity = 0.7
        faceLandmarksShapeLayer.shadowRadius = 5
        
//        // Calculate the position for the prediction text layer
//        let screenWidth = captureDeviceResolution.width // 3088
//        let screenHeight = captureDeviceResolution.height // 2316

        let predictionTextLayer = CATextLayer()
        predictionTextLayer.string = self.predictionText
        predictionTextLayer.fontSize = 100 // Increase font size
        predictionTextLayer.foregroundColor = UIColor.blue.cgColor
        predictionTextLayer.alignmentMode = .center // Align text to the center horizontally
        predictionTextLayer.frame = CGRect(x: 0, y: 0, width: 1000, height: 300)
        predictionTextLayer.position = CGPoint(x: 1200, y: 2100) // origin: right-bottom

        // Rotate the text layer to flip it vertically
        let verticalFlipTransform = CATransform3DMakeRotation(CGFloat.pi, 1.0, 0.0, 0.0)
        // Flip the text layer horizontally
        let horizontalFlipTransform = CATransform3DMakeScale(-1.0, 1.0, 1.0)
        // Combine both transforms
        predictionTextLayer.transform = CATransform3DConcat(verticalFlipTransform, horizontalFlipTransform)
        
        overlayLayer.addSublayer(predictionTextLayer)
        overlayLayer.addSublayer(faceRectangleShapeLayer)
        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
        rootLayer.addSublayer(overlayLayer)
        
        self.detectionOverlayLayer = overlayLayer
        self.detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
        self.detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer
        self.predictionTextLayer = predictionTextLayer
        
        self.updateLayerGeometry()
    }
    
    fileprivate func updateLayerGeometry() {
        guard let overlayLayer = self.detectionOverlayLayer,
              let rootLayer = self.rootLayer,
              let previewLayer = self.previewLayer
        else {
            return
        }
        
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let videoPreviewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        var rotation: CGFloat
        var scaleX: CGFloat
        var scaleY: CGFloat
        
        // Rotate the layer into screen orientation.
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            rotation = 180
            scaleX = videoPreviewRect.width / captureDeviceResolution.width
            scaleY = videoPreviewRect.height / captureDeviceResolution.height
            
        case .landscapeLeft:
            rotation = 90
            scaleX = videoPreviewRect.height / captureDeviceResolution.width
            scaleY = scaleX
            
        case .landscapeRight:
            rotation = -90
            scaleX = videoPreviewRect.height / captureDeviceResolution.width
            scaleY = scaleX
            
        default:
            rotation = 0
            scaleX = videoPreviewRect.width / captureDeviceResolution.width // 3088
            scaleY = videoPreviewRect.height / captureDeviceResolution.height // 2316
//            rotation = 90
//            scaleX = videoPreviewRect.height / captureDeviceResolution.width // enlarger this only do so to borderline, but not content included
//            scaleY = scaleX
        }
        
        // Scale and mirror the image to ensure upright presentation.
        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
            .scaledBy(x: -scaleX, y: -scaleY)
//        let affineTransform = CGAffineTransform(scaleX: -scaleX, y: -scaleY)
        overlayLayer.setAffineTransform(affineTransform)
        
        // Cover entire screen UI.
        let rootLayerBounds = rootLayer.bounds // (834, 1194)
        overlayLayer.position = CGPoint(x: rootLayerBounds.midX, y: rootLayerBounds.midY) // (417, 597)
    }
    
    fileprivate func addPoints(in landmarkRegion: VNFaceLandmarkRegion2D, to path: CGMutablePath, applying affineTransform: CGAffineTransform, closingWhenComplete closePath: Bool) {
        let pointCount = landmarkRegion.pointCount
        if pointCount > 1 {
            let points: [CGPoint] = landmarkRegion.normalizedPoints
            path.move(to: points[0], transform: affineTransform)
            path.addLines(between: points, transform: affineTransform)
            if closePath {
                path.addLine(to: points[0], transform: affineTransform)
                path.closeSubpath()
            }
        }
    }
    
    fileprivate func addIndicators(to faceRectanglePath: CGMutablePath, faceLandmarksPath: CGMutablePath, for faceObservation: VNFaceObservation) {
        let displaySize = self.captureDeviceResolution
        
        let faceBounds = VNImageRectForNormalizedRect(faceObservation.boundingBox, Int(displaySize.width), Int(displaySize.height))
        faceRectanglePath.addRect(faceBounds)
        
        if let landmarks = faceObservation.landmarks {
            // Landmarks are relative to -- and normalized within --- face bounds
            let affineTransform = CGAffineTransform(translationX: faceBounds.origin.x, y: faceBounds.origin.y)
                .scaledBy(x: faceBounds.size.width, y: faceBounds.size.height)
            
            // Treat eyebrows and lines as open-ended regions when drawing paths.
            let openLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEyebrow,
                landmarks.rightEyebrow,
                landmarks.faceContour,
                landmarks.noseCrest,
                landmarks.medianLine
            ]
            for openLandmarkRegion in openLandmarkRegions where openLandmarkRegion != nil {
                self.addPoints(in: openLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: false)
            }
            
            // Draw eyes, lips, and nose as closed regions.
            let closedLandmarkRegions: [VNFaceLandmarkRegion2D?] = [
                landmarks.leftEye,
                landmarks.rightEye,
                landmarks.outerLips,
                landmarks.innerLips,
                landmarks.nose
            ]
            for closedLandmarkRegion in closedLandmarkRegions where closedLandmarkRegion != nil {
                self.addPoints(in: closedLandmarkRegion!, to: faceLandmarksPath, applying: affineTransform, closingWhenComplete: true)
            }
            
            // calculate face angle and center via pupils and arctan
            let leftPupil = landmarks.leftPupil?.normalizedPoints.first
            let rightPupil = landmarks.rightPupil?.normalizedPoints.first
            let length1 = rightPupil!.x - leftPupil!.x
            let length2 = rightPupil!.y - leftPupil!.y
            
            let angle = atan(length1/length2) //*180/Double.pi
            if (angle > 0) {self.angle = Double.pi/2 - angle} else {self.angle = 3*Double.pi/2 - angle}
        }
    }
    
    /// - Tag: DrawPaths
    fileprivate func drawFaceObservations(_ faceObservations: [VNFaceObservation]) {
        guard let faceRectangleShapeLayer = self.detectedFaceRectangleShapeLayer,
              let faceLandmarksShapeLayer = self.detectedFaceLandmarksShapeLayer
        else {
            return
        }
        
        CATransaction.begin()
        CATransaction.setValue(NSNumber(value: true), forKey: kCATransactionDisableActions)
        
        let faceRectanglePath = CGMutablePath()
        let faceLandmarksPath = CGMutablePath()
        
        for faceObservation in faceObservations {
            self.addIndicators(to: faceRectanglePath,
                               faceLandmarksPath: faceLandmarksPath,
                               for: faceObservation)
        }
        
        // Set the paths for the layers
        faceRectangleShapeLayer.path = faceRectanglePath
        faceLandmarksShapeLayer.path = faceLandmarksPath
        
        // Update the layer geometry
        self.updateLayerGeometry()
        
        CATransaction.commit()
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    /// - Tag: PerformRequests
    // Handle delegate method callback on receiving a sample buffer.
    // Declare reusable properties at the class level
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        
        // Retrieve camera intrinsic data
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        // Convert CMSampleBuffer to CVPixelBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }
        
        // Determine the current device orientation for correct image orientation
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
        
        // Check if there are any tracking requests
        guard let requests = self.trackingRequests, !requests.isEmpty else {
            // No tracking object detected, so perform initial detection
            let detectFaceRequest = VNDetectFaceRectanglesRequest { [weak self] (request, error) in
                guard let self = self else { return }
                if let error = error {
                    print("Face detection error: \(error.localizedDescription)")
                    return
                }
                
                guard let results = request.results as? [VNFaceObservation], !results.isEmpty else {
                    print("No faces detected.")
                    return
                }
                
                // Find the largest face
                let largestFace = results.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                
                guard let largestFaceObservation = largestFace else { return }
                
                // Create a new tracking request for the largest face
                let trackingRequest = VNTrackObjectRequest(detectedObjectObservation: largestFaceObservation)
                self.trackingRequests = [trackingRequest]
            }
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                try imageRequestHandler.perform([detectFaceRequest])
            } catch let error as NSError {
                NSLog("Failed to perform FaceRectangleRequest: %@", error)
            }
            return
        }
        
        // Track the detected faces and perform further processing
        do {
            try self.sequenceRequestHandler.perform(requests,
                                                    on: pixelBuffer,
                                                    orientation: exifOrientation)
        } catch let error as NSError {
            NSLog("Failed to perform SequenceRequest: %@", error)
        }
        
        // Setup the next round of tracking
        var newTrackingRequests = [VNTrackObjectRequest]()
        for trackingRequest in requests {
            guard let results = trackingRequest.results else { continue }
            guard let observation = results.first as? VNDetectedObjectObservation else { continue }
            
            if !trackingRequest.isLastFrame {
                self.Confidence = observation.confidence
                if self.Confidence > 0.7 { // 0.3
                    trackingRequest.inputObservation = observation
                } else {
                    trackingRequest.isLastFrame = true
                    newTrackingRequests = []
                }
                newTrackingRequests.append(trackingRequest)
            }
        }
        self.trackingRequests = newTrackingRequests
        
        if newTrackingRequests.isEmpty {
            // Nothing to track, so abort.
            return
        }
        
        if self.Confidence > 0.7 {
            // Perform face landmark tracking on the largest detected face.
            let trackingRequest = newTrackingRequests.first!
            let faceLandmarksRequest = VNDetectFaceLandmarksRequest { [weak self] (request, error) in
                guard let self = self else { return }
                if let error = error {
                    print("FaceLandmarks error: \(String(describing: error)).")
                    return
                }
                
                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                      let results = landmarksRequest.results else {
                    return
                }
                
                self.drawFaceObservations(results)
                
                for observation in results {
                    if let rotatedCroppedImage = self.getRotatedCroppedImage(from: pixelBuffer, with: observation, orientation: exifOrientation) {
                        // Convert UIImage to CGImage
                        guard let cgImage = rotatedCroppedImage.cgImage else {
                            print("Failed to convert UIImage to CGImage.")
                            return
                        }
                        
                        // Save the UIImage or process it as needed
                        self.processImage(image: rotatedCroppedImage)
                        
                        // Update the contents and frame of rotatedCroppedLayer
                        DispatchQueue.main.async {
                            self.rotatedCroppedLayer?.contents = cgImage
                            self.rotatedCroppedLayer?.frame = CGRect(x: 0, y: 0, width: rotatedCroppedImage.size.width, height: rotatedCroppedImage.size.height)
                        }
                    }
                }
            }
            
            guard let trackingResults = trackingRequest.results else { return }
            guard let observation = trackingResults.first as? VNDetectedObjectObservation else { return }
            
            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
            faceLandmarksRequest.inputFaceObservations = [faceObservation]
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                try imageRequestHandler.perform([faceLandmarksRequest])
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }
        }
    }

    // Helper function to get rotated and cropped image
    func getRotatedCroppedImage(from pixelBuffer: CVPixelBuffer, with observation: VNFaceObservation, orientation: CGImagePropertyOrientation) -> UIImage? {
        // Convert pixel buffer to UIImage
        guard let bkg = UIImage(pixelBuffer: pixelBuffer) else { // width = 3088, height = 2316
            print("Failed to convert pixel buffer to UIImage.")
            return nil
        }
        
        // if self.angle add here, it would be cropped irregularly
        let rotatedBKG: UIImage?
        switch orientation {
        case .right, .rightMirrored:
            rotatedBKG = bkg.rotated(by: Double.pi/2)
        default:
            rotatedBKG = bkg
        }
        
        let faceSize = rotatedBKG!.size // width=3088, height=2316

        // Get the bounding box of the face in image coordinates
        let boundingBox = observation.boundingBox // 0-1
        
        let enlargedBB = CGRect(
            x: boundingBox.origin.x - boundingBox.size.width * 0.1,
            y: boundingBox.origin.y - boundingBox.size.height * 0.05,
            width: boundingBox.size.width * 1.2,
            height: boundingBox.size.height * 1.1
        )
        
        // coordinates of camera and world
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -faceSize.height)
        let translate = CGAffineTransform.identity.scaledBy(x: faceSize.width, y: faceSize.height)
        let facebounds = enlargedBB.applying(translate).applying(transform)
        
        // Crop the face image
        let croppedImage = rotatedBKG!.crop(to: facebounds)
        
        // Rotate the cropped image
        let rotatedCropped = croppedImage!.rotated(by: self.angle)
       
        // Resize the image to 224x224
        let resizedRotatedCroppedImage = rotatedCropped?.resize(to: CGSize(width: 224, height: 224)) //rotatedCropped
        
        return resizedRotatedCroppedImage //resizedRotatedCroppedImage
    }
    
    func softmax(_ input: [Double]) -> [Double] {
        // Step 1: Find the maximum value in the input array for numerical stability
        guard let maxValue = input.max() else { return [] }
        
        // Step 2: Subtract the maximum value from each element in the input array
        let adjustedInput = input.map { $0 - maxValue }

        // Step 3: Compute the exponentials of the elements
        var expInput = [Double](repeating: 0.0, count: adjustedInput.count)
        vvexp(&expInput, adjustedInput, [Int32(adjustedInput.count)])
        
        // Step 4: Compute the sum of the exponentials
        let sumExp = expInput.reduce(0, +)

        // Step 5: Divide each exponential by the sum of exponentials
        let result = expInput.map { $0 / sumExp }

        return result
    }
    
    func convertToArray(_ mlMultiArray: MLMultiArray) -> [Double]? {
        let count = mlMultiArray.count
        var array = [Double](repeating: 0.0, count: count)
        for i in 0..<count {
            array[i] = mlMultiArray[i].doubleValue
        }
        return array
    }
    
    func processImage(image: UIImage) {
        // 將處理後的圖片轉換為像素緩衝區，以供模型輸入使用 //newImage
        guard let pixelBuffer = image.toPixelBuffer(pixelFormatType:  kCVPixelFormatType_32ARGB, width: 224, height: 224) else {
            return
        } //kCVPixelFormatType_32ARGB,kCVPixelFormatType_32BGRA
        
        // 使用模型和輸入的像素緩衝區進行預測
        guard let prediction = try? model?.prediction(image: pixelBuffer) else { return }
        let probability = prediction.var_4088

        // Define the precision you want for p0 and p1
        let precision = 3
        
        // Apply the softmax function along the specified dimension (axis).
        let inputArray = convertToArray(probability)
        let softmaxOutput = softmax(inputArray!)
        
        let formattedS1 = String(format: "%.\(precision)f", softmaxOutput[1])

        var label: String
        if softmaxOutput[1] < 0.9 {
            label = "spoof"
        } else {
            label = "live"
//            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        // Update predictionText with formatted probabilities
        let updatedPredictionText = "\(label)\n\(formattedS1)"
        
        // Ensure UI updates are performed on the main queue
        DispatchQueue.main.async {
            self.predictionTextLayer?.string = updatedPredictionText
        }
    }
}


extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        self.init(cgImage: cgImage)
    }

    func crop(to rect: CGRect) -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }

        guard let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage)
    }

    func rotated(by radians: CGFloat) -> UIImage? {
        // Calculate the size of the rotated image
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size

        // Create a context to draw the rotated image
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, scale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Move the origin to the middle of the image so we will rotate and scale around the center.
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        
        // Rotate the image
        context.rotate(by: radians)

        // Draw the image
        draw(in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))

        // Get the rotated image
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()

        return rotatedImage
    }
    
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // 將UIImage轉換為CVPixelBuffer
    func toPixelBuffer(pixelFormatType: OSType, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: NSNumber] = [
            kCVPixelBufferCGImageCompatibilityKey as String: NSNumber(booleanLiteral: true),
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: NSNumber(booleanLiteral: true)
        ]
        
        // 創建CVPixelBuffer
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormatType, attrs as CFDictionary, &pixelBuffer)
        
        guard status == kCVReturnSuccess else {
            return nil
        }
        
        // 鎖定CVPixelBuffer 的基地址
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        // 創建CGContext
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        // 調整座標系
        context?.translateBy(x: 0, y: CGFloat(height))
        context?.scaleBy(x: 1.0, y: -1.0)
        
        // 繪製圖像
        UIGraphicsPushContext(context!)
        draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        UIGraphicsPopContext()
        
        // 解鎖基地址並返回CVPixelBuffer
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    func correctedOrientation() -> UIImage {
        guard let cgImage = self.cgImage else {
            return self
        }
        
        if self.imageOrientation == .up {
            return self
        }
        
        var transform = CGAffineTransform.identity
        switch self.imageOrientation {
        case .down, .downMirrored:
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }
        
        guard let colorSpace = cgImage.colorSpace else { return self }
        
        guard let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0, space: colorSpace, bitmapInfo: cgImage.bitmapInfo.rawValue) else {
            return self
        }
        
        context.concatenate(transform)
        
        switch self.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.height, height: cgImage.width))
        default:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        
        guard let newCGImage = context.makeImage() else { return self }
        
        return UIImage(cgImage: newCGImage)
    }
}

extension CGRect {
    var center : CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}
