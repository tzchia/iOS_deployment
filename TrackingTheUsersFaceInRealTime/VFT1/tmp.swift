public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
    if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
        requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        print("Failed to obtain a CVPixelBuffer for the current output frame.")
        return
    }
    let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
    
    // Reset tracking requests if none are valid
    if self.trackingRequests?.isEmpty ?? true {
        self.trackingRequests = nil
    }
    
    if self.trackingRequests == nil {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: requestHandlerOptions)
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

    do {
        try self.sequenceRequestHandler.perform(self.trackingRequests!, on: pixelBuffer, orientation: exifOrientation)
    } catch let error as NSError {
        NSLog("Failed to perform SequenceRequest: %@", error)
    }

    var newTrackingRequests = [VNTrackObjectRequest]()
    for trackingRequest in self.trackingRequests! {
        guard let results = trackingRequest.results, let observation = results.first as? VNDetectedObjectObservation else {
            continue
        }

        if !trackingRequest.isLastFrame {
            if observation.confidence > 0.7 {
                trackingRequest.inputObservation = observation
                newTrackingRequests.append(trackingRequest)
            } else {
                trackingRequest.isLastFrame = true
            }
        }
    }
    
    self.trackingRequests = newTrackingRequests
    
    if newTrackingRequests.isEmpty {
        self.trackingRequests = nil
        return
    }

    var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
    for trackingRequest in newTrackingRequests {
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { [weak self] (request, error) in
            guard let self = self else { return }
            if let error = error {
                print("FaceLandmarks error: \(error).")
                return
            }
            guard let results = request.results as? [VNFaceObservation] else {
                return
            }
            self.drawFaceObservations(results)
            for observation in results {
                if let rotatedCroppedImage = self.getRotatedCroppedImage(from: pixelBuffer, with: observation, orientation: exifOrientation) {
                    guard let cgImage = rotatedCroppedImage.cgImage else {
                        print("Failed to convert UIImage to CGImage.")
                        return
                    }
                    self.processImage(image: rotatedCroppedImage)
                    DispatchQueue.main.async {
                        self.rotatedCroppedLayer?.contents = cgImage
                        self.rotatedCroppedLayer?.frame = CGRect(x: 0, y: 0, width: rotatedCroppedImage.size.width, height: rotatedCroppedImage.size.height)
                    }
                }
            }
        }
        guard let trackingResults = trackingRequest.results, let observation = trackingResults.first as? VNDetectedObjectObservation else {
            continue
        }
        let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
        faceLandmarksRequest.inputFaceObservations = [faceObservation]
        faceLandmarkRequests.append(faceLandmarksRequest)
    }
    
    let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: requestHandlerOptions)
    do {
        try imageRequestHandler.perform(faceLandmarkRequests)
    } catch let error as NSError {
        NSLog("Failed to perform FaceLandmarkRequest: %@", error)
    }
}
