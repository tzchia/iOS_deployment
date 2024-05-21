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
    var predictionText = "I think this is a ..."
    private var model: flip_v_0322_255_float16?
    
    // MARK: UIViewController overrides
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            // Initialize the model
            model = try flip_v_0322_255_float16(configuration: MLModelConfiguration())
        } catch {
            // Handle initialization error
            print("Error initializing model: \(error)")
        }
        
        // Initialize rotatedCroppedLayer
        rotatedCroppedLayer = CALayer()
        
        self.session = self.setupAVCaptureSession()
        
        self.prepareVisionRequest()
        
        self.session?.startRunning()
        
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
    
    // Ensure that the interface stays locked in Portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    // Ensure that the interface stays locked in Portrait.
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    // MARK: AVCapture Setup
    
    /// - Tag: CreateCaptureSession
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        ...
    }
    
    /// - Tag: ConfigureDeviceResolution
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        ...
    }
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        ...
    }
    
    /// - Tag: CreateSerialDispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        ...
    }
    
    /// - Tag: DesignatePreviewLayer
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        ...
    }
    
    // Removes infrastructure for AVCapture as part of cleanup.
    fileprivate func teardownAVCapture() {
        ...
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
        ...
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    // MARK: Performing Vision Requests
    
    /// - Tag: WriteCompletionHandler
    fileprivate func prepareVisionRequest() {
        
        //self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
            
            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                  let results = faceDetectionRequest.results else {
                return
            }
            if results.isEmpty {
                self.trackingRequests?.removeAll()
            }
            DispatchQueue.main.async {
                // Add the observations to the tracking list
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
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
        
        // Calculate the position for the prediction text layer
        let screenWidth = captureDeviceResolution.width // 3088
        let screenHeight = captureDeviceResolution.height // 2316

        let predictionTextLayer = CATextLayer()
        predictionTextLayer.string = self.predictionText
        predictionTextLayer.fontSize = 100 // Increase font size
        predictionTextLayer.foregroundColor = UIColor.blue.cgColor
        predictionTextLayer.alignmentMode = .center // Align text to the center horizontally
        predictionTextLayer.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 250)
        predictionTextLayer.position = CGPoint(x: screenWidth/2, y: screenHeight-250)

        // Rotate the text layer to flip it vertically
        predictionTextLayer.transform = CATransform3DMakeRotation(CGFloat.pi, 1.0, 0.0, 0.0)

        
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
        }
        
        // Scale and mirror the image to ensure upright presentation.
        let affineTransform = CGAffineTransform(rotationAngle: radiansForDegrees(rotation))
            .scaledBy(x: scaleX, y: -scaleY)
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
            if (angle > 0) {self.angle = -angle + Double.pi/2} else {self.angle = -angle - Double.pi/2}
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
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        
        // Retrieve camera intrinsic data
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
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
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                guard let detectRequests = self.detectionRequests else {
                    return
                }
                try imageRequestHandler.perform(detectRequests)
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
        
        // Setup the next round of tracking.
        var newTrackingRequests = [VNTrackObjectRequest]()
        for trackingRequest in requests {
            
            guard let results = trackingRequest.results else {
                return
            }
            
            guard let observation = results[0] as? VNDetectedObjectObservation else {
                return
            }
            
            if !trackingRequest.isLastFrame {
                if observation.confidence > 0.3 {
                    trackingRequest.inputObservation = observation
                } else {
                    trackingRequest.isLastFrame = true
                }
                newTrackingRequests.append(trackingRequest)
            }
        }
        self.trackingRequests = newTrackingRequests
        
        if newTrackingRequests.isEmpty {
            // Nothing to track, so abort.
            return
        }
        
        // Perform face landmark tracking on detected faces.
        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
        
        // Perform landmark detection on tracked faces.
        for trackingRequest in newTrackingRequests {
            
            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request, error) in
                
                if error != nil {
                    print("FaceLandmarks error: \(String(describing: error)).")
                }
                
                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                      let results = landmarksRequest.results else {
                    return
                }
                
                // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
                DispatchQueue.main.async {
                    self.drawFaceObservations(results)

//                    for observation in results {
                    let observation = results[0]
                    if let rotatedCroppedImage = self.getRotatedCroppedImage(from: pixelBuffer, with: observation) {
                        // Convert UIImage to CGImage
                        guard let cgImage = rotatedCroppedImage.cgImage else {
                            print("Failed to convert UIImage to CGImage.")
                            return
                        }

                        // Update the contents and frame of rotatedCroppedLayer
                        DispatchQueue.main.async {
                            self.rotatedCroppedLayer?.contents = cgImage
                            self.rotatedCroppedLayer?.frame = CGRect(x: 0, y: 0, width: rotatedCroppedImage.size.width, height: rotatedCroppedImage.size.height)
                            self.processImage(image: rotatedCroppedImage) // seems to be a little bit smoother, but not enough
                        }
                    }
                }
            })
            
            guard let trackingResults = trackingRequest.results else {
                return
            }
            
            guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
                return
            }
            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
            faceLandmarksRequest.inputFaceObservations = [faceObservation]
            
            // Continue to track detected facial landmarks.
            faceLandmarkRequests.append(faceLandmarksRequest)
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                try imageRequestHandler.perform(faceLandmarkRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }
        }
    }
    
    // Helper function to get rotated and cropped image
    func getRotatedCroppedImage(from pixelBuffer: CVPixelBuffer, with observation: VNFaceObservation) -> UIImage? {
        // Convert pixel buffer to UIImage
        guard let faceImage = UIImage(pixelBuffer: pixelBuffer) else { // width = 3088, height = 2316
            print("Failed to convert pixel buffer to UIImage.")
            return nil
        }
        
        let flipFace = faceImage.flipHorizontally()
        let flipRotateface = flipFace!.rotated(by: -Double.pi/2)
        let frfaceSize = flipRotateface!.size // (2316, 3088)
        
        // Get the bounding box of the face in image coordinates
        let boundingBox = observation.boundingBox // 0-1
        
        // coordinates of camera and world
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -frfaceSize.height)
        let translate = CGAffineTransform.identity.scaledBy(x: frfaceSize.width, y: frfaceSize.height)
        let facebounds = boundingBox.applying(translate).applying(transform)
        
//        // Resize the bounding box by a scale factor
//        let resizedFaceRect = CGRect(x: facebounds.origin.x - (facebounds.size.width * 0.9),
//                                     y: facebounds.origin.y - (facebounds.size.height * 0.9),
//                                     width: facebounds.size.width * 1.8, //width
//                                     height: facebounds.size.height * 1.8)
        
        // Crop the face image
        let croppedImage = flipRotateface!.crop(to: facebounds)
        
        // Rotate the cropped image
        let rotatedCropped = croppedImage!.rotated(by: self.angle)
       
        // Resize the image to 224x224
        let resizedRotatedCroppedImage = rotatedCropped!.resize(to: CGSize(width: 224, height: 224))
        
        return resizedRotatedCroppedImage
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
        let probability = prediction.var_1251

        // Define the precision you want for p0 and p1
        let precision = 3
        
        // Apply the softmax function along the specified dimension (axis).
        let inputArray = convertToArray(probability)
        let softmaxOutput = softmax(inputArray!)
        let formattedS1 = String(format: "%.\(precision)f", softmaxOutput[1])

        var label: String
//        if p0 > p1 {
        if softmaxOutput[1] < 0.3 {
            label = "spoof"
        } else {
            label = "live"
        }

        // Update predictionText with formatted probabilities
        let updatedPredictionText = "label: \(label)\nsoftmax[1]: \(formattedS1)"
        
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
        ...
    }
    
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // 將UIImage轉換為CVPixelBuffer
    func toPixelBuffer(pixelFormatType: OSType, width: Int, height: Int) -> CVPixelBuffer? {
        ...
    }
    
    func flipHorizontally() -> UIImage? {
        ...
    }
}

extension CGRect {
    var center : CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}
------------------------------------------------------------------------
why is the app so slow after `self.processImage(image: rotatedCroppedImage)` added in? Do I need to modify DispatchQueue.main.async? Please highlight snippets need to me modified