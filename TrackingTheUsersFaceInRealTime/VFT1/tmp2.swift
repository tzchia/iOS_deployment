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
