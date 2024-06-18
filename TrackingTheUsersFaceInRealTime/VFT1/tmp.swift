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
    //        let otherOrientation = exifOrientationForCurrentDeviceOrientation(exifOrientationForDeviceOrientation(.unknown))
    
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
        // Perform face landmark tracking on detected faces.
        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
        
        // Perform landmark detection on tracked faces.
        for trackingRequest in newTrackingRequests {
            
            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { [self] (request, error) in
                
                if error != nil {
                    print("FaceLandmarks error: \(String(describing: error)).")
                }
                
                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                      let results = landmarksRequest.results else {
                    return
                }
                
                self.drawFaceObservations(results)
                
                for observation in results {
                    //                let observation = results[0]
                    if let rotatedCroppedImage = self.getRotatedCroppedImage(from: pixelBuffer, with: observation, orientation: exifOrientation) {
                        // Convert UIImage to CGImage
                        guard let cgImage = rotatedCroppedImage.cgImage else {
                            print("Failed to convert UIImage to CGImage.")
                            return
                        }
                        
                        // save an UIImage
                        //                        UIImageWriteToSavedPhotosAlbum(rotatedCroppedImage, nil, nil, nil)
                        
                        self.processImage(image: rotatedCroppedImage)
                        
                        // Update the contents and frame of rotatedCroppedLayer
                        DispatchQueue.main.async {
                            self.rotatedCroppedLayer?.contents = cgImage
                            self.rotatedCroppedLayer?.frame = CGRect(x: 0, y: 0, width: rotatedCroppedImage.size.width, height: rotatedCroppedImage.size.height)
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
                try imageRequestHandler.perform(faceLandmarkRequests) // detected results appear
            } catch let error as NSError {
                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
            }
        }
    }
}
